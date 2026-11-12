module main

import jagkit

// Offsets of the values the 68000 and the GPU share, from the `shared`
// label of the GPU program.
const shared_rotation = 4 // angle added to every pixel, 0..255
const shared_travel = 8 // depth added to every pixel, 0..255
const shared_finished = 12 // the GPU leaves a finished frame's address here
const shared_table = 16
const shared_texture = 20
const shared_first = 24 // the buffer to draw first
const shared_second = 28
const shared_palette = 32 // address of the palette phase to draw with
const shared_window = 36 // where the screen sits on the table: y in the high word, x in the low
const shared_drawn = 40 // the window the finished frame was drawn with

// renderer is the GPU program. For every pixel it looks up where on the
// wall the eye looks, adds the rotation and the distance travelled, fetches
// that texel and turns it into a colour through the palette of the pixel's
// fog level. When a frame is finished it publishes the buffer and waits for
// the 68000 to show it, then draws into the other.
fn renderer() &jagkit.Risc {
	mailbox := jagkit.Reg.r14
	pixel_loop := jagkit.Reg.r15
	next_frame := jagkit.Reg.r16
	drawing := jagkit.Reg.r17
	showing := jagkit.Reg.r18
	table_base := jagkit.Reg.r19
	table := jagkit.Reg.r20
	target := jagkit.Reg.r21
	left := jagkit.Reg.r22
	texture := jagkit.Reg.r23
	low_byte := jagkit.Reg.r24
	high_byte := jagkit.Reg.r25
	rotation := jagkit.Reg.r26
	travel := jagkit.Reg.r27
	rows := jagkit.Reg.r4
	row := jagkit.Reg.r5
	row_pixels := jagkit.Reg.r6
	row_bytes := jagkit.Reg.r7
	row_loop := jagkit.Reg.r8
	palette := jagkit.Reg.r9
	window := jagkit.Reg.r10
	pixel := jagkit.Reg.r0
	depth := jagkit.Reg.r1
	fog := jagkit.Reg.r2

	mut g := jagkit.new_risc(jagkit.gpu_ram)
	g.movei_label('shared', mailbox)
	g.load_r14(shared_table, table_base)
	g.load_r14(shared_texture, texture)
	g.load_r14(shared_first, drawing)
	g.load_r14(shared_second, showing)
	g.movei(0x00ff, low_byte)
	g.movei(0xff00, high_byte)
	g.movei(tunnel_width, row_pixels)
	g.movei(table_width * 4, row_bytes)
	g.movei_label('pixel', pixel_loop)
	g.movei_label('row', row_loop)
	g.movei_label('frame', next_frame)

	g.label('frame')
	g.load_r14(shared_rotation, rotation)
	g.load_r14(shared_travel, travel)
	g.shlq(8, travel)
	g.load_r14(shared_palette, palette)
	g.load_r14(shared_window, window)
	// The first table entry of the window: base + (y * width + x) * 4.
	g.move(window, row)
	g.shrq(16, row)
	g.mult(row_bytes, row)
	g.move(window, pixel)
	g.shlq(16, pixel) // drop y ...
	g.shrq(14, pixel) // ... and leave x * 4
	g.add(pixel, row)
	g.add(table_base, row)
	g.move(drawing, target)
	g.movei(tunnel_height, rows)

	g.label('row')
	g.move(row, table)
	g.move(row_pixels, left)

	g.label('pixel')
	g.load(table, pixel) // fog, depth, angle
	g.addqt(4, table)
	g.move(pixel, fog)
	g.shrq(16, fog) // offset of the fog level's palette
	g.move(pixel, depth)
	g.add(rotation, pixel) // angle in the low byte; the carry is masked off
	g.add(travel, depth) // depth in the second byte
	g.and(low_byte, pixel)
	g.and(high_byte, depth)
	g.orr(depth, pixel) // ring * 256 + angle
	g.add(texture, pixel)
	g.loadb(pixel, pixel) // the texel: a colour number
	g.add(pixel, pixel)
	g.add(fog, pixel)
	g.add(palette, pixel)
	g.loadw(pixel, pixel) // the colour
	g.storew(pixel, target)
	g.subq(1, left)
	g.jump(.ne, pixel_loop)
	g.addqt(2, target) // delay slot

	g.add(row_bytes, row)
	g.subq(1, rows)
	g.jump(.ne, row_loop)
	g.nop()

	g.store_r14(window, shared_drawn)
	g.store_r14(drawing, shared_finished)
	g.label('wait')
	g.load_r14(shared_finished, pixel)
	g.cmpq(0, pixel)
	g.jr(.ne, 'wait')
	g.nop()
	g.move(drawing, pixel)
	g.move(showing, drawing)
	g.move(pixel, showing)
	g.jump(.always, next_frame)
	g.nop()

	g.align_long()
	g.label('shared')
	for _ in 0 .. 12 {
		g.long(0)
	}
	return g
}
