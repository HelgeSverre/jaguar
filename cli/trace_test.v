module cli

import os

fn test_trace_returns_on_a_cpu_double_fault_for_every_processor() {
	path := os.join_path(os.temp_dir(), 'vjag_trace_halt_${os.getpid()}.bin')
	defer { os.rm(path) or {} }
	// movea.l #1,a7; illegal: exception stacking on an odd SP double-faults.
	os.write_file_array(path, [u8(0x2e), 0x7c, 0, 0, 0, 1, 0x4a, 0xfc])!
	for processor in [Processor.m68k, .gpu, .dsp] {
		reason := trace(path, ImageOptions{ format: .raw_binary, load_addr: 0x4000 }, TraceOptions{
			processor: processor
			frames:    1
			tail:      8
			skip:      1000 // a halt must also break out while skipping instructions
		})!
		assert reason == '68000 halted'
	}
}

fn test_trace_rejects_invalid_budgets_before_opening_the_image() {
	for options in [TraceOptions{ tail: 0, frames: 1 }, TraceOptions{ tail: 1, frames: -1 }] {
		trace('unused', ImageOptions{}, options) or {
			assert err.msg().contains('tail must be positive')
			continue
		}
		assert false, 'invalid trace options must fail'
	}
}
