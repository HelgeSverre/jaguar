module machine

import loader

fn timer_machine() &Machine {
	plan := loader.plan([u8(0x60), 0xfe], loader.Options{ format: .raw_binary, load_addr: 0x4000 }) or {
		panic(err)
	}
	mut m := new(Config{})
	m.load_direct(plan)
	m.write16(0xf10000, 9)
	m.write16(0xf10002, 99) // timer 1: 1000 ticks
	m.write16(0xf10004, 19)
	m.write16(0xf10006, 99) // timer 2: 2000 ticks
	m.write32(0xf1a150, 19)
	m.write32(0xf1a154, 0x15) // serial audio: 1280 ticks
	return m
}

fn test_reprogramming_each_clock_preserves_the_other_deadlines() {
	for addr in [u32(0xf10000), 0xf10002, 0xf10004, 0xf10006, 0xf1a150, 0xf1a154] {
		mut m := timer_machine()
		m.advance(100, false)
		if addr < 0xf1a140 {
			m.write16(addr, 49)
		} else {
			m.write32(addr, if addr == 0xf1a150 { u32(9) } else { u32(0x15) })
		}
		assert m.next_timer1 == if addr < 0xf10004 {
			100 + m.jerry.timer_period(1)
		} else {
			1000
		}
		assert m.next_timer2 == if addr >= 0xf10004 && addr < 0xf10008 {
			100 + m.jerry.timer_period(2)
		} else {
			2000
		}
		assert m.next_sample == if addr >= 0xf1a140 {
			100 + m.jerry.sample_period()
		} else {
			1280
		}
	}
}

fn test_repeated_timer_writes_do_not_starve_audio_or_the_other_timer() {
	mut m := timer_machine()
	for tick in 1 .. 31 {
		m.advance(u64(tick * 100), false)
		m.write16(0xf10000, 9)
	}
	assert m.jerry.samples == 2
	assert m.jerry.int_pending & (1 << 3) != 0, 'timer 2 must expire despite timer 1 being restarted'
	m.power_on()
	m.advance(3100, false)
	assert m.next_timer1 == no_event && m.next_timer2 == no_event && m.next_sample == no_event
}

fn test_tom_timer_reads_live_counters_without_rescheduling() {
	mut m := timer_machine()
	m.write16(0xf00050, 9)
	m.write16(0xf00052, 99)
	assert m.read32(0xf00050) == 0x0009_0063
	m.advance(1, false)
	assert m.read16(0xf00050) == 8
	assert m.read16(0xf00052) == 99
	m.advance(10, false)
	assert m.read32(0xf00050) == 0x0009_0062
	assert m.read8(0xf00051) == 9
	assert m.next_pit == 1000
	assert m.tick == 10, 'reads do not advance guest time'
	m.advance(999, false)
	assert m.read32(0xf00050) == 0
	m.advance(1000, false)
	assert m.read32(0xf00050) == 0x0009_0063
	assert m.next_pit == 2000
	m.write16(0xf00050, 0)
	assert m.read32(0xf00050) == 0
}
