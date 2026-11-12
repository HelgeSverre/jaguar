// JERRY: programmable timers, the I2S audio interface, the controller
// matrix and the interrupt controller of the Jaguar's sound chip. The DSP
// core lives in `risc`.
module jerry

// Irq numbers the interrupt sources of JINTCTRL, which are also bit numbers.
pub enum Irq {
	external
	dsp
	timer1
	timer2
	serial
	i2s
}

// DSP interrupt lines driven by JERRY devices.
pub const dsp_irq_i2s = u32(1)
pub const dsp_irq_timer1 = u32(2)
pub const dsp_irq_timer2 = u32(3)

// Register offsets from 0xF10000.
const reg_jpit1 = u32(0x00) // timer 1 prescaler
const reg_jpit2 = u32(0x02) // timer 1 divider
const reg_jpit3 = u32(0x04) // timer 2 prescaler
const reg_jpit4 = u32(0x06) // timer 2 divider
const reg_jintctrl = u32(0x20)
const reg_block_size = u32(0x40)

// Offsets of the serial audio registers from 0xF1A140.
const i2s_left = u32(0x08) // LTXD on write
const i2s_right = u32(0x0c) // RTXD on write
const i2s_sclk = u32(0x10) // SCLK on write, SSTAT on read
const i2s_smode = u32(0x14)

const smode_internal_clock = u32(1 << 0)

// i2s_bits_per_frame is the number of serial clocks in one stereo sample.
const i2s_bits_per_frame = u64(32)

// audio_capacity is the size of the sample queue in stereo frames. A full
// queue drops the oldest audio; guest execution never waits for the host.
const audio_capacity = 16384

// Jerry is the guest-visible state of the sound chip apart from the DSP.
@[heap]
pub struct Jerry {
pub mut:
	regs         [32]u16 // 0xF10000..0xF1003F as last written
	int_pending  u32     // JINTCTRL latches, bit per `Irq`
	int_enable   u32
	host_irq     bool // an enabled source fired: the machine forwards it to TOM
	dsp_irqs     u32  // interrupt lines for the machine to forward to the DSP
	timers_dirty bool // a timer or the serial clock was reprogrammed
	sclk         u32
	smode        u32
	left         i16 // transmit latches
	right        i16
	pads         Pads
	// Generated audio: interleaved stereo frames in a ring.
	audio       []i16 = []i16{len: audio_capacity * 2}
	audio_read  u32
	audio_write u32
	audio_lost  u64 // frames dropped because the host did not drain in time
	samples     u64 // frames generated since power-on
}

// new creates JERRY in its power-on state.
pub fn new() &Jerry {
	return &Jerry{}
}

// reset applies the peripheral reset. Queued audio is discarded.
pub fn (mut j Jerry) reset() {
	for i in 0 .. j.regs.len {
		j.regs[i] = 0
	}
	j.int_pending = 0
	j.int_enable = 0
	j.host_irq = false
	j.dsp_irqs = 0
	j.timers_dirty = true
	j.sclk = 0
	j.smode = 0
	j.left = 0
	j.right = 0
	j.pads.reset()
	j.audio_read = 0
	j.audio_write = 0
}

// raise latches an interrupt source of JINTCTRL.
pub fn (mut j Jerry) raise(irq Irq) {
	bit := u32(1) << u32(irq)
	j.int_pending |= bit
	if j.int_enable & bit != 0 {
		j.host_irq = true
	}
}

// read16 reads a register; `offset` is relative to 0xF10000.
pub fn (j &Jerry) read16(offset u32) u16 {
	if offset >= reg_block_size {
		return 0
	}
	return match offset & 0x3e {
		reg_jintctrl { u16(j.int_pending) }
		// The timer read-back registers mirror the programmed values.
		0x36 { j.regs[reg_jpit1 >> 1] }
		0x38 { j.regs[reg_jpit2 >> 1] }
		0x3a { j.regs[reg_jpit3 >> 1] }
		0x3c { j.regs[reg_jpit4 >> 1] }
		else { j.regs[offset >> 1] }
	}
}

// write16 writes a register; `offset` is relative to 0xF10000.
pub fn (mut j Jerry) write16(offset u32, value u16) {
	if offset >= reg_block_size {
		return
	}
	j.regs[offset >> 1] = value
	match offset & 0x3e {
		reg_jintctrl {
			j.int_enable = value & 0x3f
			j.int_pending &= ~(u32(value >> 8) & 0x3f)
		}
		reg_jpit1, reg_jpit2, reg_jpit3, reg_jpit4 {
			j.timers_dirty = true
		}
		else {}
	}
}

// timer_period returns the period of timer 1 or 2 in master ticks, or zero
// when the timer is stopped.
pub fn (j &Jerry) timer_period(timer int) u64 {
	base := if timer == 1 { reg_jpit1 } else { reg_jpit3 }
	prescaler := u64(j.regs[base >> 1])
	divider := u64(j.regs[(base >> 1) + 1])
	if prescaler == 0 && divider == 0 {
		return 0
	}
	return (prescaler + 1) * (divider + 1)
}

// timer_expired is called by the machine when timer 1 or 2 fires.
pub fn (mut j Jerry) timer_expired(timer int) {
	if timer == 1 {
		j.raise(.timer1)
		j.dsp_irqs |= u32(1) << dsp_irq_timer1
	} else {
		j.raise(.timer2)
		j.dsp_irqs |= u32(1) << dsp_irq_timer2
	}
}

// read_i2s reads a serial audio register; `offset` is relative to 0xF1A140.
pub fn (j &Jerry) read_i2s(offset u32) u32 {
	return match offset & 0x1c {
		// SSTAT: both word-strobe status bits read as set.
		i2s_sclk { u32(3) }
		i2s_smode { j.smode }
		else { u32(0) }
	}
}

// write_i2s writes a serial audio register.
pub fn (mut j Jerry) write_i2s(offset u32, value u32) {
	match offset & 0x1c {
		i2s_left {
			j.left = i16(u16(value))
		}
		i2s_right {
			j.right = i16(u16(value))
		}
		i2s_sclk {
			j.sclk = value & 0xff
			j.timers_dirty = true
		}
		i2s_smode {
			j.smode = value
			j.timers_dirty = true
		}
		else {}
	}
}

// sample_period returns the length of one stereo sample in master ticks, or
// zero while JERRY does not generate the serial clock.
pub fn (j &Jerry) sample_period() u64 {
	if j.smode & smode_internal_clock == 0 {
		return 0
	}
	return 2 * (u64(j.sclk) + 1) * i2s_bits_per_frame
}

// sample_clock is called by the machine once per stereo sample period: the
// transmit latches go out to the DAC and the DSP is asked for the next pair.
@[direct_array_access]
pub fn (mut j Jerry) sample_clock() {
	audible := j.pads.audio_enabled
	j.audio[j.audio_write * 2] = if audible { j.left } else { i16(0) }
	j.audio[j.audio_write * 2 + 1] = if audible { j.right } else { i16(0) }
	j.audio_write = (j.audio_write + 1) % audio_capacity
	if j.audio_write == j.audio_read {
		j.audio_read = (j.audio_read + 1) % audio_capacity
		j.audio_lost++
	}
	j.samples++
	j.raise(.i2s)
	j.dsp_irqs |= u32(1) << dsp_irq_i2s
}

// drain_audio moves queued stereo frames into `out` (interleaved) and
// returns the number of frames written.
@[direct_array_access]
pub fn (mut j Jerry) drain_audio(mut out []i16) int {
	mut frames := 0
	for j.audio_read != j.audio_write && (frames + 1) * 2 <= out.len {
		out[frames * 2] = j.audio[j.audio_read * 2]
		out[frames * 2 + 1] = j.audio[j.audio_read * 2 + 1]
		j.audio_read = (j.audio_read + 1) % audio_capacity
		frames++
	}
	return frames
}
