module jaggame

fn test_a_machine_walks_through_its_states() {
	mut p := new_program()
	log := p.array_u8('log', 16)
	n := p.u8('n')
	mut m := p.machine_global('light')
	mut c := m.state('red')
	c.set(log.at(n), 1)
	c.inc(n)
	c.if_(c.time_in_state().eq(2))
	c.to('green')
	c.end()
	c = m.state('green')
	c.set(log.at(n), 2)
	c.inc(n)
	c.to('red')
	main := p.func('main', [], .void)
	mut mc := p.define(main)
	m.run(mut mc, 0)
	mut it := p.interpreter()!
	for _ in 0 .. 8 {
		it.run('main')!
	}
	// red for frames 0, 1, 2 (time 0, 1, 2), then green once, then red again
	expected := [1, 1, 1, 2, 1, 1, 1, 2]
	for i, e in expected {
		assert it.element('log', i)! == e, 'frame ${i}'
	}
}

fn test_actors_spawn_and_are_visited() {
	mut g := new_game(Config{ sprites: 6 })
	a := g.actors('crowd', [Field{'hp', .u8}], 4, 2)
	total := g.p.u16('total')
	got := g.p.u16('got')
	mut c := g.define_update()
	i := c.local_u16('i')
	c.if_(g.frame.eq(1))
	c.set(got, a.spawn(10, 20))
	c.set(got, a.spawn(30.5, 40))
	c.set(a.field(1, 'hp'), 7)
	a.remove(mut c, 0)
	c.end()
	a.each(mut c, i)
	c.add_to(total, a.field(i, 'hp').as_(.u16).add(i).add(1))
	c.end()
	mut it := g.interpreter(.ntsc)!
	g.step(mut it, 0)!
	g.step(mut it, 0)!
	assert it.value('got')! == 1
	assert it.value('total')! == 2 * (7 + 1 + 1) // two frames; only actor 1 lives: hp 7 + index 1 + 1
	assert it.field('crowd', 1, 'x')! == 30 * 65536 + 32768
	assert it.field('sprites', 3, 'visible')! == 1 && it.field('sprites', 2, 'visible')! == 0
}
