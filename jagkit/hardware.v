module jagkit

// Addresses of the hardware registers a program is likely to touch, and the
// bits of the ones that are written most.

// TOM: video and the object processor.
pub const olp = u32(0xf00020) // object list pointer, written with its words swapped
pub const vmode = u32(0xf00028)
pub const bord1 = u32(0xf0002a)
pub const bord2 = u32(0xf0002c)
pub const hdb1 = u32(0xf00038)
pub const hdb2 = u32(0xf0003a)
pub const hde = u32(0xf0003c)
pub const vdb = u32(0xf00046)
pub const vde = u32(0xf00048)
pub const vi = u32(0xf0004e) // half-line of the vertical interrupt
pub const bg = u32(0xf00058)
pub const int1 = u32(0xf000e0) // interrupt enables (low byte) and acknowledges (high byte)
pub const int2 = u32(0xf000e2) // written to let the next interrupt through
pub const clut = u32(0xf00400) // 256 colours, one word each

// vmode_cry16 is 16-bit CRY at four clocks per pixel, video on.
pub const vmode_cry16 = 0x06c1
pub const int1_video = 0x0001
pub const int1_video_ack = 0x0100

// The GPU.
pub const g_flags = u32(0xf02100)
pub const g_pc = u32(0xf02110)
pub const g_ctrl = u32(0xf02114)
pub const gpu_ram = u32(0xf03000)
pub const gpu_ram_size = 0x1000

// JERRY: controllers, sound and the DSP.
pub const joystick = u32(0xf14000) // row select on write, columns on read
pub const joybuts = u32(0xf14002) // fire buttons; bit 4 is set on NTSC machines
pub const d_flags = u32(0xf1a100)
pub const d_pc = u32(0xf1a110)
pub const d_ctrl = u32(0xf1a114)
pub const l_dac = u32(0xf1a148)
pub const r_dac = u32(0xf1a14c)
pub const sclk = u32(0xf1a150)
pub const smode = u32(0xf1a154)
pub const dsp_ram = u32(0xf1b000)
pub const dsp_ram_size = 0x2000

// joystick_enable drives the row-select outputs and unmutes the sound; the
// low nibble selects one row of the first controller, active low.
pub const joystick_enable = 0x8100

// The 68000 vector every Jaguar interrupt arrives through.
pub const interrupt_vector = u32(0x100)

// risc_go is written to G_CTRL or D_CTRL to start the processor.
pub const risc_go = 1

// DSP flag bits used by an interrupt handler.
pub const flag_imask = 3
pub const dsp_flag_i2s_enable = 5
pub const dsp_flag_i2s_clear = 10

// dsp_i2s_vector is where the DSP enters its sample interrupt handler.
pub const dsp_i2s_vector = u32(0xf1b010)

// smode_internal is the usual serial mode: clock from SCLK, word strobe on.
pub const smode_internal = 0x15

// Video is the display timing of one television standard, as the boot ROM
// would have set it up.
pub struct Video {
pub:
	name   string
	hdb    int
	hde    int
	vdb    int // first visible half-line
	vde    int // one past the last visible half-line
	width  int // visible pixels at four clocks per pixel
	height int // visible lines
	clock  f64 // master clock in Hz
}

pub const ntsc = video_timing('NTSC', 1409, 241, 823, 266, 26_590_906)
pub const pal = video_timing('PAL', 1381, 287, 843, 322, 26_593_900)

// video_timing derives the display window registers from the width and
// height of the picture and the position of its centre.
fn video_timing(name string, clocks int, lines int, hmid int, vmid int, clock f64) Video {
	half := clocks / 2
	return Video{
		name:   name
		hdb:    hmid - half + 4
		hde:    (half - 1) | 0x400
		vdb:    vmid - lines
		vde:    vmid + lines
		width:  clocks / 4
		height: lines
		clock:  clock
	}
}

// sample_rate is the DSP's sample interrupt frequency for a value of SCLK.
pub fn (v Video) sample_rate(sclk_value int) f64 {
	return v.clock / f64(64 * (sclk_value + 1))
}
