module robot

import jaggame

// The robot plays a mission unseen. It does not look ahead by guessing: the
// guards and the cameras do the same whatever the figure does as long as they
// do not notice it, so the game is first run in the interpreter with the
// figure parked in a wall, and the cones of every frame are written down (the
// game's own `lit` words and where each guard is). Then a search over (tile,
// time) finds the walk that is never in a lit tile, waiting where it has to,
// and crouching where a cover block hides it from a guard. A camera is not
// fooled by cover, so a tile a camera's cone is on is never entered. The
// goals of a room are its chips, nearest first, and then its exit or its
// door; a room that follows is planned with the game run on through the
// earlier ones.

pub const tick = 4 // frames in a step of the plan
pub const horizon = 3600 // frames of the guards' doings that are written down

// Recording is what the guards did, frame by frame from the first.
pub struct Recording {
pub mut:
	frames int
	lit    []u16 // room_cells words after each frame
	guards []int // after each frame, for each guard: tile x, tile y, facing (0..3)
}

// record plays `frames` frames with nobody touching the pad and writes down
// the cones and the guards after each.
pub fn record(mut rig Rig, frames int) Recording {
	mut rec := Recording{
		frames: frames + 1
	}
	rec.snapshot(mut rig)
	for _ in 0 .. frames {
		rig.frame(0)
		rec.snapshot(mut rig)
	}
	return rec
}

fn (mut rec Recording) snapshot(mut rig Rig) {
	for v in rig.it.array('lit') or { panic(err) } {
		rec.lit << u16(v)
	}
	s := Sim(rig)
	for i in 0 .. 4 {
		t := gtile(s, i)
		rec.guards << t.x
		rec.guards << t.y
		rec.guards << s.field('guards', i, 'face') >> 6
	}
}

// Danger says, for every tick of a plan and every tile, whether standing there
// would be seen and whether crouching there would be.
pub struct Danger {
pub mut:
	standing  []bool
	crouching []bool
}

fn (s &Spec) view_grid(mut game jaggame.Game, room int, mut cache map[int][]bool, x int, y int, f int) []bool {
	key := (y * s.cols + x) * 4 + f
	if key in cache {
		return cache[key]
	}
	cells := s.cols * s.rows
	mut grid := []bool{len: cells}
	handle := jaggame.Room{
		index: room
		name:  'room${room}'
	}
	for p in game.view_cells(handle, x, y, f * 64, s.range, s.half, true) {
		grid[p.y * s.cols + p.x] = true
	}
	cache[key] = grid
	return grid
}

// danger works out what each tick of the plan has to avoid. A tick covers
// the frames around it, a little before and after, so that a plan that is a
// frame or two out is still safe.
pub fn (s &Spec) danger(rec &Recording, mut game jaggame.Game, room int) Danger {
	cells := s.cols * s.rows
	ticks := (rec.frames - 10) / tick
	mut d := Danger{
		standing:  []bool{len: ticks * cells}
		crouching: []bool{len: ticks * cells}
	}
	mut cache := map[int][]bool{}
	for f in 0 .. rec.frames {
		// which tiles are lit now, and which of them a crouching figure is seen on
		mut stand := []bool{len: cells}
		mut crouch := []bool{len: cells}
		for cell in 0 .. cells {
			bits := rec.lit[f * cells + cell]
			if bits & 0x7f == 0 {
				continue
			}
			stand[cell] = true
			if bits & 0x70 != 0 {
				crouch[cell] = true // a camera is not fooled by cover
			}
			for g in 0 .. 4 {
				if bits & (1 << u8(g)) != 0 {
					base := f * 12 + g * 3
					grid := s.view_grid(mut game, room, mut cache, rec.guards[base], rec.guards[
						base + 1], rec.guards[base + 2])
					if grid[cell] {
						crouch[cell] = true
					}
				}
			}
		}
		// frame f belongs to the ticks whose window it is in
		first := (f - 6 + tick - 1) / tick
		last := (f + 2) / tick
		for k in int_max(0, first) .. int_min(ticks, last + 1) {
			for cell in 0 .. cells {
				if stand[cell] {
					d.standing[k * cells + cell] = true
				}
				if crouch[cell] {
					d.crouching[k * cells + cell] = true
				}
			}
		}
	}
	return d
}

// Action is one step of a plan: what the figure does for `ticks` ticks.
pub struct Action {
pub:
	kind  int // 0 wait, 1 wait crouching, 2 walk, 3 crouch-walk
	cell  int // the tile it ends in
	ticks int
}

pub const wait = 0
pub const hide = 1
pub const walk = 2
pub const creep = 3

pub fn (a Action) name() string {
	return ['wait', 'hide', 'walk', 'creep'][a.kind]
}

// Options say what the plan may use.
pub struct Options {
pub:
	hide  bool = true // wait crouching, behind cover
	creep bool = true // walk crouching
}

// passable_cells is, for every tile of a room, whether the figure can stand on it.
fn (s &Spec) passable_cells(room int) []bool {
	map_rows := s.rows_of(room)
	mut passable := []bool{len: s.cols * s.rows}
	for y in 0 .. s.rows {
		for x in 0 .. s.cols {
			passable[y * s.cols + x] = !is_blocking(map_rows[y][x])
		}
	}
	return passable
}

// Leg is a plan from a tile and a tick to a goal tile: the actions and the
// tick it ends at.
pub struct Leg {
pub:
	actions []Action
	end     int
}

// make_plan finds the fastest way, by breadth first search over (tick, tile),
// from a tile at a tick to a goal tile, never in a tile a guard would see.
pub fn (s &Spec) make_plan(d &Danger, ticks int, room int, from int, from_tick int, goal int, opts Options) ?Leg {
	cells := s.cols * s.rows
	passable_cell := s.passable_cells(room)
	size := (ticks + 8) * cells
	mut parent := []int{len: size, init: -1}
	mut how := []u8{len: size}
	mut seen := []bool{len: size}
	mut buckets := [][]int{len: ticks + 8}
	start := from_tick * cells + from
	seen[start] = true
	buckets[from_tick] << start
	safe := fn [d, ticks, cells] (k int, cell int, crouching bool) bool {
		if k >= ticks {
			return false
		}
		return !(if crouching {
			d.crouching[k * cells + cell]
		} else {
			d.standing[k * cells + cell]
		})
	}
	for k in from_tick .. ticks {
		for state in buckets[k] {
			cell := state % cells
			if cell == goal {
				// walk back to find the way
				mut path := []Action{}
				mut at := state
				for parent[at] >= 0 {
					path << Action{int(how[at]), at % cells, at / cells - parent[at] / cells}
					at = parent[at]
				}
				path.reverse_in_place()
				return Leg{path, k}
			}
			mut moves := [[0, cell, 1, wait]]
			if opts.hide {
				moves << [1, cell, 1, hide]
			}
			for step in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
				x := cell % s.cols + step[0]
				y := cell / s.cols + step[1]
				if x < 0 || y < 0 || x >= s.cols || y >= s.rows || !passable_cell[y * s.cols + x] {
					continue
				}
				n := y * s.cols + x
				if safe(k + 1, n, false) && safe(k + 2, n, false) && safe(k + 3, n, false)
					&& safe(k + 1, cell, false) && safe(k + 2, cell, false)
					&& safe(k + 3, cell, false) {
					moves << [2, n, 3, walk]
				}
				if opts.creep {
					mut ok := true
					for j in 1 .. 7 {
						ok = ok && safe(k + j, n, true) && safe(k + j, cell, true)
					}
					if ok {
						moves << [2, n, 6, creep]
					}
				}
			}
			for mv in moves {
				n := mv[1]
				nk := k + (if mv[0] == 0 || mv[0] == 1 { 1 } else { mv[2] })
				if mv[0] == 0 && !safe(nk, n, false) {
					continue
				}
				if mv[0] == 1 && !safe(nk, n, true) {
					continue
				}
				target := nk * cells + n
				if seen[target] {
					continue
				}
				seen[target] = true
				parent[target] = state
				how[target] = u8(mv[3])
				buckets[nk] << target
			}
		}
	}
	return none
}

// steer is the pad that takes the figure towards the middle of a tile: the
// figure's position is its top left corner, (16 tx, 16 ty - 1) when its box
// is in the middle of the tile.
pub fn (s &Spec) steer(sim Sim, cell int, tolerance f64) u32 {
	want_x := f64((cell % s.cols) * 16)
	want_y := f64((cell / s.cols) * 16 - 1)
	px := fixed_of(sim.value('px'))
	py := fixed_of(sim.value('py'))
	mut mask := u32(0)
	if want_x - px > tolerance {
		mask |= pad(.right)
	} else if px - want_x > tolerance {
		mask |= pad(.left)
	}
	if want_y - py > tolerance {
		mask |= pad(.down)
	} else if py - want_y > tolerance {
		mask |= pad(.up)
	}
	return mask
}

// execute plays a plan frame by frame, and stops when the mission or the
// room is over (the scene changes, or a fade begins).
pub fn (s &Spec) execute(mut sim Sim, actions []Action, each fn (mut s Sim)) {
	for a in actions {
		for _ in 0 .. a.ticks * tick {
			mut mask := u32(0)
			match a.kind {
				hide {
					mask = pad(.b)
				}
				walk {
					mask = s.steer(sim, a.cell, 1.6)
				}
				creep {
					mask = s.steer(sim, a.cell, 0.8) | pad(.b)
				}
				else {}
			}

			sim.frame(mask)
			each(mut sim)
			if scene_of(sim) != scene_play || sim.value('scenes_fading') != 0 {
				return
			}
		}
	}
}

pub fn nothing(mut s Sim) {
}

// cell_of is the number of a tile.
pub fn (s &Spec) cell_of(p jaggame.Point) int {
	return p.y * s.cols + p.x
}

// goals_of lists the tiles a room's plan visits, in order: the chips, the
// nearest to the last place first, then the exit, or the door onward.
pub fn (s &Spec) goals_of(room int, from jaggame.Point, last bool) []int {
	mut chips := s.find(room, `$`)
	mut goals := []int{}
	mut at := from
	for chips.len > 0 {
		mut best := 0
		for k, c in chips {
			if int_abs(c.x - at.x) + int_abs(c.y - at.y) < int_abs(chips[best].x - at.x) +
				int_abs(chips[best].y - at.y) {
				best = k
			}
		}
		goals << s.cell_of(chips[best])
		at = chips[best]
		chips.delete(best)
	}
	exit := if last { s.find(room, `X`) } else { s.find(room, `D`) }
	goals << s.cell_of(exit[0])
	return goals
}

fn int_abs(a int) int {
	return if a < 0 { -a } else { a }
}

// Plan is what the robot works out for a mission: the actions in each room.
pub struct Plan {
pub mut:
	rooms [][]Action
}

// start_of is the tile the figure is on when it comes into a room of a
// mission: the start in the first, beside the door in the others.
pub fn (s &Spec) start_of(mission int, k int) jaggame.Point {
	room := s.first[mission] + k
	found := if k == 0 { s.find(room, `@`) } else { s.find(room, `[`) }
	return found[0]
}

// plan_room plans one room of a mission, with the game played in the
// interpreter through the rooms before it.
pub fn (s &Spec) plan_room(mission int, k int, before Plan, opts Options) ?[]Action {
	room := s.first[mission] + k
	mut rig := s.rig(false)
	mut sim := Sim(rig)
	enter_mission(mut sim, mission)
	for j in 0 .. k {
		s.execute(mut sim, before.rooms[j], nothing)
		ready(mut sim)
	}
	sim.poke('px', 0)
	sim.poke('py', 0)
	rec := record(mut rig, horizon)
	d := s.danger(&rec, mut rig.g, room)
	ticks := (rec.frames - 10) / tick
	mut at := s.start_of(mission, k)
	mut now := 0
	mut actions := []Action{}
	for goal in s.goals_of(room, at, k == s.rooms[mission] - 1) {
		leg := s.make_plan(&d, ticks, room, s.cell_of(at), now, goal, opts)?
		actions << leg.actions
		now = leg.end
		at = jaggame.Point{goal % s.cols, goal / s.cols}
	}
	return actions
}

// plan_mission plans every room of a mission.
pub fn (s &Spec) plan_mission(mission int, opts Options) ?Plan {
	mut plan := Plan{}
	for k in 0 .. s.rooms[mission] {
		plan.rooms << s.plan_room(mission, k, plan, opts)?
	}
	return plan
}

// describe_plan is a plan as text.
pub fn (s &Spec) describe_plan(actions []Action) string {
	mut parts := []string{}
	for a in actions {
		parts << '${a.name()} ${a.cell % s.cols},${a.cell / s.cols} x${a.ticks}'
	}
	return parts.join(', ')
}

// kinds counts the ticks of each kind of action in a plan.
pub fn kinds(actions []Action) map[string]int {
	mut count := map[string]int{}
	for a in actions {
		count[a.name()] += a.ticks
	}
	return count
}

// Result is how a mission ended.
pub struct Result {
pub:
	phase  int // 1 done, 2 caught, 3 out of time
	secs   int
	seen   int
	alerts int
	score  int
	rank   int
	frames int // frames from the first of the mission to the end
}

// play plays a plan from the title to the result screen, with `each` called
// after every frame of the mission.
pub fn (s &Spec) play(mut sim Sim, mission int, plan Plan, each fn (mut s Sim)) Result {
	enter_mission(mut sim, mission)
	start := sim.value('frame')
	for k, actions in plan.rooms {
		s.execute(mut sim, actions, each)
		if k < plan.rooms.len - 1 {
			ready(mut sim)
		}
	}
	frames := sim.value('frame') - start
	// the result is written a few lines a frame
	run_frames(mut sim, 16, 0)
	return Result{
		phase:  sim.value('phase')
		secs:   sim.value('secs')
		seen:   sim.value('seen')
		alerts: sim.value('alerts')
		score:  sim.value('score')
		rank:   sim.value('rank')
		frames: frames
	}
}

// play_here is `play` for a game that is already in the first frame of a
// mission (the one a result screen's NEXT MISSION has started).
pub fn (s &Spec) play_here(mut sim Sim, plan Plan, each fn (mut s Sim)) Result {
	start := sim.value('frame')
	for k, actions in plan.rooms {
		s.execute(mut sim, actions, each)
		if k < plan.rooms.len - 1 {
			ready(mut sim)
		}
	}
	frames := sim.value('frame') - start
	run_frames(mut sim, 16, 0)
	return Result{
		phase:  sim.value('phase')
		secs:   sim.value('secs')
		seen:   sim.value('seen')
		alerts: sim.value('alerts')
		score:  sim.value('score')
		rank:   sim.value('rank')
		frames: frames
	}
}

// next_mission chooses NEXT MISSION on the result screen and waits for the
// next mission to be up.
pub fn next_mission(mut sim Sim) {
	tap(mut sim, .down)
	sim.frame(pad(.a))
	ready(mut sim)
}

// pad_script writes a pad log as runs of held buttons, `up@120+36 a@130+5`
// (a button, the frame it goes down at and for how many frames), the form
// `vjag_test run --press` and the second emulator's `--holds-file` read.
pub fn pad_script(log []u32) string {
	mut parts := []string{}
	for i, button in robot_masks {
		name := robot_buttons[i].str()
		mut start := -1
		for n, mask in log {
			held := mask & jaggame.button_mask(button) != 0
			if held && start < 0 {
				start = n
			}
			if !held && start >= 0 {
				parts << '${name}@${start}+${n - start}'
				start = -1
			}
		}
		if start >= 0 {
			parts << '${name}@${start}+${log.len - start}'
		}
	}
	return parts.join(' ')
}
