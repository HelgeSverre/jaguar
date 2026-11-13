module jaggame

import os
import stbi

// Canvas is a picture to draw on and save as a PNG: for the small programs
// that make a game's art (see demos/ghostgrid/art) and for tests that need
// a file to import. A pixel is red, green, blue and alpha, 0..255; an alpha
// of 0 is transparent.
pub struct Canvas {
pub:
	width  int
	height int
pub mut:
	pixels []u8 // four bytes a pixel, a line after a line
}

// new_canvas makes a transparent picture.
pub fn new_canvas(width int, height int) Canvas {
	return Canvas{
		width:  width
		height: height
		pixels: []u8{len: width * height * 4}
	}
}

// put sets one pixel; a place outside the canvas is ignored.
pub fn (mut c Canvas) put(x int, y int, r int, g int, b int, a int) {
	if x < 0 || y < 0 || x >= c.width || y >= c.height {
		return
	}
	i := (y * c.width + x) * 4
	c.pixels[i] = u8(r)
	c.pixels[i + 1] = u8(g)
	c.pixels[i + 2] = u8(b)
	c.pixels[i + 3] = u8(a)
}

// fill paints an opaque rectangle.
pub fn (mut c Canvas) fill(x int, y int, w int, h int, r int, g int, b int) {
	for yy in y .. y + h {
		for xx in x .. x + w {
			c.put(xx, yy, r, g, b, 255)
		}
	}
}

// save writes the canvas as a PNG file, making the directory if it is missing.
pub fn (c Canvas) save(path string) ! {
	os.mkdir_all(os.dir(path))!
	stbi.stbi_write_png(path, c.width, c.height, 4, c.pixels.data, c.width * 4)!
}
