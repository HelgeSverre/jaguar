module cli

import machine

fn test_compat_accepts_mirrored_ram_but_not_vectors_or_unpopulated_ram() {
	mut m := machine.new(machine.Config{})
	for pc in [u32(0x4000), 0x201000, 0x3ffffe] {
		m.cpu.pc = pc
		assert plausible_program_counter(m)
	}
	for pc in [u32(0), 0x200010, 0x400000, 0x700000, 0xf00000, 0x201001] {
		m.cpu.pc = pc
		assert !plausible_program_counter(m)
	}
}
