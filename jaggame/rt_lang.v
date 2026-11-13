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

	if g.scene_set {
		g.scene_ref.finish()
	}
	if g.sounds {
		g.define_sound()
	}
	if g.save_info.len > 0 {
		g.define_save()
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
	if g.save_info.len > 0 {
		// the interpreter's chip starts erased
		c.for_(i, 0, eeprom_words_total)
		c.set(g.save_info[0].eeprom.at(i), 0xffff)
		c.end() // each word
	}
	c.call(g.init_func)
	if g.scene_set && g.scene_ref.has_start() {
		c.call(g.scene_ref.gos[g.scene_ref.first])
	}

	frame := g.p.func('rt_frame', [], .void)
	c = g.p.define(frame)
	c.inc(g.frame)
	if g.sight_ready {
		c.if_(g.sight.noise_left.ne(0))
		c.dec(g.sight.noise_left)
		c.end() // a noise dies away
	}
	if g.map_ready {
		// The tiles that were drawn last frame leave the ring.
		drawn := c.local_u8('drawn')
		c.set(drawn, g.tv.queued.min(g.tv.budget))
		c.set(g.tv.head, g.tv.head.add(drawn).and(tile_queue_size - 1))
		c.set(g.tv.queued, g.tv.queued.sub(drawn))
	}
	if g.timers.len > 0 {
		tick := g.p.func('rt_tick', [], .void)
		g.define_timers(tick)
		c.call(tick)
	}
	c.call(g.update_func)
	if g.scene_set {
		c.call(g.scene_ref.tick)
	}
	if g.backdrop_used {
		g.define_backdrop(mut c)
	}
	if g.save_info.len > 0 {
		c.call(g.save_info[0].tick)
	}
	if g.seqs.len > 0 {
		animate := g.p.func('rt_animate', [], .void)
		g.define_animate(animate)
		c.call(animate)
	}
	if g.map_ready {
		c.call(g.tv.load_step)
		// What waits to be drawn: a few a frame, more when many wait.
		c.set(g.tv.budget, tile_draws_light)

		c.if_(g.tv.queued.ge(tile_draws_per_frame))
		c.set(g.tv.budget, tile_draws_per_frame)
		c.end() // a lot to draw
	}
	if g.sounds {
		c.call(g.snd.tick)
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
