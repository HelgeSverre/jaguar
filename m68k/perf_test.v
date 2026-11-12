// Throughput smoke test: runs a loop of simple instructions through the
// public `step` interface and reports instructions per second. The figure
// is informational (compile with -prod for a meaningful number); the test
// only checks that the loop computed what it should.
//
// Environment:
//   M68K_PERF_INSTRUCTIONS=<n>  number of instructions to execute
module m68k

import hwtypes
import os
import time

const perf_default_instructions = 2_000_000
const perf_loop_length = 10

// RamBus is a minimal 64 KiB RAM implementing hwtypes.Bus.
struct RamBus {
mut:
	mem [0x10000]u8
}

@[direct_array_access]
fn (mut b RamBus) read8(addr u32) u8 {
	return b.mem[addr & 0xffff]
}

@[direct_array_access]
fn (mut b RamBus) read16(addr u32) u16 {
	return (u16(b.mem[addr & 0xffff]) << 8) | b.mem[(addr + 1) & 0xffff]
}

fn (mut b RamBus) read32(addr u32) u32 {
	return (u32(b.read16(addr)) << 16) | b.read16(addr + 2)
}

@[direct_array_access]
fn (mut b RamBus) write8(addr u32, val u8) {
	b.mem[addr & 0xffff] = val
}

@[direct_array_access]
fn (mut b RamBus) write16(addr u32, val u16) {
	b.mem[addr & 0xffff] = u8(val >> 8)
	b.mem[(addr + 1) & 0xffff] = u8(val)
}

fn (mut b RamBus) write32(addr u32, val u32) {
	b.write16(addr, u16(val >> 16))
	b.write16(addr + 2, u16(val))
}

fn test_simple_instruction_throughput() {
	// Convert to the interface once: V boxes a concrete bus on every
	// implicit conversion, which would put an allocation into each step.
	mut bus := hwtypes.Bus(&RamBus{})
	program := [
		u16(0xd081), // loop: add.l d1,d0
		0xb142, // eor.w d0,d2
		0x2600, // move.l d0,d3
		0x5281, // addq.l #1,d1
		0xe24b, // lsr.w #1,d3
		0x3083, // move.w d3,(a0)
		0x3810, // move.w (a0),d4
		0xb644, // cmp.w d4,d3
		0x5387, // subq.l #1,d7
		0x66ec, // bne.s loop
	]
	bus.write32(0, 0x8000)
	bus.write32(4, 0x1000)
	for i, word in program {
		bus.write16(0x1000 + u32(i) * 2, word)
	}
	requested := os.getenv('M68K_PERF_INSTRUCTIONS').int()
	instructions := if requested > 0 { requested } else { perf_default_instructions }
	iterations := u32(instructions / perf_loop_length)

	mut cpu := &Cpu{}
	cpu.reset(mut bus)
	cpu.a[0] = 0x4000
	cpu.d[1] = 1
	cpu.d[7] = iterations
	watch := time.new_stopwatch()
	for _ in 0 .. iterations * perf_loop_length {
		cpu.step(mut bus)
	}
	elapsed := watch.elapsed()

	assert cpu.d[7] == 0
	assert cpu.d[1] == iterations + 1
	assert cpu.pc == 0x1000 + perf_loop_length * 2
	// Nine instructions of the loop body plus the taken or final branch.
	body_cycles := u64(8 + 4 + 4 + 8 + 8 + 8 + 8 + 4 + 8)
	assert cpu.cycles == u64(iterations) * (body_cycles + 10) - 2
	rate := f64(iterations) * perf_loop_length / elapsed.seconds() / 1.0e6
	println('m68k throughput: ${rate:.1f} M instructions/s (${instructions} instructions)')
}
