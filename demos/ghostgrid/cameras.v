// The cameras of GHOSTGRID. A camera is an actor (jaggame.Actors) on a pillar
// of the map. It sweeps a cone of light between two angles in steps of 11
// degrees, one step every 24 frames, and the cone is lit on the floor like a
// guard's: what is lit is what sees. The cones of a camera's positions were
// worked out when the game was built (world.v), so a step is a look-up and
// one `light` (guards.v) like a guard's.
//
// The rules:
//
//   - a camera holds still while the figure is in its light and goes on
//     sweeping when it is out of it
//   - cover does not hide the figure from a camera: it looks from above, so
//     a crouching figure in the light is seen all the same
//   - the light on the figure grows an exposure (a frame in the light adds
//     one, a frame out of it takes one off every second frame)
//   - at 12 the camera has seen the figure: that is one time seen, and every
//     guard within 12 tiles of the camera (across plus down) that is on
//     patrol or on its way back becomes suspicious about the spot
//   - at 60 the guards within that reach that are not chasing already are
//     alert, and chase the figure
//   - when the exposure is back to 0 the camera can see the figure for the
//     first time again
module main

import jaggame

const cam_period = 24 // frames between two positions of a sweep
const cam_notice = 12 // frames in the light before the camera has seen the figure
const cam_alarm = 60 // frames in the light before the guards chase
const cam_reach = 192 // pixels, across plus down, within which a guard is called

// cam_fields are what a camera's record holds besides what every actor has.
fn cam_fields() []jaggame.Field {
	return [jaggame.Field{'step', .u8}, jaggame.Field{'dir', .bool},
		jaggame.Field{'wait', .u8}, jaggame.Field{'exposure', .u8},
		jaggame.Field{'alarm', .u8}, jaggame.Field{'n', .u8},
		jaggame.Field{'a0', .u8}, jaggame.Field{'tx', .u8}, jaggame.Field{'ty', .u8},
		jaggame.Field{'stale', .bool}, jaggame.Field{'cone_n', .u8}]
}

// cf is a field of camera `i`.
fn (m &Mission) cf(i jaggame.Val, name string) jaggame.Expr {
	return m.cams.field(i, name)
}

// define_cameras writes `think_camera` (one camera's frame) and `call_guards`.
fn (mut m Mission) define_cameras() {
	mut game := m.game
	mut p := game.p

	// call_guards: every guard near camera `i` that is not past it already
	// comes to the figure: suspicious (mode 1) or alert (mode 2).
	mut c := p.define(m.call_guards)
	ci := m.call_guards.arg('i')
	mode := m.call_guards.arg('mode')
	g := c.local_u16('g')
	camx := c.local_i32('camx')
	camy := c.local_i32('camy')
	c.set(camx, m.cf(ci, 'tx').as_(.i32).mul(16).add(8))
	c.set(camy, m.cf(ci, 'ty').as_(.i32).mul(16).add(8))
	// guide:gg_call
	m.guards.each(mut c, g)
	state := m.ai.state_of(g)

	c.if_(m.gcx(g).sub(camx).abs().add(m.gcy(g).sub(camy).abs()).le(cam_reach))
	m.spot_figure(mut c, g)

	c.if_(mode.eq(1))

	c.if_(state.eq(0).either(state.eq(4)))
	m.ai.start(mut c, g, 'suspicious')
	c.end() // on patrol or on the way back
	c.else_()

	c.if_(state.ne(2))
	m.ai.start(mut c, g, 'alert')
	c.end() // not chasing already
	c.end() // which call
	c.end() // near the camera
	c.end() // each guard
	// guide:end

	// think_camera: sweep, light, look.
	c = p.define(m.think)
	i := m.think.arg('i')
	step := m.cf(i, 'step')
	n := m.cf(i, 'n')
	exposure := m.cf(i, 'exposure')
	alarm := m.cf(i, 'alarm')
	sprite := m.cams.sprite(i)
	face := c.local_u8('face')
	redraw := c.local_bool('redraw')
	c.set(redraw, m.cf(i, 'stale'))

	// The sweep: it holds while the figure is in its light.
	// guide:gg_sweep
	c.if_(exposure.eq(0).both(n.gt(1)))
	c.set(m.cf(i, 'wait'), m.cf(i, 'wait').add(1))

	c.if_(m.cf(i, 'wait').ge(cam_period))
	c.set(m.cf(i, 'wait'), 0)

	c.if_(m.cf(i, 'dir').invert())

	c.if_(step.add(1).ge(n))
	c.set(m.cf(i, 'dir'), true)
	c.dec(step)
	c.else_()
	c.inc(step)
	c.end() // the far end, or on
	c.else_()

	c.if_(step.eq(0))
	c.set(m.cf(i, 'dir'), false)
	c.inc(step)
	c.else_()
	c.dec(step)
	c.end() // the near end, or back
	c.end() // which way
	c.set(m.cf(i, 'stale'), true)
	c.set(redraw, true)
	c.end() // time to turn
	c.end() // sweeping
	// guide:end

	c.if_(m.cf(i, 'stale').both(m.worked.invert()))
	c.set(m.worked, true)
	c.set(m.cf(i, 'cone_n'), m.light.call(i.add(max_guards),
		game.room_number.as_(.u16).mul(keys_per_room).add(room_cells * 4).add(i.mul(cam_steps)).add(step.as_(.u16)), m.cf(i,
		'cone_n')))
	c.set(m.cf(i, 'stale'), false)
	c.end() // a new position

	// Looking: the exposure grows in the light and fades out of it.
	// guide:gg_look
	seeing := m.lit.at(m.pcell).and(jaggame.lit(1).as_(.u16).shl(i.add(max_guards))).ne(0)

	c.if_(seeing)

	c.if_(exposure.lt(255))
	c.inc(exposure)
	c.end() // not at the top
	c.else_if(game.frame.and(1).eq(0).both(exposure.gt(0)))
	c.dec(exposure)
	c.end() // seen or not

	c.if_(exposure.eq(0).both(alarm.ne(0)))
	c.set(alarm, 0)
	c.set(redraw, true)
	c.end() // out of the light

	c.if_(exposure.ge(cam_notice).both(alarm.eq(0)))
	c.set(alarm, 1)
	c.set(redraw, true)
	c.inc(m.seen)
	game.play(mut c, 'spotted')
	c.call(m.call_guards, i, 1)
	c.end() // it has seen the figure

	c.if_(exposure.ge(cam_alarm).both(alarm.lt(2)))
	c.set(alarm, 2)
	c.call(m.call_guards, i, 2)
	c.end() // the alarm
	// guide:end

	// The picture: the camera looks along its angle (left is the right
	// frame flipped), and its lens is red once it has seen the figure.
	// guide:gg_cam_sprite
	c.if_(redraw)
	c.set(face, m.cf(i, 'a0').add(step.mul(cam_turn)).add(32).shr(6).and(3))
	c.set(sprite.flip, face.eq(2))
	c.set(sprite.frame, jaggame.lit(0).as_(.u8))

	c.if_(face.eq(1))
	c.set(sprite.frame, 1)
	c.else_if(face.eq(3))
	c.set(sprite.frame, 2)
	c.end() // down or up

	c.if_(alarm.ne(0))
	c.set(sprite.frame, sprite.frame.add(3))
	c.end() // alarmed
	c.end() // something changed
	// guide:end
}
