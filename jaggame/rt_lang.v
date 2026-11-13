module jaggame

// The parts of the runtime that are written in the language itself, so that
// the interpreter runs them too: start-up of the variables, the work of one
// frame, animations.

// define_runtime writes `rt_init` and `rt_frame`, the two functions the
// machine's start-up and its frame interrupt call, and what they use.
fn (mut g Game) define_runtime() {
	if g.defined {
		return
	}
	g.defined = true
	g.parse_rooms()
	if !g.has_init {
		g.p.define(g.init_func)
	}
	if !g.has_update {
		g.p.define(g.update_func)
	}
	g.define_text()
	if g.map_ready {
		g.define_map()
	}
	if g.sight_ready {
		g.define_sight()
	}

	init := g.p.func('rt_init', [], .void)
	mut c := g.p.define(init)
	i := c.local_u16('i')

	c.for_(i, 0, g.config.sprites)
	c.set(g.sprite_at(i).scale, 1.0)
	c.end() // for each sprite

	c.if_(g.pal.ne(0))
	c.set(g.fps, 50)
	c.else_()
	c.set(g.fps, 60)
	c.end()
	c.call(g.init_func)

	frame := g.p.func('rt_frame', [], .void)
	c = g.p.define(frame)
	c.inc(g.frame)
	if g.sight_ready {
		c.if_(g.sight.noise_left.ne(0))
		c.dec(g.sight.noise_left)
		c.end() // a noise dies away
	}
	if g.map_ready {
		c.set(g.tv.queued, 0) // the tiles changed last frame were drawn
	}
	if g.timers.len > 0 {
		tick := g.p.func('rt_tick', [], .void)
		g.define_timers(tick)
		c.call(tick)
	}
	c.call(g.update_func)
	if g.seqs.len > 0 {
		animate := g.p.func('rt_animate', [], .void)
		g.define_animate(animate)
		c.call(animate)
	}
	if g.map_ready {
		c.call(g.tv.load_step)
	}
	if g.sounds {
		c.set(g.beep_volume, g.beep_volume.sub(g.beep_volume.shr(3)))
	}
}

// define_animate writes the function that moves every playing animation on
// one frame. The durations are tables of frames, one for each standard.
fn (mut g Game) define_animate(f Func) {
	mut first := []int{}
	mut lens := []int{}
	mut frames := []int{}
	mut ntsc := []int{}
	mut pal := []int{}
	for s in g.seqs {
		first << frames.len
		lens << s.steps.len
		for st in s.steps {
			frames << st.frame
			ntsc << frames_for(st.seconds, 60)
			pal << frames_for(st.seconds, 50)
		}
	}
	total := frames.len
	mut both := ntsc.clone()
	both << pal
	ticks := g.p.table_u16('rt_step_ticks', both)
	seq_first := g.p.table_u16('rt_seq_first', first)
	seq_len := g.p.table_u8('rt_seq_length', lens)
	step_frame := g.p.table_u8('rt_step_frame', frames)

	mut c := g.p.define(f)
	i := c.local_u16('i')
	index := c.local_u16('index')

	c.for_(i, 0, g.config.sprites)
	s := g.sprite_at(i)
	seq := s.element.field('seq')
	step := s.element.field('step')
	wait := s.element.field('wait')

	c.if_(seq.ne(0))
	c.dec(wait)

	c.if_(wait.eq(0))
	c.inc(step)

	c.if_(step.ge(seq_len.at(seq.sub(1))))
	c.if_(s.element.field('loops'))
	c.set(step, 0)
	c.else_()
	c.set(seq, 0)
	c.end() // loops
	c.end() // past the last step

	c.if_(seq.ne(0))
	c.set(index, seq_first.at(seq.sub(1)).add(step))
	c.set(s.frame, step_frame.at(index))
	c.set(wait, ticks.at(index.add(g.pal.as_(.u16).mul(total))))
	c.end() // still playing
	c.end() // the step is over
	c.end() // playing
	c.end() // for each sprite
}
