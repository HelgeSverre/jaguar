// The console: processors, devices and memory composed on one guest
// timeline. Nothing here touches the host; frontends drive the machine
// through this module's public functions.
module machine

import hwtypes
import m68k
import risc
import tom
import jerry
import cart
import loader

pub const ram_size = 0x20_0000
pub const cart_base = u32(0x80_0000)
pub const cart_window = u32(0x60_0000)
pub const bios_base = u32(0xe0_0000)
pub const bios_size = u32(0x2_0000)

// timing_profile names the accuracy contract of this build (see the
// staged timing table in the specification).
pub const timing_profile = 'functional_v1'

// Config selects the machine variant.
pub struct Config {
pub:
	region hwtypes.Region = .ntsc
	// quantum is the longest stretch, in master ticks, one processor runs
	// before the others catch up.
	quantum u64 = 64
	// ram_seed fills main RAM deterministically at power-on; zero clears it.
	ram_seed u32
}

// Counters are per-subsystem activity totals since power-on.
pub struct Counters {
pub mut:
	cpu_instructions u64
	frames           u64
	half_lines       u64
	timer_events     u64
}

// Machine is the complete emulated console.
@[heap]
pub struct Machine {
pub:
	config Config
pub mut:
	cpu       &m68k.Cpu    = unsafe { nil }
	gpu       &risc.Risc   = unsafe { nil }
	dsp       &risc.Risc   = unsafe { nil }
	tom       &tom.Tom     = unsafe { nil }
	jerry     &jerry.Jerry = unsafe { nil }
	eeprom    cart.Eeprom
	ram       []u8
	rom       []u8 // cartridge image, mapped at `cart_base`
	bios      []u8 // boot ROM, mapped at `bios_base` when present
	wavetable []u8
	counters  Counters
	// Guest timeline, in master ticks. Each processor has its own frontier
	// because an instruction can overshoot the end of a slice.
	tick     u64
	cpu_tick u64
	gpu_tick u64
	dsp_tick u64
	// Next occurrence of each periodic device event.
	next_half_line u64
	next_pit       u64 = no_event
	next_timer1    u64 = no_event
	next_timer2    u64 = no_event
	next_sample    u64 = no_event
	frame_done     bool
	entry          u32 // direct-boot entry point of the loaded program
}

// new builds a powered-off machine with no cartridge.
pub fn new(config Config) &Machine {
	mut m := &Machine{
		config:    config
		cpu:       &m68k.Cpu{}
		gpu:       risc.new_gpu()
		dsp:       risc.new_dsp()
		tom:       tom.new(config.region)
		jerry:     jerry.new()
		eeprom:    cart.new_eeprom()
		ram:       []u8{len: ram_size}
		wavetable: jerry.synthesized_wavetable()
	}
	m.jerry.pads.region_ntsc = config.region == .ntsc
	return m
}

// load_direct powers the machine on and places a validated load plan in
// memory for direct boot: no boot ROM runs, the 68000 starts at the plan's
// entry with the stack at the top of RAM, and video timing holds the values
// the boot ROM would have left for the region.
pub fn (mut m Machine) load_direct(plan loader.LoadPlan) {
	m.rom = []u8{}
	for segment in plan.segments {
		if segment.addr >= cart_base {
			m.map_cartridge(segment.addr - cart_base, segment.data)
		}
	}
	m.entry = plan.entry
	m.power_on()
	for segment in plan.segments {
		if segment.addr < cart_base {
			for i, b in segment.data {
				m.ram[(segment.addr + u32(i)) & (ram_size - 1)] = b
			}
		}
	}
	for fill in plan.zero_fill {
		for i in u32(0) .. fill.len {
			if fill.addr + i < ram_size {
				m.ram[fill.addr + i] = 0
			}
		}
	}
	m.direct_boot()
}

// map_cartridge copies image bytes into the cartridge window.
fn (mut m Machine) map_cartridge(offset u32, data []u8) {
	end := int(offset) + data.len
	if m.rom.len < end {
		m.rom << []u8{len: end - m.rom.len, init: 0xff}
	}
	for i, b in data {
		m.rom[int(offset) + i] = b
	}
}

// power_on is the cold start: RAM is seeded, every device is reset and the
// guest timeline restarts at zero. Cartridge and EEPROM contents survive.
pub fn (mut m Machine) power_on() {
	mut seed := m.config.ram_seed
	for i in 0 .. m.ram.len {
		if seed != 0 {
			seed = seed * 1664525 + 1013904223
		}
		m.ram[i] = u8(seed >> 24)
	}
	for i in 0 .. m.gpu.ram.len {
		m.gpu.ram[i] = 0
	}
	for i in 0 .. m.dsp.ram.len {
		m.dsp.ram[i] = 0
	}
	m.gpu.reset()
	m.dsp.reset()
	m.tom.reset()
	m.jerry.reset()
	m.eeprom.select()
	m.counters = Counters{}
	m.tick = 0
	m.cpu_tick = 0
	m.gpu_tick = 0
	m.dsp_tick = 0
	m.next_half_line = u64(m.tom.half_period())
	m.next_pit = no_event
	m.next_timer1 = no_event
	m.next_timer2 = no_event
	m.next_sample = no_event
	m.frame_done = false
}

// direct_boot installs the synthetic start state promised by direct boot.
// Everything it does not set is unspecified, as the specification requires.
fn (mut m Machine) direct_boot() {
	mut bus := hwtypes.Bus(m)
	bus.write32(0, ram_size)
	bus.write32(4, m.entry)
	m.cpu.reset(mut bus)
	for setting in boot_video_settings(m.config.region) {
		bus.write16(0xf0_0000 + setting.offset, setting.value)
	}
	m.sync()
}

struct RegisterSetting {
	offset u32
	value  u16
}

// boot_video_settings lists the TOM video timing the boot ROM programs
// before it starts a cartridge.
fn boot_video_settings(region hwtypes.Region) []RegisterSetting {
	common := [
		RegisterSetting{0x00, 0x1861}, // MEMCON1
		RegisterSetting{0x02, 0x35cc}, // MEMCON2
		RegisterSetting{0x38, 203}, // HDB1
		RegisterSetting{0x3a, 203}, // HDB2
		RegisterSetting{0x3c, 1665}, // HDE
		RegisterSetting{0x46, 38}, // VDB
		RegisterSetting{0x48, 518}, // VDE
		RegisterSetting{0x28, 0x06c1}, // VMODE: CRY, four clocks per pixel
	]
	timing := match region {
		.ntsc {
			[
				RegisterSetting{0x2e, 844}, // HP
				RegisterSetting{0x30, 1713}, // HBB
				RegisterSetting{0x32, 125}, // HBE
				RegisterSetting{0x34, 1741}, // HS
				RegisterSetting{0x3e, 523}, // VP
				RegisterSetting{0x40, 500}, // VBB
				RegisterSetting{0x42, 24}, // VBE
				RegisterSetting{0x44, 517}, // VS
			]
		}
		.pal {
			[
				RegisterSetting{0x2e, 850},
				RegisterSetting{0x30, 1711},
				RegisterSetting{0x32, 158},
				RegisterSetting{0x34, 1749},
				RegisterSetting{0x3e, 623},
				RegisterSetting{0x40, 600},
				RegisterSetting{0x42, 34},
				RegisterSetting{0x44, 618},
			]
		}
	}

	mut settings := common.clone()
	settings << timing
	return settings
}

// set_button changes the level of a controller button on port 0 or 1.
pub fn (mut m Machine) set_button(port int, button jerry.Button, pressed bool) {
	if port == 0 || port == 1 {
		m.jerry.pads.set(port, button, pressed)
	}
}

// frame returns the most recently completed picture and its description.
pub fn (m &Machine) frame() ([]u32, hwtypes.FrameInfo) {
	return m.tom.frame, m.tom.frame_info()
}

// drain_audio moves generated stereo frames into `out` and returns how many.
pub fn (mut m Machine) drain_audio(mut out []i16) int {
	return m.jerry.drain_audio(mut out)
}

// audio_rate returns the guest's current sample rate in Hz, or zero while
// the serial clock is stopped.
pub fn (m &Machine) audio_rate() f64 {
	period := m.jerry.sample_period()
	if period == 0 {
		return 0
	}
	return f64(m.config.region.master_clock_hz()) / f64(period)
}

// seconds converts a tick count on the guest timeline to seconds.
pub fn (m &Machine) seconds(ticks u64) f64 {
	return f64(ticks) / f64(m.config.region.master_clock_hz())
}
