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

fn problems_of(p &Program) string {
	p.check() or { return err.msg() }
	return ''
}

fn test_a_transition_to_a_state_that_does_not_exist_is_a_build_error() {
	mut p := new_program()
	mut m := p.machine_global('door')
	mut c := m.state('open')
	c.to('closed')
	text := problems_of(p)
	assert text.contains('a transition to the state `closed`, which does not exist'), text
	assert text.contains('the states are: open'), text
}

fn test_a_machine_without_states_and_a_state_defined_twice_are_build_errors() {
	mut p := new_program()
	p.machine_global('empty')
	mut m := p.machine_global('twice')
	m.state('a')
	m.state('a')
	text := problems_of(p)
	assert text.contains('machine `empty` has no states'), text
	assert text.contains('the state `a` is defined twice'), text
	assert !text.contains('machine `twice` has no states'), text
}

fn test_machine_mistakes_are_reported_together_with_the_others() {
	mut p := new_program()
	x := p.u8('x')
	mut m := p.machine_global('m')
	mut c := m.state('a')
	c.set(x, 300) // does not fit a u8
	c.to('nowhere')
	m.on_enter('ghost') // for a state that is not there
	main := p.func('main', [], .void)
	mut mc := p.define(main)
	mc.to('a') // not in a state
	text := problems_of(p)
	assert text.contains('300 does not fit u8'), text
	assert text.contains('to(`a`) outside the body of a state'), text
	assert text.contains('which does not exist'), text
	assert text.contains('on_enter(`ghost`) belongs to a state that does not exist'), text
}

fn test_a_machine_needs_an_array_and_a_state_can_be_named_before_it_exists() {
	mut p := new_program()
	x := p.u8('x')
	p.machine('flat', x)
	assert problems_of(p).contains('needs an array or an array of records')
	// A forward reference is fine: `a` goes to `b`, declared after.
	mut q := new_program()
	mut m := q.machine_global('fwd')
	mut c := m.state('a')
	c.to('b')
	c = m.state('b')
	c.to('a')
	assert problems_of(q) == ''
}

fn test_on_enter_runs_at_the_transition_and_sees_time_zero() {
	mut p := new_program()
	log := p.array_u8('log', 8)
	n := p.u8('n')
	mut m := p.machine_global('m')
	mut c := m.state('idle')
	c.to('busy')
	c = m.state('busy')
	c.set(log.at(n), 20)
	c.inc(n)
	c = m.on_enter('busy')
	c.set(log.at(n), c.time_in_state().add(100).as_(.u8))
	c.inc(n)
	main := p.func('main', [], .void)
	mut mc := p.define(main)
	m.run(mut mc, 0)
	mut it := p.interpreter()!
	it.run('main')!
	it.run('main')!
	it.run('main')!
	// frame 1: idle goes to busy; on_enter logs 100 (time 0); frame 2: busy logs 20; frame 3: 20 again
	assert [it.element('log', 0)!, it.element('log', 1)!, it.element('log', 2)!] == [
		i64(100),
		20,
		20,
	]
	assert it.element('m_time', 0)! == 2
}
