module jaggame

// Scenes. A game is a handful of scenes (a title, a menu, the play, a result)
// and one of them runs at a time. A scene has an update that runs every frame
// while it is the current one, and optionally an `enter` (when it begins), a
// `leave` (when it ends) and a `setup` that is spread over several frames for
// work that is too much for one.
//
//	scenes := game.scenes()
//	mut c := scenes.scene('title')
//	c.if_(game.pressed(.a))
//	scenes.go(mut c, 'menu')
//	c.ret_void()
//	c.end()
//	scenes.start('title')
//
// Like state machines, scenes are not a new kind of statement: a scene is a
// state of a global state machine called `scene`, and the rest (`go`, the
// leave bodies, the steps of a setup) is written out as ordinary functions
// and variables of the program, so that the interpreter and the compiled
// code cannot disagree about it. The runtime calls the update of the current
// scene once a frame, after the game's own `update`.

// Scenes is the handle on the game's scenes, made by `Game.scenes`.
@[heap]
pub struct Scenes {
pub:
	step    Expr // u8: while a setup runs, the step it is on, counting from 0
	stalled Expr // u8: set by `wait`
	steps   Expr // u8: how many steps the current scene's setup has; 0 when it has none
	live    Expr // bool: some scene has been entered
mut:
	game     &Game
	machine  &Machine
	names    []string
	declared map[string]bool
	leaves   map[string]Func
	setups   map[string]Func
	counts   map[string]int
	asked    []string
	gos      map[string]Func
	first    string
	tick     Func
	done     bool
}

// scenes starts the game's scenes, or returns them if they were started.
pub fn (mut g Game) scenes() &Scenes {
	if g.scene_set {
		return g.scene_ref
	}
	g.scene_set = true
	mut p := g.p
	g.scene_ref = &Scenes{
		step:    p.u8('scenes_step')
		stalled: p.u8('scenes_stalled')
		steps:   p.u8('scenes_steps')
		live:    p.bool('scenes_live')
		game:    unsafe { g }
		machine: p.machine_global('scene')
		tick:    p.func('scenes_tick', [], .void)
	}
	return g.scene_ref
}

fn (mut s Scenes) problem(message string) {
	s.game.p.problems << 'scenes: ${message}'
}

// scene declares a scene and returns the block to write its update in: it
// runs once a frame while the scene is the current one. Inside it,
// `time_in_state()` is the frames the scene has been going.
pub fn (mut s Scenes) scene(name string) &Code {
	if s.declared[name] {
		s.problem('the scene `${name}` is defined twice')
		return s.detached('${name}_again_${s.names.len}')
	}
	s.declared[name] = true
	s.names << name
	return s.machine.state(name)
}

// detached is a block that belongs to nothing, for the body of a mistake:
// the mistake is reported and the author's calls on the block still work.
fn (mut s Scenes) detached(name string) &Code {
	mut p := s.game.p
	return p.define(p.func('scenes_detached_${name}', [], .void))
}

// on_enter declares the block that runs when the scene begins, before its
// first frame (and before its setup, if it has one).
pub fn (mut s Scenes) on_enter(name string) &Code {
	return s.machine.on_enter(name)
}

// on_leave declares the block that runs when the scene ends, before the next
// scene's `on_enter`.
pub fn (mut s Scenes) on_leave(name string) &Code {
	if name in s.leaves {
		s.problem('on_leave(`${name}`) is defined twice')
		return s.detached('${name}_leave_again')
	}
	mut p := s.game.p
	f := p.func('sceneleave_${name}', [], .void)
	s.leaves[name] = f
	return p.define(f)
}

// setup declares a scene's setup: a block that runs once a frame for `steps`
// frames after the scene begins, with `step` (0, 1, ...) saying which. The
// scene's update starts when the last step is done. A step that has to wait
// for something calls `wait`, which makes the same step run again next
// frame.
pub fn (mut s Scenes) setup(name string, steps int) &Code {
	if steps < 1 || steps > 255 {
		s.problem('the setup of `${name}` has ${steps} steps; it must have 1..255')
	}
	if name in s.setups {
		s.problem('the setup of `${name}` is defined twice')
		return s.detached('${name}_setup_again')
	}
	mut p := s.game.p
	f := p.func('scenesetup_${name}', [], .void)
	s.setups[name] = f
	s.counts[name] = if steps < 1 { 1 } else { steps }
	return p.define(f)
}

// start says which scene the game begins in, after its `init` has run.
pub fn (mut s Scenes) start(name string) {
	if s.first != '' {
		s.problem('start(`${name}`): the start scene is already `${s.first}`')
		return
	}
	s.first = name
}

// go leaves the current scene for another one: its `on_leave` runs, then
// `on_enter` of the new one, at once; the new scene's update (or its setup)
// begins next frame. The statements after it in the block still run, so
// follow it with `ret_void()` to stop.
pub fn (mut s Scenes) go(mut c Code, name string) {
	c.call(s.go_func(name))
}

// wait makes the setup step that is running run again next frame instead of
// moving on.
pub fn (s &Scenes) wait(mut c Code) {
	c.set(s.stalled, 1)
}

// current is the number of the current scene, in the order they were
// declared (a `u8` expression).
pub fn (s &Scenes) current() Expr {
	return s.machine.state_of(0)
}

// time is the frames the current scene has been going, counting from 0 in
// its first frame (a `u16` expression); it does not count while a setup runs.
pub fn (s &Scenes) time() Expr {
	return s.machine.time_of(0)
}

// in_scene is true while the named scene is the current one. Declare the
// scene first.
pub fn (mut s Scenes) in_scene(name string) Expr {
	return s.machine.in_state(0, name)
}

// settled is true when no setup is running: the update of the current scene
// is the thing that runs.
pub fn (s &Scenes) settled() Expr {
	return s.step.ge(s.steps)
}

// go_func is the function of a transition to a scene, made when something
// first asks for it; whether the scene exists is checked when the game is
// built.
fn (mut s Scenes) go_func(name string) Func {
	if name in s.gos {
		return s.gos[name]
	}
	f := s.game.p.func('scenego_${name}', [], .void)
	s.gos[name] = f
	s.asked << name
	return f
}

// finish writes the transition functions and the one that runs a frame, once
// every scene is declared, and reports the mistakes of the description: no
// scene, no start scene, a start or a transition to a scene that does not
// exist.
fn (mut s Scenes) finish() {
	if s.done {
		return
	}
	s.done = true
	if s.names.len == 0 {
		s.problem('there are no scenes; declare one with scene(name)')
	}
	if s.first == '' {
		s.problem('there is no start scene; call start(name)')
	} else if !s.declared[s.first] {
		s.problem('the start scene `${s.first}` does not exist; the scenes are: ${s.names.join(', ')}')
	}
	for name in s.leaves.keys() {
		if !s.declared[name] {
			s.problem('on_leave(`${name}`) belongs to a scene that does not exist; the scenes are: ${s.names.join(', ')}')
		}
	}
	for name in s.setups.keys() {
		if !s.declared[name] {
			s.problem('the setup of `${name}` belongs to a scene that does not exist; the scenes are: ${s.names.join(', ')}')
		}
	}
	if s.has_start() {
		s.go_func(s.first)
	}
	for name in s.asked {
		s.define_go(name)
	}
	s.define_tick()
}

// has_start is true when the start scene is named and exists.
fn (s &Scenes) has_start() bool {
	return s.first != '' && s.declared[s.first]
}

// define_go writes the transition to a scene: leave the current one, enter
// the new one, and start its setup.
fn (mut s Scenes) define_go(name string) {
	mut p := s.game.p
	mut c := p.define(s.gos[name])
	if !s.declared[name] {
		s.problem('a transition to the scene `${name}`, which does not exist; the scenes are: ${s.names.join(', ')}')
		return
	}
	c.if_(s.live)
	for i, other in s.names {
		if other in s.leaves {
			c.if_(s.current().eq(i))
			c.call(s.leaves[other])
			c.end() // this scene
		}
	}
	c.end() // there was a scene
	c.set(s.live, true)
	c.set(s.step, 0)
	c.set(s.stalled, 0)
	c.set(s.steps, s.counts[name] or { 0 })
	s.machine.start(mut c, 0, name)
}

// define_tick writes what the runtime does for the scenes in one frame: a
// step of the setup, or the update of the current scene.
fn (mut s Scenes) define_tick() {
	mut p := s.game.p
	mut c := p.define(s.tick)
	c.if_(s.settled())
	s.machine.run(mut c, 0)
	c.ret_void()
	c.end() // an ordinary frame
	mut first := true
	for i, name in s.names {
		if name !in s.setups {
			continue
		}
		if first {
			c.if_(s.current().eq(i))
		} else {
			c.else_if(s.current().eq(i))
		}
		first = false
		c.call(s.setups[name])
	}
	if !first {
		c.end() // which scene
	}

	c.if_(s.stalled.ne(0))
	c.set(s.stalled, 0)
	c.else_()
	c.inc(s.step)
	c.end() // the step is over, or must be done again
}
