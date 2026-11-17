module machine

import loader

fn test_uploaded_program_can_exit_to_monitor_without_corrupting_ram() {
	plan := loader.plan([u8(0x4a), 0xfc], loader.Options{ format: .raw_binary, load_addr: 0x4000 }) or {
		panic(err)
	}
	mut m := new(Config{})
	m.load_direct(plan)
	m.write32(0x2000, 0x12345678)
	m.advance(1000, false)
	assert m.cpu.pc == 0x1000
	assert m.cpu.a[7] == ram_size - 6 // real ILLEGAL exception frame, not an intercepted opcode
	assert m.read32(ram_size - 4) == 0x4000
	m.advance(100000, false)
	assert m.cpu.pc == 0x1000
	assert m.cpu.a[7] == ram_size - 6
	assert m.read32(0x2000) == 0x12345678
	assert m.counters.half_lines > 0
}

fn test_monitor_does_not_overwrite_image_owned_memory_or_cartridges() {
	for addr in [u32(0x10), 0x12, 0x1000] {
		for bss in [false, true] {
			mut segments := [loader.Segment{ addr: 0x4000, data: [u8(0x60), 0xfe] }]
			mut fills := []loader.ZeroFill{}
			if bss {
				fills << loader.ZeroFill{
					addr: addr
					len:  2
				}
			} else {
				segments << loader.Segment{
					addr: addr
					data: [u8(0xab), 0xcd]
				}
			}
			mut m := new(Config{})
			m.load_direct(loader.LoadPlan{
				kind:      .raw_binary
				entry:     0x4000
				segments:  segments
				zero_fill: fills
			})
			assert m.read16(addr) == if bss {
				u16(0)
			} else {
				u16(0xabcd)
			}
			assert m.read32(0x10) != 0x1000
		}
	}
	mut m := new(Config{})
	m.load_direct(loader.LoadPlan{
		kind:     .cartridge
		entry:    0x802000
		segments: [loader.Segment{ addr: 0x802000, data: [u8(0x60), 0xfe] }]
	})
	assert m.read32(0x10) == 0
	assert m.read16(0x1000) == 0
}
