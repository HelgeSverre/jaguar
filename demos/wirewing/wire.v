module main

import jagkit

// The picture: 320x200 at eight bits a pixel, a colour number each.
const screen_width = 320
const screen_height = 200

// The world is a grid of square cells, a height at every corner. Lengths
// are in 1/256 of a cell. The GPU draws the `grid` x `grid` corners around
// the eye.
const cell = 256
const grid = 16
const map_size = 32 // the height map repeats after this many cells
const height_shift = 3 // a height of 1 is 8 units
const near_plane = 128 // nothing nearer than this is drawn
const focal_shift = 8 // the picture plane is 256 pixels from the eye
const model_colour = 15

// Offsets of the values the 68000 and the GPU share, from the `shared`
// label of the GPU program. Positions are in units; sines are 2.14 fixed
// point.
const shared_eye_x = 4
const shared_eye_z = 8
const shared_eye_y = 12
const shared_yaw_sin = 16
const shared_yaw_cos = 20
const shared_roll_sin = 24
const shared_roll_cos = 28
const shared_horizon = 32 // screen line of the horizon
const shared_finished = 36 // the GPU leaves a finished frame's address here
const shared_first = 40 // the buffer to draw first
const shared_second = 44
const shared_heights = 48 // address of the height map, a byte a corner
const shared_points = 52 // address of room for the projected points
const shared_model = 56 // address of the model's points: x, y, z longs, from the eye
const shared_model_points = 60
const shared_model_lines = 64 // address of its lines: two point numbers each
const shared_model_line_count = 68
const shared_scratch = 72 // four longs the GPU keeps for itself

// A point behind the eye is stored as this.
const unseen = u32(0x8000_0000)

// wireframe is the GPU program. Every frame it clears the buffer, turns
// the corners of the landscape around the eye and the points of the model
// into screen positions, and joins them with lines.
fn wireframe() &jagkit.Risc {
	mailbox := jagkit.Reg.r14
	drawing := jagkit.Reg.r15
	showing := jagkit.Reg.r16
	yaw_sin := jagkit.Reg.r17
	yaw_cos := jagkit.Reg.r18
	roll_sin := jagkit.Reg.r19
	roll_cos := jagkit.Reg.r20
	horizon := jagkit.Reg.r21
	width := jagkit.Reg.r22
	height := jagkit.Reg.r23
	points := jagkit.Reg.r24
	near := jagkit.Reg.r25
	after_project := jagkit.Reg.r26 // where `project` returns to
	after_ray := jagkit.Reg.r27
	after_line := jagkit.Reg.r28
	project := jagkit.Reg.r29
	ray := jagkit.Reg.r30
	line := jagkit.Reg.r31
	// Scratch. `project` and `ray` use r0..r8; r9..r13 belong to the loops.
	a := jagkit.Reg.r0
	b := jagkit.Reg.r1
	c := jagkit.Reg.r2
	d := jagkit.Reg.r3
	e := jagkit.Reg.r4
	f := jagkit.Reg.r5
	g6 := jagkit.Reg.r6
	g7 := jagkit.Reg.r7
	colour := jagkit.Reg.r8
	eye_x := jagkit.Reg.r8 // only while the corners are projected
	eye_z := jagkit.Reg.r9
	eye_y := jagkit.Reg.r10
	height_map := jagkit.Reg.r11
	out := jagkit.Reg.r12
	count := jagkit.Reg.r13
	record := jagkit.Reg.r9
	first := jagkit.Reg.r10
	shade := jagkit.Reg.r11

	mut g := jagkit.new_risc(jagkit.gpu_ram)
	g.movei_label('shared', mailbox)
	g.movei(screen_width, width)
	g.movei(screen_height, height)
	g.movei(near_plane, near)
	g.movei_label('project', project)
	g.movei_label('ray', ray)
	g.movei_label('line', line)
	g.load_r14(shared_first, drawing)
	g.load_r14(shared_second, showing)
	g.load_r14(shared_points, points)

	g.label('frame')
	g.load_r14(shared_yaw_sin, yaw_sin)
	g.load_r14(shared_yaw_cos, yaw_cos)
	g.load_r14(shared_roll_sin, roll_sin)
	g.load_r14(shared_roll_cos, roll_cos)
	g.load_r14(shared_horizon, horizon)

	// Clear the buffer, four longs a turn.
	g.move(drawing, a)
	g.movei(screen_width * screen_height / 16, b)
	g.moveq(0, c)
	g.movei_label('clear', d)
	g.label('clear')
	g.store(c, a)
	g.addqt(4, a)
	g.store(c, a)
	g.addqt(4, a)
	g.store(c, a)
	g.addqt(4, a)
	g.store(c, a)
	g.subq(1, b)
	g.jump(.ne, d)
	g.addqt(4, a) // delay slot

	// The corners of the landscape. Corner n is column n % grid, row
	// n / grid of the square around the eye.
	g.load_r14(shared_eye_x, eye_x)
	g.load_r14(shared_eye_z, eye_z)
	g.load_r14(shared_eye_y, eye_y)
	g.load_r14(shared_heights, height_map)
	g.move(points, out)
	g.moveq(0, count)
	g.movei_label('corner_done', after_project)
	g.label('corner')
	g.move(count, a)
	g.moveq(grid - 1, d)
	g.and(d, a) // column
	g.move(count, c)
	g.shrq(4, c) // row
	g.moveq(map_size - 1, d)
	g.move(eye_x, e)
	g.shrq(8, e)
	g.add(a, e)
	g.subq(grid / 2, e)
	g.and(d, e) // the corner's column in the height map
	g.move(eye_z, f)
	g.shrq(8, f)
	g.add(c, f)
	g.subq(grid / 2, f)
	g.and(d, f) // and its row
	g.shlq(5, f)
	g.add(e, f)
	g.add(height_map, f)
	g.loadb(f, b)
	g.shlq(height_shift, b)
	g.sub(eye_y, b) // how far above the eye
	g.subq(grid / 2, a)
	g.shlq(8, a)
	g.move(eye_x, e)
	g.shlq(24, e)
	g.shrq(24, e) // how far the eye is into its cell
	g.sub(e, a) // how far right of the eye
	g.subq(grid / 2, c)
	g.shlq(8, c)
	g.move(eye_z, e)
	g.shlq(24, e)
	g.shrq(24, e)
	g.sub(e, c) // how far ahead of it, before turning
	g.jump(.always, project)
	g.nop()
	g.label('corner_done')
	g.store(a, out)
	g.addqt(4, out)
	g.store(b, out)
	g.addqt(4, out)
	g.addq(1, count)
	g.btst(8, count) // 256 corners
	g.movei_label('corner', d)
	g.jump(.eq, d)
	g.nop()

	// The model's points follow the corners.
	g.load_r14(shared_model, record)
	g.load_r14(shared_model_points, count)
	g.movei_label('model_point_done', after_project)
	g.label('model_point')
	g.load(record, a)
	g.addqt(4, record)
	g.load(record, b)
	g.addqt(4, record)
	g.load(record, c)
	g.jump(.always, project)
	g.addqt(4, record) // delay slot
	g.label('model_point_done')
	g.store(a, out)
	g.addqt(4, out)
	g.store(b, out)
	g.addqt(4, out)
	g.subq(1, count)
	g.movei_label('model_point', d)
	g.jump(.ne, d)
	g.nop()

	// The landscape's lines: from every corner to the next in its row and
	// to the one below it.
	g.moveq(0, count)
	g.label('corner_lines')
	g.move(count, record)
	g.shlq(3, record)
	g.add(points, record)
	g.load(record, first)
	g.addqt(4, record)
	g.load(record, shade)
	g.move(count, a)
	g.moveq(grid - 1, b)
	g.and(b, a)
	g.cmp(b, a)
	g.jr(.eq, 'no_line_right') // the last column has no neighbour
	g.nop()
	g.addqt(4, record)
	g.load(record, b)
	g.move(first, a)
	g.move(shade, c)
	g.movei_label('no_line_right', after_line)
	g.jump(.always, line)
	g.nop()
	g.label('no_line_right')
	g.movei(grid * (grid - 1), a)
	g.cmp(a, count)
	g.jr(.cc, 'no_line_down') // nor has the last row
	g.nop()
	g.move(count, record)
	g.addq(grid, record)
	g.shlq(3, record)
	g.add(points, record)
	g.load(record, b)
	g.move(first, a)
	g.move(shade, c)
	g.movei_label('no_line_down', after_line)
	g.jump(.always, line)
	g.nop()
	g.label('no_line_down')
	g.addq(1, count)
	g.btst(8, count)
	g.movei_label('corner_lines', a)
	g.jump(.eq, a)
	g.nop()

	// The model's lines.
	g.load_r14(shared_model_lines, record)
	g.load_r14(shared_model_line_count, count)
	g.movei(grid * grid * 8, first)
	g.add(points, first) // the model's first point
	g.movei_label('model_line_done', after_line)
	g.label('model_line')
	g.loadb(record, a)
	g.addqt(1, record)
	g.loadb(record, b)
	g.addqt(1, record)
	g.shlq(3, a)
	g.add(first, a)
	g.load(a, a)
	g.shlq(3, b)
	g.add(first, b)
	g.load(b, b)
	g.moveq(model_colour, c)
	g.jump(.always, line)
	g.nop()
	g.label('model_line_done')
	g.subq(1, count)
	g.movei_label('model_line', a)
	g.jump(.ne, a)
	g.nop()

	// Publish the frame, wait until it is taken, draw into the other.
	g.store_r14(drawing, shared_finished)
	g.label('wait')
	g.load_r14(shared_finished, a)
	g.cmpq(0, a)
	g.jr(.ne, 'wait')
	g.nop()
	g.move(drawing, a)
	g.move(showing, drawing)
	g.move(a, showing)
	g.movei_label('frame', a)
	g.jump(.always, a)
	g.nop()

	// project turns a point (a right, b up, c ahead of the eye, before
	// the eye's own turn) into a screen position in a (x in the high word,
	// y in the low) and a colour in b, darker with distance.
	g.label('project')
	g.move(a, d)
	g.imult(yaw_cos, d)
	g.move(c, e)
	g.imult(yaw_sin, e)
	g.sub(e, d)
	g.sharq(14, d) // right of where the eye looks
	g.imult(yaw_sin, a)
	g.imult(yaw_cos, c)
	g.add(a, c)
	g.sharq(14, c) // ahead of it
	g.cmp(near, c)
	g.jr(.pl, 'in_front')
	g.nop()
	g.movei(unseen, a)
	g.jump(.always, after_project)
	g.nop()
	g.label('in_front')
	// Perspective: divide by the distance. `div` is unsigned, so the
	// sign is taken off and put back.
	g.move(d, e)
	g.sharq(31, e)
	g.xor(e, d)
	g.sub(e, d)
	g.shlq(focal_shift, d)
	g.div(c, d)
	g.xor(e, d)
	g.sub(e, d)
	g.move(b, f)
	g.sharq(31, f)
	g.xor(f, b)
	g.sub(f, b)
	g.shlq(focal_shift, b)
	g.div(c, b)
	g.xor(f, b)
	g.sub(f, b)
	// Roll the picture around its centre.
	g.move(d, e)
	g.imult(roll_cos, e)
	g.move(b, f)
	g.imult(roll_sin, f)
	g.sub(f, e)
	g.sharq(14, e)
	g.imult(roll_sin, d)
	g.imult(roll_cos, b)
	g.add(d, b)
	g.sharq(14, b)
	g.move(width, f)
	g.shrq(1, f)
	g.add(f, e) // screen x
	g.move(horizon, f)
	g.sub(b, f) // screen y: up is towards line 0
	g.shlq(16, e)
	g.shlq(16, f)
	g.shrq(16, f)
	g.orr(f, e)
	g.move(e, a)
	// Colours 8 down to 1 for 0 to 7 cells away.
	g.shrq(8, c)
	g.moveq(7, b)
	g.cmp(c, b)
	g.jr(.pl, 'shade_known')
	g.nop()
	g.move(b, c)
	g.label('shade_known')
	g.sub(c, b)
	g.jump(.always, after_project)
	g.addq(1, b) // delay slot

	// line joins two screen positions a and b in colour c. A line is
	// drawn from an end that is on the screen towards the other, and
	// stopped where it leaves. With both ends off the screen it is drawn
	// from its middle both ways, if the middle is on it.
	g.label('line')
	g.movei(unseen, d)
	g.cmp(d, a)
	g.jump(.eq, after_line)
	g.nop()
	g.cmp(d, b)
	g.jump(.eq, after_line)
	g.nop()
	g.move(c, colour)
	g.move(a, e)
	g.sharq(16, e) // first x
	g.shlq(16, a)
	g.sharq(16, a) // first y
	g.move(b, f)
	g.sharq(16, f) // second x
	g.shlq(16, b)
	g.sharq(16, b) // second y
	g.cmp(width, e)
	g.jr(.cc, 'first_off')
	g.nop()
	g.cmp(height, a)
	g.jr(.cc, 'first_off')
	g.nop()
	g.move(b, d) // from the first end to the second
	g.move(a, b)
	g.move(e, a)
	g.move(f, c)
	g.move(after_line, after_ray)
	g.jump(.always, ray)
	g.nop()
	g.label('first_off')
	g.cmp(width, f)
	g.jr(.cc, 'both_off')
	g.nop()
	g.cmp(height, b)
	g.jr(.cc, 'both_off')
	g.nop()
	g.move(a, d) // from the second end to the first
	g.move(e, c)
	g.move(f, a)
	g.move(after_line, after_ray)
	g.jump(.always, ray)
	g.nop()
	g.label('both_off')
	g.move(e, g6)
	g.add(f, g6)
	g.sharq(1, g6) // middle x
	g.move(a, g7)
	g.add(b, g7)
	g.sharq(1, g7) // middle y
	g.cmp(width, g6)
	g.jump(.cc, after_line)
	g.nop()
	g.cmp(height, g7)
	g.jump(.cc, after_line)
	g.nop()
	g.store_r14(g6, shared_scratch)
	g.store_r14(g7, shared_scratch + 4)
	g.store_r14(f, shared_scratch + 8)
	g.store_r14(b, shared_scratch + 12)
	g.move(a, d) // from the middle to the first end
	g.move(e, c)
	g.move(g6, a)
	g.move(g7, b)
	g.movei_label('other_half', after_ray)
	g.jump(.always, ray)
	g.nop()
	g.label('other_half')
	g.load_r14(shared_scratch, a) // and from the middle to the second
	g.load_r14(shared_scratch + 4, b)
	g.load_r14(shared_scratch + 8, c)
	g.load_r14(shared_scratch + 12, d)
	g.move(after_line, after_ray)
	g.jump(.always, ray)
	g.nop()

	// ray draws from (a, b), which is on the screen, towards (c, d) in
	// `colour`, a pixel a step along the longer side, until it arrives or
	// leaves the screen.
	g.label('ray')
	g.sub(a, c) // how far right
	g.sub(b, d) // how far down
	g.move(c, e)
	g.abs(e)
	g.move(d, f)
	g.abs(f)
	g.cmp(e, f)
	g.jr(.cc, 'steps_known')
	g.nop()
	g.move(e, f)
	g.label('steps_known')
	g.cmpq(0, f)
	g.jr(.ne, 'not_a_dot')
	g.nop()
	g.moveq(1, f)
	g.label('not_a_dot')
	// The step in x and in y, 16.16 fixed point.
	g.move(c, e)
	g.sharq(31, e)
	g.xor(e, c)
	g.sub(e, c)
	g.shlq(16, c)
	g.div(f, c)
	g.xor(e, c)
	g.sub(e, c)
	g.move(d, e)
	g.sharq(31, e)
	g.xor(e, d)
	g.sub(e, d)
	g.shlq(16, d)
	g.div(f, d)
	g.xor(e, d)
	g.sub(e, d)
	g.shlq(16, a)
	g.shlq(16, b)
	g.bset(15, a) // start in the middle of the pixel
	g.bset(15, b)
	g.movei_label('ray_pixel', e)
	g.label('ray_pixel')
	g.move(a, g6)
	g.sharq(16, g6)
	g.cmp(width, g6)
	g.jump(.cc, after_ray) // off the left or the right
	g.nop()
	g.move(b, g7)
	g.sharq(16, g7)
	g.cmp(height, g7)
	g.jump(.cc, after_ray) // off the top or the bottom
	g.nop()
	g.mult(width, g7)
	g.add(g6, g7)
	g.add(drawing, g7)
	g.storeb(colour, g7)
	g.add(c, a)
	g.add(d, b)
	g.subq(1, f)
	g.jump(.pl, e)
	g.nop()
	g.jump(.always, after_ray)
	g.nop()

	g.align_long()
	g.label('shared')
	for _ in 0 .. 24 {
		g.long(0)
	}
	return g
}
