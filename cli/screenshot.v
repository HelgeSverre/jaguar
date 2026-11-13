module cli

import os
import stbi
import machine

// FrameStats summarises a picture for automated triage.
pub struct FrameStats {
pub:
	width    int
	height   int
	colours  int // distinct colours, capped at `colour_cap`
	lit      f64 // fraction of pixels that are not the most common colour
	checksum u64
}

const colour_cap = 4096

// frame_rgb copies the current frame into tightly packed RGB bytes.
fn frame_rgb(m &machine.Machine) ([]u8, int, int) {
	pixels, info := m.frame()
	mut rgb := []u8{len: info.width * info.height * 3}
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			pixel := pixels[y * info.pitch + x]
			i := (y * info.width + x) * 3
			rgb[i] = u8(pixel >> 16)
			rgb[i + 1] = u8(pixel >> 8)
			rgb[i + 2] = u8(pixel)
		}
	}
	return rgb, info.width, info.height
}

// write_png saves the current frame at its native resolution.
pub fn write_png(m &machine.Machine, path string) ! {
	rgb, width, height := frame_rgb(m)
	stbi.stbi_write_png(path, width, height, 3, rgb.data, width * 3)!
}

// Film is a video written as a stream of binary PPM images, one per frame:
// `ffmpeg -f image2pipe -c:v ppm -i frames.ppm`.
pub struct Film {
mut:
	file   os.File
	width  int = 320
	height int = 240
}

// add appends the current frame. While video is off the machine has no
// picture; the film then gets a black frame of the last size, so it keeps one
// image per emulated frame.
pub fn (mut f Film) add(m &machine.Machine) ! {
	mut rgb, width, height := frame_rgb(m)
	if width == 0 || height == 0 {
		rgb = []u8{len: f.width * f.height * 3}
	} else {
		f.width = width
		f.height = height
	}
	f.file.write_string('P6\n${f.width} ${f.height}\n255\n')!
	f.file.write(rgb)!
}

// frame_stats measures the current frame.
pub fn frame_stats(m &machine.Machine) FrameStats {
	pixels, info := m.frame()
	mut histogram := map[u32]int{}
	mut checksum := u64(0xcbf2_9ce4_8422_2325)
	for y in 0 .. info.height {
		for x in 0 .. info.width {
			pixel := pixels[y * info.pitch + x]
			checksum = (checksum ^ pixel) * 0x0000_0100_0000_01b3
			if pixel in histogram || histogram.len < colour_cap {
				histogram[pixel]++
			}
		}
	}
	mut most_common := 0
	for _, count in histogram {
		if count > most_common {
			most_common = count
		}
	}
	total := info.width * info.height
	return FrameStats{
		width:    info.width
		height:   info.height
		colours:  histogram.len
		lit:      if total == 0 { 0.0 } else { 1.0 - f64(most_common) / f64(total) }
		checksum: checksum
	}
}
