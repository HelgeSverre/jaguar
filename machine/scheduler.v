module machine

import hwtypes

const no_event = u64(0xffff_ffff_ffff_ffff)

// cpu_clock_divider: the 68000 runs at half the master clock.
const cpu_clock_divider = u64(2)

// StopReason says why `advance` returned.
pub enum StopReason {
	deadline
	frame_complete
	cpu_halted
}

// run_frame advances the guest until the video field in progress completes.
// A guest that has stopped the video counters still returns after two
// nominal field times.
pub fn (mut m Machine) run_frame() StopReason {
	limit := m.tick + m.config.region.master_clock_hz() / 25
	return m.advance(limit, true)
}

// advance runs the guest timeline up to `deadline` master ticks, or to the
// end of the current field when `stop_at_frame` is set.
//
// Ordering within a slice is deterministic: the 68000 runs to the slice end,
// then the GPU, then the DSP, then every device event due at the slice end
// fires in a fixed order (video, TOM timer, JERRY timers, audio sample).
pub fn (mut m Machine) advance(deadline u64, stop_at_frame bool) StopReason {
	mut bus := m.self_bus
	m.frame_done = false
	for m.tick < deadline {
		mut target := m.tick + m.config.quantum
		if deadline < target {
			target = deadline
		}
		next := m.next_event()
		if next < target {
			target = next
		}
		for m.cpu_tick < target {
			if m.cpu.halted {
				return .cpu_halted
			}
			if m.cpu.stopped && m.cpu.irq_level == 0 {
				m.cpu_tick = target
				break
			}
			m.cpu_tick += u64(m.cpu.step(mut bus)) * cpu_clock_divider
			m.counters.cpu_instructions++
			if m.cpu.irq_acknowledged {
				m.cpu.irq_acknowledged = false
				m.tom.acknowledge()
				m.cpu.irq_level = 0
			}
		}
		if !m.gpu.running {
			m.gpu_tick = target
		} else if m.gpu_tick < target {
			m.gpu_tick += m.gpu.run(mut bus, u32(target - m.gpu_tick))
		}
		if !m.dsp.running {
			m.dsp_tick = target
		} else if m.dsp_tick < target {
			m.dsp_tick += m.dsp.run(mut bus, u32(target - m.dsp_tick))
		}
		m.tick = target
		m.fire_events(mut bus)
		if m.frame_done && stop_at_frame {
			return .frame_complete
		}
	}
	return .deadline
}

// next_event returns the tick of the earliest pending device event.
@[inline]
fn (m &Machine) next_event() u64 {
	mut next := m.next_half_line
	if m.next_pit < next {
		next = m.next_pit
	}
	if m.next_timer1 < next {
		next = m.next_timer1
	}
	if m.next_timer2 < next {
		next = m.next_timer2
	}
	if m.next_sample < next {
		next = m.next_sample
	}
	return next
}

// fire_events runs every device event that is due and routes the resulting
// interrupts.
fn (mut m Machine) fire_events(mut bus hwtypes.Bus) {
	if m.tick >= m.next_half_line {
		m.tom.hc = 0
		if m.tom.half_line(mut bus) {
			m.frame_done = true
			m.counters.frames++
		}
		m.counters.half_lines++
		m.next_half_line += u64(m.tom.half_period())
	}
	if m.tick >= m.next_pit {
		m.tom.pit_expired()
		m.counters.timer_events++
		m.next_pit += m.tom.pit_period()
	}
	if m.tick >= m.next_timer1 {
		m.jerry.timer_expired(1)
		m.counters.timer_events++
		m.next_timer1 += m.jerry.timer_period(1)
	}
	if m.tick >= m.next_timer2 {
		m.jerry.timer_expired(2)
		m.counters.timer_events++
		m.next_timer2 += m.jerry.timer_period(2)
	}
	if m.tick >= m.next_sample {
		m.jerry.sample_clock()
		m.next_sample += m.jerry.sample_period()
	}
	m.sync()
}

// sync propagates state that crosses device boundaries: reprogrammed timers
// are rescheduled and interrupt requests are forwarded along the wiring of
// the console (GPU and JERRY to TOM, TOM to the 68000 at level 2, device
// lines to the GPU and DSP).
fn (mut m Machine) sync() {
	if m.tom.pit_dirty {
		m.tom.pit_dirty = false
		m.next_pit = schedule(m.tick, m.tom.pit_period())
	}
	if m.jerry.timers_dirty {
		m.jerry.timers_dirty = false
		m.next_timer1 = schedule(m.tick, m.jerry.timer_period(1))
		m.next_timer2 = schedule(m.tick, m.jerry.timer_period(2))
		m.next_sample = schedule(m.tick, m.jerry.sample_period())
	}
	if m.dsp.host_irq {
		m.dsp.host_irq = false
		m.jerry.raise(.dsp)
	}
	if m.jerry.host_irq {
		m.jerry.host_irq = false
		m.tom.raise(.jerry)
		m.gpu.raise_irq(gpu_irq_jerry)
	}
	if m.gpu.host_irq {
		m.gpu.host_irq = false
		m.tom.raise(.gpu)
	}
	if m.tom.gpu_irqs != 0 {
		for line in u32(0) .. 5 {
			if m.tom.gpu_irqs & (u32(1) << line) != 0 {
				m.gpu.raise_irq(line)
			}
		}
		m.tom.gpu_irqs = 0
	}
	if m.jerry.dsp_irqs != 0 {
		for line in u32(0) .. 6 {
			if m.jerry.dsp_irqs & (u32(1) << line) != 0 {
				m.dsp.raise_irq(line)
			}
		}
		m.jerry.dsp_irqs = 0
	}
	m.cpu.irq_level = if m.tom.irq_asserted() { u8(2) } else { u8(0) }
}

// gpu_irq_jerry is the GPU interrupt line wired to JERRY's interrupt output.
const gpu_irq_jerry = u32(1)

// schedule returns the first expiry of a periodic event started at `now`.
@[inline]
fn schedule(now u64, period u64) u64 {
	return if period == 0 { no_event } else { now + period }
}

// horizontal_count derives the HC register from the guest timeline.
fn (m &Machine) horizontal_count() u16 {
	period := u64(m.tom.half_period())
	line_start := m.next_half_line - period
	mut position := if m.cpu_tick > line_start { m.cpu_tick - line_start } else { u64(0) }
	if position >= period {
		position = period - 1
	}
	second_half := if m.tom.vc & 1 != 0 { u16(0x400) } else { u16(0) }
	return u16(position) | second_half
}
