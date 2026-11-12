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

// renderer is the GPU program. For every pixel it looks up where on the
// wall the eye looks, adds the rotation and the distance travelled, fetches
// that texel and dims it by the fog. When a frame is finished it publishes
// the buffer and waits for the 68000 to show it, then draws into the other.
fn renderer() &jagkit.Risc {
	mailbox := jagkit.Reg.r14
	loop := jagkit.Reg.r15
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
	pixel := jagkit.Reg.r0
	depth := jagkit.Reg.r1
	fog := jagkit.Reg.r2
	luma := jagkit.Reg.r3

	mut g := jagkit.new_risc(jagkit.gpu_ram)
	g.movei_label('shared', mailbox)
	g.load_r14(shared_table, table_base)
	g.load_r14(shared_texture, texture)
	g.load_r14(shared_first, drawing)
	g.load_r14(shared_second, showing)
	g.movei(0x00ff, low_byte)
	g.movei(0xff00, high_byte)
	g.movei_label('pixel', loop)
	g.movei_label('frame', next_frame)

	g.label('frame')
	g.load_r14(shared_rotation, rotation)
	g.load_r14(shared_travel, travel)
	g.shlq(8, travel)
	g.move(table_base, table)
	g.move(drawing, target)
	g.movei(tunnel_pixels, left)

	g.label('pixel')
	g.load(table, pixel) // fog, depth, angle
	g.addqt(4, table)
	g.move(pixel, fog)
	g.shrq(16, fog)
	g.move(pixel, depth)
	g.add(rotation, pixel) // angle in the low byte; the carry is masked off
	g.add(travel, depth) // depth in the second byte
	g.and(low_byte, pixel)
	g.and(high_byte, depth)
	g.orr(depth, pixel) // ring * 256 + angle
	g.add(pixel, pixel)
	g.add(texture, pixel)
	g.loadw(pixel, pixel) // the CRY texel
	g.move(pixel, luma)
	g.and(low_byte, luma)
	g.mult(fog, luma)
	g.shrq(8, luma)
	g.and(high_byte, pixel) // keep the hue, replace the brightness
	g.orr(luma, pixel)
	g.storew(pixel, target)
	g.subq(1, left)
	g.jump(.ne, loop)
	g.addqt(2, target) // delay slot

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
	for _ in 0 .. 8 {
		g.long(0)
	}
	return g
}
