module hwtypes

// Region selects the television standard of the emulated console.
pub enum Region {
	ntsc
	pal
}

// master_clock_hz is the crystal frequency every device clock derives from.
pub fn (r Region) master_clock_hz() u64 {
	return match r {
		.ntsc { u64(26_590_906) }
		.pal { u64(26_593_900) }
	}
}

// FrameInfo describes a completed video frame. Pixels are 0x00RRGGBB, one
// `u32` per pixel, `pitch` pixels per row.
pub struct FrameInfo {
pub:
	width    int
	height   int
	pitch    int
	sequence u64
	// pixel_aspect is the width of one pixel relative to its height. The
	// console's pixel clock divider changes it, so presentation must stretch
	// the image by this factor to restore the 4:3 picture.
	pixel_aspect f64
}
