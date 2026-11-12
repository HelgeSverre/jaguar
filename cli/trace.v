module cli

import debug
import machine

// Processor names the processor a trace follows.
enum Processor {
	m68k
	gpu
	dsp
}

fn parse_processor(name string) !Processor {
	return match name.to_lower() {
		'm68k', '68k', '68000', 'cpu' { Processor.m68k }
		'gpu' { Processor.gpu }
		'dsp' { Processor.dsp }
		else { error('unknown processor "${name}": expected m68k, gpu or dsp') }
	}
}

// TraceOptions selects what the `trace` command watches.
struct TraceOptions {
	processor  Processor
	frames     int
	tail       int  // instructions kept and printed
	stop_pc    ?u32 // stop when the processor reaches this address
	stop_low   ?u32 // stop when the program counter enters [stop_low, stop_high)
	stop_high  u32
	skip       u64  // instructions to execute before any stop condition applies
	watch      ?u32 // stop when the long at this address changes
	watch_mask u32 = 0xffff_ffff
}

// program_counter returns the traced processor's program counter and its
// executed-instruction count.
fn program_counter(m &machine.Machine, processor Processor) (u32, u64) {
	return match processor {
		.m68k { m.cpu.pc, m.counters.cpu_instructions }
		.gpu { m.gpu.pc, m.gpu.instructions }
		.dsp { m.dsp.pc, m.dsp.instructions }
	}
}

// Executed is one traced instruction: its address and the words at that
// address when it ran, so later self-modification cannot change the listing.
struct Executed {
mut:
	pc    u32
	words [5]u16
}

// text disassembles the recorded instruction.
fn (e Executed) text(processor Processor) string {
	read := fn [e] (addr u32) u16 {
		index := (addr - e.pc) >> 1
		return if index < 5 { e.words[index] } else { u16(0) }
	}
	text, _ := match processor {
		.m68k { debug.disassemble_m68k(read, e.pc) }
		.gpu { debug.disassemble_risc(read, .gpu, e.pc) }
		.dsp { debug.disassemble_risc(read, .dsp, e.pc) }
	}

	return text
}

// trace single-steps the machine and keeps the last instructions of one
// processor in a ring. It stops on the first matching stop condition, when a
// RISC processor leaves its local RAM, or when the frame budget runs out,
// and prints the ring oldest first followed by the processor state.
//
// This is a diagnostic: it runs the scheduler one master tick at a time, so
// it is slow and its interleaving is finer than a normal run.
fn trace(path string, options ImageOptions, t TraceOptions) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	mut ring := []Executed{len: t.tail}
	mut head := 0
	mut recorded := u64(0)
	mut reason := 'frame budget reached'
	_, mut last_count := program_counter(m, t.processor)
	mut watched := u32(0)
	if addr := t.watch {
		watched = m.peek32(addr) & t.watch_mask
	}
	deadline := u64(t.frames) * m.config.region.master_clock_hz() / 60
	for m.tick < deadline {
		pc_before, _ := program_counter(m, t.processor)
		mut entry := Executed{
			pc: pc_before
		}
		for i in u32(0) .. 5 {
			entry.words[i] = (u16(m.peek8(pc_before + i * 2)) << 8) | m.peek8(pc_before + i * 2 + 1)
		}
		m.advance(m.tick + 1, false)
		pc, count := program_counter(m, t.processor)
		if count == last_count {
			continue
		}
		last_count = count
		ring[head] = entry
		head = (head + 1) % t.tail
		recorded++
		if recorded < t.skip {
			// The watch compares against the value at the end of the skip.
			if addr := t.watch {
				watched = m.peek32(addr) & t.watch_mask
			}
			continue
		}
		if stop := t.stop_pc {
			if pc == stop {
				reason = 'reached ${stop:06x}'
				break
			}
		}
		if low := t.stop_low {
			if pc >= low && pc < t.stop_high {
				reason = 'entered ${low:06x}..${t.stop_high:06x} at ${pc:06x}'
				break
			}
		}
		if addr := t.watch {
			value := m.peek32(addr) & t.watch_mask
			if value != watched {
				reason = '${addr:06x} changed from ${watched:08x} to ${value:08x}'
				break
			}
		}
		if t.processor == .gpu && m.gpu.running && !m.gpu.owns_ram(pc) {
			reason = 'left local RAM for ${pc:06x}'
			break
		}
		if t.processor == .dsp && m.dsp.running && !m.dsp.owns_ram(pc) {
			reason = 'left local RAM for ${pc:06x}'
			break
		}
	}
	println('${t.processor}: ${reason} at tick ${m.tick} after ${recorded} instructions')
	count := if recorded < u64(t.tail) { int(recorded) } else { t.tail }
	for i in 0 .. count {
		entry := ring[(head + t.tail - count + i) % t.tail]
		println('${entry.pc:06x}  ${entry.text(t.processor)}')
	}
	match t.processor {
		.gpu { print(debug.registers_risc(m.gpu)) }
		.dsp { print(debug.registers_risc(m.dsp)) }
		.m68k {}
	}

	print(debug.processors(m))
}
