module jerry

fn test_matrix_rows_and_simultaneous_buttons() {
	mut p := Pads{}
	p.set(0, .up, true)
	p.set(0, .right, true)
	p.set(0, .seven, true)
	p.set(1, .down, true)
	p.write_select(0x007e) // row 0 of both ports: bit 0 and bit 7 low
	assert p.read_columns() & 0x0f00 == 0x0600, 'up and right pull bits 8 and 11 low'
	assert p.read_columns() & 0xf000 == 0xd000, 'port 1 down is bit 13'
	p.write_select(0x00fd) // row 1 of port 0 only
	assert p.read_columns() & 0x0f00 == 0x0d00, 'seven is the second column of row 1'
	assert p.read_columns() & 0xf000 == 0xf000, 'no row selected on port 1'
	p.write_select(0x00fc) // rows 0 and 1 together
	assert p.read_columns() & 0x0f00 == 0x0400
}

fn test_fire_buttons_follow_their_rows() {
	mut p := Pads{}
	p.set(0, .a, true)
	p.set(0, .option, true)
	p.set(0, .pause, true)
	p.write_select(0x00fe)
	assert p.read_buttons() & 3 == 0, 'row 0 carries A and Pause'
	p.write_select(0x00fd)
	assert p.read_buttons() & 3 == 3, 'B is not held'
	p.write_select(0x00f7)
	assert p.read_buttons() & 3 == 1, 'Option reads on row 3'
	p.release_all()
	assert p.read_buttons() & 3 == 3
}

fn test_region_bit_and_audio_gate() {
	mut p := Pads{}
	assert p.read_buttons() & 0x10 != 0
	p.region_ntsc = false
	assert p.read_buttons() & 0x10 == 0
	p.write_select(0x01ff)
	assert p.audio_enabled
	p.write_select(0x00ff)
	assert !p.audio_enabled
}

fn test_interrupt_control_latches_and_clears() {
	mut j := new()
	j.raise(.timer1)
	assert j.read16(reg_jintctrl) == 1 << 2
	assert !j.host_irq, 'a disabled source does not interrupt'
	j.write16(reg_jintctrl, 0x0004)
	j.raise(.timer1)
	assert j.host_irq
	j.write16(reg_jintctrl, 0x0404)
	assert j.read16(reg_jintctrl) == 0
}

fn test_timer_periods_and_reprogramming() {
	mut j := new()
	j.reset()
	j.timers_dirty = false
	assert j.timer_period(1) == 0, 'a timer with both registers zero is stopped'
	j.write16(reg_jpit1, 9)
	j.write16(reg_jpit2, 99)
	assert j.timers_dirty, 'the machine must reschedule'
	assert j.timer_period(1) == 1000
	assert j.timer_period(2) == 0
	j.timer_expired(1)
	assert j.dsp_irqs == 1 << dsp_irq_timer1
	assert j.int_pending == 1 << 2
}

fn test_sample_clock_period_and_queue() {
	mut j := new()
	j.reset()
	assert j.sample_period() == 0, 'no serial clock until SMODE selects the internal one'
	j.write_i2s(i2s_sclk, 19)
	j.write_i2s(i2s_smode, 0x15)
	assert j.sample_period() == 1280
	j.pads.write_select(0x0100) // audio enabled
	j.write_i2s(i2s_left, 0x1234)
	j.write_i2s(i2s_right, 0xfffe)
	j.sample_clock()
	j.pads.write_select(0) // muted: the DSP still gets its interrupt
	j.sample_clock()
	assert j.dsp_irqs == 1 << dsp_irq_i2s
	mut out := []i16{len: 8}
	assert j.drain_audio(mut out) == 2
	assert out[0] == 0x1234 && out[1] == -2
	assert out[2] == 0 && out[3] == 0, 'a muted sample is silence'
	assert j.samples == 2
	assert j.drain_audio(mut out) == 0
}

fn test_audio_queue_drops_oldest_when_full() {
	mut j := new()
	j.pads.write_select(0x0100)
	for i in 0 .. audio_capacity + 10 {
		j.write_i2s(i2s_left, u32(i))
		j.sample_clock()
	}
	assert j.audio_lost == 11
	mut out := []i16{len: 2}
	assert j.drain_audio(mut out) == 1
	assert out[0] == 11, 'the oldest frames were dropped'
}

fn test_wavetable_layout() {
	rom := synthesized_wavetable()
	assert rom.len == wavetable_size
	// The sine table starts at zero and peaks a quarter of the way in.
	assert rom[0x200] == 0 && rom[0x201] == 0
	peak := (u32(rom[0x200 + 32 * 4 + 2]) << 8) | rom[0x200 + 32 * 4 + 3]
	assert peak == 0x7fff
	// Negative samples are sign-extended to 32 bits.
	assert rom[0x200 + 96 * 4] == 0xff && rom[0x200 + 96 * 4 + 1] == 0xff
}
