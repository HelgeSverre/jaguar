module cli

import debug
import risc

// TraceOptions selects what the `trace` command watches.
struct TraceOptions {
	processor risc.Variant
	frames    int
	tail      int  // instructions kept and printed
	stop_pc   ?u32 // stop when the processor reaches this address
}

// trace single-steps the machine and keeps the last instructions of one
// RISC processor in a ring. It stops when the processor leaves its local
// RAM, reaches `stop_pc`, or the frame budget runs out, and then prints the
// ring oldest first with the register file.
//
// This is a diagnostic: it runs the scheduler one master tick at a time, so
// it is slow and its interleaving is finer than a normal run.
fn trace(path string, options ImageOptions, t TraceOptions) ! {
	mut session := open_session(path, options)!
	mut m := session.machine
	mut ring := []string{len: t.tail}
	mut head := 0
	mut recorded := 0
	mut last_count := u64(0)
	mut reason := 'frame budget reached'
	deadline := u64(t.frames) * m.config.region.master_clock_hz() / 60
	for m.tick < deadline {
		c := if t.processor == .gpu { m.gpu } else { m.dsp }
		// Decode before executing: the program may be overwritten later.
		text, _ := debug.disassemble_risc(m, t.processor, c.pc)
		line := '${c.pc:06x}  ${text}'
		m.advance(m.tick + 1, false)
		if c.instructions == last_count {
			continue
		}
		last_count = c.instructions
		ring[head] = line
		head = (head + 1) % t.tail
		recorded++
		if stop := t.stop_pc {
			if c.pc == stop {
				reason = 'reached ${stop:06x}'
				break
			}
		}
		if c.running && !c.owns_ram(c.pc) {
			reason = 'left local RAM for ${c.pc:06x}'
			break
		}
	}
	c := if t.processor == .gpu { m.gpu } else { m.dsp }
	println('${t.processor}: ${reason} at tick ${m.tick} after ${c.instructions} instructions')
	count := if recorded < t.tail { recorded } else { t.tail }
	for i in 0 .. count {
		println(ring[(head + t.tail - count + i) % t.tail])
	}
	print(debug.registers_risc(c))
	print(debug.processors(m))
}
