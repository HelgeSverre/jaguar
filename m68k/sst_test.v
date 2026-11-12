// Runs the SingleStepTests/m68000 corpus (MIT, pinned by
// scripts/fetch-m68000-tests.sh) against the interpreter.
//
// Every test loads registers and RAM, executes one `step` and compares all
// registers (D0-D7, A0-A6, USP, SSP, SR, PC) and all RAM. Two further
// metrics are reported per file: the cycle count (`length`) and the order,
// address and data of the bus accesses. All three must match on every test
// of every file; there are no exclusions. Without the corpus the test prints
// a SKIPPED notice and passes without claiming any coverage.
//
// Environment:
//   M68K_SST_FILTER=<substring>  only run corpus files whose name contains it
//   M68K_SST_SHOW=<n>            print details of the first n failures per file
//
// Corpus conventions handled here (see the corpus README and decode.py):
// - The state PC is MAME's `m_au`, four bytes past the opcode address; the
//   two prefetched words are also present in RAM, so execution simply starts
//   at PC-4 and the final PC is compared as `cpu.pc + 4`.
// - After STOP the corpus PC is not advanced by a prefetch, so it equals
//   the address of the next instruction.
// - Tests run with the trace bit set do not include the trace exception that
//   would follow; a single `step` stops before it as well.
// - RAM is listed as 16-bit words; byte accesses appear on the bus without
//   A0 and are told apart by the UDS/LDS strobes.
// - Transactions of kind "re"/"we" are the refused bus cycles of an address
//   error and are not real accesses.
// - The bus-order metric compares every write exactly and requires the
//   corpus data-space reads to appear in order among the core's reads. The
//   core fetches an opcode when it executes it instead of prefetching, so
//   program-space reads are not comparable one to one and are skipped.
//
// Corpus caveats named in its README, and how they turn out:
// - TAS: the corpus does not model the indivisible read-modify-write bus
//   cycle and records an ordinary read followed by a write. That is also
//   what this core does, so TAS is compared in full and matches.
// - TRAPV: the README suspects a dependence on the S bit. The pinned corpus
//   traps exactly when V is set, in both modes, so TRAPV is compared in full
//   and matches.
module m68k

import os
import m68k.testbus

const corpus_dir = os.join_path(os.dir(@FILE), '..', 'data', 'tests', 'm68000')
const corpus_suffix = '.json.bin'

const reg_names = ['d0', 'd1', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7', 'a0', 'a1', 'a2', 'a3', 'a4',
	'a5', 'a6', 'usp', 'ssp', 'sr', 'pc']!
const reg_usp = 15
const reg_ssp = 16
const reg_sr = 17
const reg_pc = 18

const tx_idle = u8(0)
const tx_write = u8(1)
const tx_read = u8(2)
const tx_tas = u8(3)

struct RamWord {
	addr u32
	data u16
}

struct SstState {
mut:
	regs [19]u32
	ram  []RamWord
}

struct SstTest {
mut:
	name     string
	initial  SstState
	final    SstState
	length   u32
	expected []testbus.BusEvent // data-space reads and all writes, in bus order
}

// Reader decodes the little-endian `.json.bin` container.
struct Reader {
	data []u8
mut:
	pos int
}

fn (mut r Reader) u8() u8 {
	v := r.data[r.pos]
	r.pos++
	return v
}

fn (mut r Reader) u16() u16 {
	v := u16(r.data[r.pos]) | (u16(r.data[r.pos + 1]) << 8)
	r.pos += 2
	return v
}

fn (mut r Reader) u32() u32 {
	lo := u32(r.u16())
	return lo | (u32(r.u16()) << 16)
}

// block skips a block header (byte count, magic) after checking the magic.
fn (mut r Reader) block(magic u32) {
	r.u32()
	found := r.u32()
	if found != magic {
		fail('corpus block magic ${found:08x}, expected ${magic:08x} at offset ${r.pos}')
	}
}

fn (mut r Reader) state() SstState {
	r.block(0x01234567)
	mut st := SstState{}
	for i in 0 .. 19 {
		st.regs[i] = r.u32()
	}
	r.u32() // prefetch words: also present in RAM
	r.u32()
	count := int(r.u32())
	st.ram = []RamWord{cap: count}
	for _ in 0 .. count {
		addr := r.u32()
		st.ram << RamWord{addr, r.u16()}
	}
	return st
}

fn (mut r Reader) transactions(mut t SstTest) {
	r.block(0x456789ab)
	t.length = r.u32()
	count := int(r.u32())
	for _ in 0 .. count {
		kind := r.u8()
		r.u32() // cycles of this transaction
		if kind == tx_idle {
			continue
		}
		fc := r.u32()
		addr := r.u32()
		data := r.u32()
		uds := r.u32()
		lds := r.u32()
		is_write := kind == tx_write
		is_data_read := (kind == tx_read || kind == tx_tas) && fc & 3 == 1
		if !is_write && !is_data_read {
			continue
		}
		if uds != 0 && lds != 0 {
			t.expected << testbus.BusEvent{is_write, 2, addr, u16(data)}
		} else if uds != 0 {
			t.expected << testbus.BusEvent{is_write, 1, addr & ~u32(1), u16(data >> 8)}
		} else {
			t.expected << testbus.BusEvent{is_write, 1, addr | 1, u16(data & 0xff)}
		}
	}
}

fn (mut r Reader) test() SstTest {
	r.block(0xabc12367)
	r.block(0x89abcdef)
	name_len := int(r.u32())
	mut t := SstTest{
		name: r.data[r.pos..r.pos + name_len].bytestr()
	}
	r.pos += name_len
	t.initial = r.state()
	t.final = r.state()
	r.transactions(mut t)
	return t
}

fn load_corpus_file(path string) []SstTest {
	data := os.read_bytes(path) or { fail('cannot read ${path}: ${err}') }
	mut r := Reader{
		data: data
	}
	if r.u32() != 0x1a3f5d71 {
		fail('${path}: not a SingleStepTests .json.bin file')
	}
	count := int(r.u32())
	mut tests := []SstTest{cap: count}
	for _ in 0 .. count {
		tests << r.test()
	}
	return tests
}

// fail aborts the test run with an explicit error; it does not rely on
// `assert`, which optimized builds may strip.
@[noreturn]
fn fail(msg string) {
	eprintln('FAIL: ${msg}')
	exit(1)
}

struct Outcome {
	state  bool
	cycles bool
	bus    bool
}

fn load_state(mut cpu Cpu, mut bus testbus.TestBus, st &SstState) {
	bus.clear()
	for w in st.ram {
		bus.poke16(w.addr, w.data)
	}
	for i in 0 .. 8 {
		cpu.d[i] = st.regs[i]
	}
	for i in 0 .. 7 {
		cpu.a[i] = st.regs[8 + i]
	}
	cpu.sr = u16(st.regs[reg_sr])
	cpu.usp = st.regs[reg_usp]
	cpu.ssp = st.regs[reg_ssp]
	cpu.a[7] = if cpu.supervisor() { cpu.ssp } else { cpu.usp }
	cpu.pc = st.regs[reg_pc] - 4
}

// actual_regs returns the CPU registers in corpus order and convention.
fn actual_regs(cpu &Cpu) [19]u32 {
	mut regs := [19]u32{}
	for i in 0 .. 8 {
		regs[i] = cpu.d[i]
	}
	for i in 0 .. 7 {
		regs[8 + i] = cpu.a[i]
	}
	regs[reg_usp] = if cpu.supervisor() { cpu.usp } else { cpu.a[7] }
	regs[reg_ssp] = if cpu.supervisor() { cpu.a[7] } else { cpu.ssp }
	regs[reg_sr] = cpu.sr
	// A stopped processor has not prefetched past the STOP operand.
	regs[reg_pc] = if cpu.stopped { cpu.pc } else { cpu.pc + 4 }
	return regs
}

// ram_matches checks every expected RAM word and that nothing outside the
// expected set was written.
fn ram_matches(bus &testbus.TestBus, final &SstState) bool {
	for w in final.ram {
		if bus.peek16(w.addr) != w.data {
			return false
		}
	}
	for ev in bus.events[..bus.event_count] {
		if ev.write && !final.ram.any(it.addr == ev.addr & 0xff_fffe) {
			return false
		}
	}
	return true
}

// bus_order_matches checks that all writes happen exactly as in the corpus
// and that the corpus data-space reads appear, in order, among the reads the
// core performed (which also include instruction-stream fetches).
fn bus_order_matches(bus &testbus.TestBus, expected []testbus.BusEvent) bool {
	mut next := 0
	for ev in bus.events[..bus.event_count] {
		if next < expected.len && ev == expected[next] {
			next++
		} else if ev.write {
			return false
		}
	}
	return next == expected.len && !bus.overflowed
}

fn run_case(mut bus testbus.TestBus, t &SstTest) (Outcome, Cpu) {
	mut cpu := Cpu{}
	load_state(mut cpu, mut bus, t.initial)
	cycles := cpu.step(mut bus)
	state_ok := actual_regs(cpu) == t.final.regs && ram_matches(bus, t.final) && !cpu.halted
		&& !bus.long_access
	return Outcome{state_ok, cycles == t.length, bus_order_matches(bus, t.expected)}, cpu
}

fn describe_failure(t &SstTest, cpu &Cpu, bus &testbus.TestBus, cycles u64) string {
	mut s := '  ${t.name}: cycles ${cycles} (expected ${t.length})\n'
	actual := actual_regs(cpu)
	for i in 0 .. 19 {
		if actual[i] != t.final.regs[i] {
			s += '    ${reg_names[i]}: got ${actual[i]:08x}, expected ${t.final.regs[i]:08x} (initial ${t.initial.regs[i]:08x})\n'
		}
	}
	for w in t.final.ram {
		got := bus.peek16(w.addr)
		if got != w.data {
			s += '    ram ${w.addr:06x}: got ${got:04x}, expected ${w.data:04x}\n'
		}
	}
	for ev in bus.events[..bus.event_count] {
		if ev.write && !t.final.ram.any(it.addr == ev.addr & 0xff_fffe) {
			s += '    stray write at ${ev.addr:06x}\n'
		}
	}
	s += '    initial sr=${t.initial.regs[reg_sr]:04x} pc=${t.initial.regs[reg_pc] - 4:08x}\n'
	s += '    bus:     ' + bus.events[..bus.event_count].map(it.str()).join(' ') + '\n'
	s += '    corpus:  ' + t.expected.map(it.str()).join(' ') + '\n'
	return s
}

struct FileResult {
	name string
mut:
	total  int
	state  int
	cycles int
	bus    int
}

fn run_file(path string, mut bus testbus.TestBus, show int) FileResult {
	tests := load_corpus_file(path)
	mut res := FileResult{
		name:  os.base(path).all_before_last(corpus_suffix)
		total: tests.len
	}
	mut shown := 0
	for t in tests {
		outcome, cpu := run_case(mut bus, t)
		if outcome.state {
			res.state++
		}
		if outcome.cycles {
			res.cycles++
		}
		if outcome.bus {
			res.bus++
		}
		if shown < show && !(outcome.state && outcome.cycles && outcome.bus) {
			shown++
			print(describe_failure(t, cpu, bus, cpu.cycles))
		}
	}
	return res
}

fn test_single_step_corpus() {
	if !os.is_dir(corpus_dir) {
		println('SKIPPED: SingleStepTests/m68000 corpus not found at ${corpus_dir}')
		println('SKIPPED: run scripts/fetch-m68000-tests.sh to enable the instruction corpus gate')
		return
	}
	filter := os.getenv('M68K_SST_FILTER')
	show := os.getenv('M68K_SST_SHOW').int()
	mut files := os.ls(corpus_dir) or { fail('cannot list ${corpus_dir}: ${err}') }
	files = files.filter(it.ends_with(corpus_suffix) && it.contains(filter))
	files.sort()
	if files.len == 0 {
		println('SKIPPED: no corpus files in ${corpus_dir} match the filter "${filter}"')
		return
	}
	mut bus := testbus.new()
	mut sum := FileResult{
		name: 'TOTAL'
	}
	mut failed := []string{}
	println('file               tests   state  cycles     bus')
	for file in files {
		res := run_file(os.join_path(corpus_dir, file), mut bus, show)
		println('${res.name:-16} ${res.total:7} ${res.state:7} ${res.cycles:7} ${res.bus:7}')
		sum.total += res.total
		sum.state += res.state
		sum.cycles += res.cycles
		sum.bus += res.bus
		if res.state != res.total || res.cycles != res.total || res.bus != res.total {
			failed << res.name
		}
	}
	println('${sum.name:-16} ${sum.total:7} ${sum.state:7} ${sum.cycles:7} ${sum.bus:7}')
	if failed.len > 0 {
		fail('state, cycle or bus-order mismatches in: ${failed.join(', ')}')
	}
}
