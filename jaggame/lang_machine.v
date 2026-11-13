module jaggame

// State machines. A machine has named states, each with a body that runs
// once a frame while the machine is in it, and an optional `on_enter` body
// that runs when a transition arrives. A machine belongs to an array (one
// state for each element, so one machine can run a whole squad) or to
// nothing (a single global one).
//
//	guard_ai := p.machine('guard_ai', guards)
//	mut c := guard_ai.state('patrol')
//	c.if_(c.time_in_state().gt(120))
//	c.to('look')
//	c.end()
//	c = guard_ai.state('look')
//	…
//	guard_ai.run(mut update, i)
//
// A machine is not a new kind of statement: it is written out as ordinary
// functions and arrays of the program, so the interpreter and the compiled
// code cannot disagree about it. For a machine `m` the program gets
//
//	m_state, m_time, m_fresh   arrays with one element for each record
//	m_<state>(self)            the body of a state; `self` is the record's index
//	m_<state>_enter(self)      its on_enter body
//	m_to_<state>(self)         the transition: set the state, time 0, run on_enter
//	m_run(self)                the dispatch: call the body of the current state,
//	                           then count a frame
//
// The tests read the state of a record by name from `m_state`.

@[heap]
pub struct Machine {
pub:
	name string
	size int // how many records have a state
mut:
	prog     &Program
	index    int
	states   Expr // u8 array: the state of each record, as the number of its declaration
	time     Expr // u16 array: frames since the state was entered, as the body sees them
	fresh    Expr // u8 array: 1 from a transition until the end of that frame's `run`
	names    []string
	funcs    []Func          // the body of each state
	entries  map[string]Func // the on_enter body of a state, by name
	enters   map[string]Func // the transition functions that something asked for
	asked    []string        // the names in `enters`, in the order they were asked for
	dispatch Func
	done     bool
}

// machine declares a state machine with one state for each element of an
// array (an array of records, usually). All start in the first state that is
// declared, with time 0, without its `on_enter` having run (use `start` for
// that).
pub fn (mut p Program) machine(name string, of Expr) &Machine {
	mut size := 1
	if of.node.kind == .variable && of.node.var >= 0
		&& p.vars[of.node.var].kind in [.array, .records] {
		size = p.vars[of.node.var].len
	} else {
		p.problems << 'machine `${name}`: it needs an array or an array of records to be the machine of, not ${p.show(of)}'
	}
	return p.new_machine(name, size)
}

// machine_global declares a machine that is not tied to an array: one state,
// at index 0. Run it with `run(c, 0)`.
pub fn (mut p Program) machine_global(name string) &Machine {
	return p.new_machine(name, 1)
}

fn (mut p Program) new_machine(name string, size int) &Machine {
	states := p.array_u8('${name}_state', size)
	time := p.array_u16('${name}_time', size)
	fresh := p.array_u8('${name}_fresh', size)
	dispatch := p.func('${name}_run', [Param{'self', .u16}], .void)
	mut m := &Machine{
		name:     name
		size:     size
		prog:     p
		index:    p.machines.len
		states:   states
		time:     time
		fresh:    fresh
		dispatch: dispatch
	}
	p.machines << m
	return m
}

// state_id is the number of a state (from 0, in the order they were
// declared), or -1.
pub fn (m &Machine) state_id(name string) int {
	return m.names.index(name)
}

// state declares a state and returns the block to write its body in: the
// body runs once a frame for every record the machine finds in the state.
// Inside it, `me()` is the record's index, `time_in_state()` the frames it has
// been here and `to(name)` leaves.
pub fn (mut m Machine) state(name string) &Code {
	mut p := m.prog
	mut label := name
	if name in m.names {
		p.problems << 'machine `${m.name}`: the state `${name}` is defined twice'
		label = '${name}_again_${m.names.len}'
	}
	f := p.func('${m.name}_${label}', [Param{'self', .u16}], .void)
	mut c := p.define(f)
	c.machine = m.index
	c.self = f.arg('self')
	if name !in m.names {
		m.names << name
		m.funcs << f
	}
	return c
}

// on_enter declares the block that runs when a transition enters the state,
// before the first frame of its body. The state may be declared before or
// after.
pub fn (mut m Machine) on_enter(name string) &Code {
	mut p := m.prog
	mut label := name
	if name in m.entries {
		p.problems << 'machine `${m.name}`: on_enter(`${name}`) is defined twice'
		label = '${name}_again_${m.entries.len}'
	}
	f := p.func('${m.name}_${label}_enter', [Param{'self', .u16}], .void)
	mut c := p.define(f)
	c.machine = m.index
	c.self = f.arg('self')
	if name !in m.entries {
		m.entries[name] = f
	}
	return c
}

// enter_func is the transition function of a state, made when something
// first asks for it. Whether the state exists is checked when the program is
// built, so a state can be named before it is declared.
fn (mut m Machine) enter_func(name string) Func {
	if name in m.enters {
		return m.enters[name]
	}
	mut p := m.prog
	f := p.func('${m.name}_to_${name}', [Param{'self', .u16}], .void)
	m.enters[name] = f
	m.asked << name
	return f
}

// start puts a record in a state from outside the machine's own bodies (when
// an actor is spawned, say) and runs its `on_enter`.
pub fn (mut m Machine) start(mut c Code, index Val, state string) {
	c.call(m.enter_func(state), index)
}

// run runs the machine for one record: the body of its state, then the
// frame is counted. Call it from the update, for each record.
pub fn (m &Machine) run(mut c Code, index Val) {
	c.call(m.dispatch, index)
}

// state_of is the number of the state a record is in, a `u8` expression
// (the number of the state's declaration, from 0).
pub fn (m &Machine) state_of(index Val) Expr {
	return m.states.at(index)
}

// time_of is the frames a record has been in its state, a `u16` expression:
// 0 in the first frame of the state, counting up to 65535.
pub fn (m &Machine) time_of(index Val) Expr {
	return m.time.at(index)
}

// in_state is true when a record is in the named state. The state must be
// declared already.
pub fn (mut m Machine) in_state(index Val, name string) Expr {
	id := m.state_id(name)
	if id < 0 {
		mut p := m.prog
		p.problems << 'machine `${m.name}`: in_state(`${name}`): there is no such state (declare the states before you ask about them); the states are: ${m.names.join(', ')}'
		return invalid('no state ${name}')
	}
	return m.states.at(index).eq(id)
}

// me is the index of the record whose state this body is running for, a
// `u16` expression; only inside a state or an on_enter.
pub fn (mut c Code) me() Expr {
	if c.machine < 0 {
		c.problem('me() outside the body of a state')
		return invalid('me() outside a state')
	}
	return c.self
}

// time_in_state is how many frames the record has been in the state, a
// `u16` expression: 0 in the first frame; only inside a state or an on_enter.
pub fn (mut c Code) time_in_state() Expr {
	if c.machine < 0 {
		c.problem('time_in_state() outside the body of a state')
		return invalid('time_in_state() outside a state')
	}
	m := c.prog.machines[c.machine]
	return m.time.at(c.self)
}

// to leaves for another state of the machine: the state and the time are set
// at once, the state's on_enter runs, and the body of the new state runs
// from the next frame. The statements after it in the body still run, so
// follow it with `ret_void()` to stop.
pub fn (mut c Code) to(state string) {
	if c.machine < 0 {
		c.problem('to(`${state}`) outside the body of a state')
		return
	}
	mut m := c.prog.machines[c.machine]
	f := m.enter_func(state)
	c.call(f, c.self)
}

// finish_machines writes the functions of every machine, once all states are
// known, and reports a machine without states, a transition to a state that
// does not exist and an on_enter without a state.
fn (mut p Program) finish_machines() {
	for mut m in p.machines {
		m.finish()
	}
}

fn (mut m Machine) finish() {
	if m.done {
		return
	}
	m.done = true
	mut p := m.prog
	if m.names.len == 0 {
		p.problems << 'machine `${m.name}` has no states'
	}
	for name in m.entries.keys() {
		if m.state_id(name) < 0 {
			p.problems << 'machine `${m.name}`: on_enter(`${name}`) belongs to a state that does not exist; the states are: ${m.names.join(', ')}'
		}
	}
	for name in m.asked {
		f := m.enters[name]
		mut c := p.define(f)
		self := f.arg('self')
		id := m.state_id(name)
		if id < 0 {
			p.problems << 'machine `${m.name}`: a transition to the state `${name}`, which does not exist; the states are: ${m.names.join(', ')}'
			continue
		}
		c.set(m.states.at(self), id)
		c.set(m.time.at(self), 0)
		c.set(m.fresh.at(self), 1)
		if name in m.entries {
			c.call(m.entries[name], self)
		}
	}
	mut c := p.define(m.dispatch)
	self := m.dispatch.arg('self')
	for id, f in m.funcs {
		if id == 0 {
			c.if_(m.states.at(self).eq(id))
		} else {
			c.else_if(m.states.at(self).eq(id))
		}
		c.call(f, self)
	}
	if m.funcs.len > 0 {
		c.end() // which state
	}

	// A frame has passed in the state, unless it was entered during this one:
	// the body of the first frame sees time 0.
	c.if_(m.fresh.at(self).ne(0))
	c.set(m.fresh.at(self), 0)
	c.else_if(m.time.at(self).lt(65535))
	c.inc(m.time.at(self))
	c.end() // fresh
}
