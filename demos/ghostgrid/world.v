// The world: what the build works out from the table of missions so that the
// game itself only looks things up. Every room of every mission is in one
// list; for each there are the guards' routes (and a field of directions for
// each waypoint, so that a guard cannot be stuck on a corner), the cameras,
// and the tiles every cone lights, for every tile a guard can stand on and
// every way it can face and for every position of every camera's sweep.
module main

import jaggame

const cone_slots = 40 // cells a cone list holds
const sight_range = 64 // pixels a guard's cone reaches: four tiles
const sight_half = 24 // angle units either side of the facing: 34 degrees
const keys_per_room = 2288 // lists a room has: room_cells * 4 + max_cams * cam_steps (a plain number: see room_cells)

const marker_start = 'start'
const marker_from_prev = 'from_prev'
const marker_from_next = 'from_next'

// World is everything the tables of the game are made from.
struct World {
mut:
	defs   []MissionDef
	rooms  []RoomDef
	handle []jaggame.Room
	first  []int // the number of each mission's first room
	// guards
	rm_guards []int // for each room: how many guards
	g_first   []int // for each room and guard slot: its first waypoint
	g_count   []int
	g_face    []int
	wp_x      []int // the tile of every waypoint
	wp_y      []int
	fields    []int // a field of directions for every waypoint, one after the other
	// cameras
	rm_cams []int // for each room: how many cameras
	c_tx    []int // for each room and camera slot: its tile, its first angle and its steps
	c_ty    []int
	c_a0    []int
	c_n     []int
	// the cones
	view_at   []int // where each list starts in its room's part of the pool
	view_len  []int
	pool_cell []int // the cells of all the lists, as row * columns + column
	rm_pool   []int // where each room's part of the pool starts
}

// check stops the build with a message: an assert would only be checked in a
// test.
fn check(ok bool, what string) {
	if !ok {
		panic(what)
	}
}

// room_name is the name a room has in the game.
fn room_name(number int) string {
	return 'room${number}'
}

// new_world reads the table and declares the rooms; the markers and the
// routes are worked out by `routes` and `views`, once the legend is in.
fn new_world(mut game jaggame.Game) World {
	mut w := World{
		defs: missions()
	}
	check(keys_per_room == room_cells * 4 + max_cams * cam_steps,
		'keys_per_room == room_cells * 4 + max_cams * cam_steps')
	check(room_cells == room_cols * room_rows, 'room_cells == room_cols * room_rows')
	if !(w.defs.len == mission_count) {
		panic('the table has ${w.defs.len} missions, not ${mission_count}')
	}
	for def in w.defs {
		w.first << w.rooms.len
		if !(def.title.len <= 8) {
			panic('the title ${def.title} has more than 8 letters')
		}
		if !(def.ranks.len == 3) {
			panic('${def.title}: the ranks are the scores for S, A and B')
		}
		if !(def.rooms.len >= 1 && def.rooms.len <= 3) {
			panic('${def.title}: one to three rooms')
		}
		for room in def.rooms {
			w.handle << game.room(room_name(w.rooms.len), room.map)
			w.rooms << room
		}
	}
	return w
}

// rows is the lines of a room's map.
fn (w &World) rows(room int) []string {
	return w.rooms[room].map.trim('\n').split('\n')
}

// passable is whether a guard can walk on a character of a map.
fn passable(ch u8) bool {
	return ch != `#` && ch != `c` && ch != `A` && ch != `B` && ch != `C`
}

// flow_field is, for every tile of a room, the direction (0 right, 1 down, 2
// left, 3 up) of the first step of a shortest walk to the target tile; 255
// at the target itself and where there is no way. Found by a breadth-first
// search from the target.
fn flow_field(rows []string, target jaggame.Point) []int {
	mut dist := []int{len: room_cells, init: -1}
	mut field := []int{len: room_cells, init: 255}
	mut queue := [target]
	dist[target.y * room_cols + target.x] = 0
	mut head := 0
	steps := [jaggame.Point{1, 0}, jaggame.Point{0, 1}, jaggame.Point{-1, 0},
		jaggame.Point{0, -1}]
	for head < queue.len {
		here := queue[head]
		head++
		for d, step in steps {
			next := jaggame.Point{here.x + step.x, here.y + step.y}
			if next.x < 0 || next.y < 0 || next.x >= room_cols || next.y >= room_rows {
				continue
			}
			cell := next.y * room_cols + next.x
			if !passable(rows[next.y][next.x]) || dist[cell] >= 0 {
				continue
			}
			dist[cell] = dist[here.y * room_cols + here.x] + 1
			field[cell] = (d + 2) % 4 // from `next`, the way back to `here`
			queue << next
		}
	}
	return field
}

// waypoint_marker is the name of the marker of a route character.
fn waypoint_marker(ch u8) string {
	return 'w${rune(ch)}'
}

// marker finds the first place of a marker in a room.
fn (mut w World) marker(mut game jaggame.Game, room int, name string) ?jaggame.Point {
	found := game.markers_of(w.handle[room], name)
	if found.len == 0 {
		return none
	}
	return found[0]
}

// routes works out, for every room, the guards' waypoints, their fields of
// directions and the way each guard faces when it starts.
fn (mut w World) routes(mut game jaggame.Game) {
	for r, room in w.rooms {
		rows := w.rows(r)
		if !(rows.len == room_rows && rows.all(it.len == room_cols)) {
			panic('room ${r}: the map is not ${room_cols} by ${room_rows}')
		}
		if !(room.guards.len <= max_guards) {
			panic('room ${r}: ${room.guards.len} guards, at most ${max_guards}')
		}
		w.rm_guards << room.guards.len
		for g in 0 .. max_guards {
			if g >= room.guards.len {
				w.g_first << 0
				w.g_count << 0
				w.g_face << 0
				continue
			}
			def := room.guards[g]
			if !(def.route.len >= 1) {
				panic('room ${r}, guard ${g}: no waypoints')
			}
			w.g_first << w.wp_x.len
			w.g_count << def.route.len
			mut points := []jaggame.Point{}
			for ch in def.route {
				point := w.marker(mut game, r, waypoint_marker(ch)) or {
					panic('room ${r}, guard ${g}: the map has no waypoint ${rune(ch)}')
				}
				points << point
				w.wp_x << point.x
				w.wp_y << point.y
				w.fields << flow_field(rows, point)
			}
			// the first leg: the direction the field of the next waypoint gives
			mut face := def.face
			if points.len > 1 {
				field := flow_field(rows, points[1])
				way := field[points[0].y * room_cols + points[0].x]
				if way < 4 {
					face = way * 64
				}
			}
			w.g_face << face
		}
	}
	if !(w.wp_x.len * room_cells < 65536) {
		panic('too many waypoints for the fields: ${w.wp_x.len}')
	}
	check(w.wp_x.len < 256, 'w.wp_x.len < 256')
}

// cameras reads the cameras' markers and sweeps.
fn (mut w World) cameras(mut game jaggame.Game) {
	for r, room in w.rooms {
		if !(room.cameras.len <= max_cams) {
			panic('room ${r}: ${room.cameras.len} cameras, at most ${max_cams}')
		}
		w.rm_cams << room.cameras.len
		for k in 0 .. max_cams {
			if k >= room.cameras.len {
				w.c_tx << 0
				w.c_ty << 0
				w.c_a0 << 0
				w.c_n << 0
				continue
			}
			def := room.cameras[k]
			span := def.to - def.from
			if !(span >= 0 && span % cam_turn == 0 && def.from % cam_turn == 0) {
				panic('room ${r}, camera ${k}: the sweep ${def.from} to ${def.to} is not in steps of ${cam_turn}')
			}
			if !(span / cam_turn + 1 <= cam_steps) {
				panic('room ${r}, camera ${k}: more than ${cam_steps} positions')
			}
			at := w.marker(mut game, r, 'cam${k}') or {
				panic('room ${r}: the map has no camera ${rune(`A` + k)}')
			}
			w.c_tx << at.x
			w.c_ty << at.y
			w.c_a0 << def.from
			w.c_n << span / cam_turn + 1
		}
	}
}

// views works out the cones: for every room, the cells a guard sees from
// every tile it can stand on facing each of the four ways, and the cells a
// camera sees from each position of its sweep. The lists are one long pool;
// a table says where each starts and how long it is.
fn (mut w World) views(mut game jaggame.Game) {
	for r in 0 .. w.rooms.len {
		rows := w.rows(r)
		room := w.handle[r]
		w.rm_pool << w.pool_cell.len
		base := w.pool_cell.len
		for y in 0 .. room_rows {
			for x in 0 .. room_cols {
				for f in 0 .. 4 {
					w.view_at << w.pool_cell.len - base
					if passable(rows[y][x]) {
						for cell in game.view_cells(room, x, y, f * 64, sight_range, sight_half,
							false) {
							w.pool_cell << cell.y * room_cols + cell.x
						}
					}
					w.view_len << w.pool_cell.len - base - w.view_at.last()
					check(w.view_len.last() <= cone_slots, 'w.view_len.last() <= cone_slots')
				}
			}
		}
		for k in 0 .. max_cams {
			for s in 0 .. cam_steps {
				w.view_at << w.pool_cell.len - base
				if k < w.rm_cams[r] && s < w.c_n[r * max_cams + k] {
					angle := w.c_a0[r * max_cams + k] + s * cam_turn
					for cell in game.view_cells(room, w.c_tx[r * max_cams + k], w.c_ty[
						r * max_cams + k], angle, cam_range, cam_half, false) {
						w.pool_cell << cell.y * room_cols + cell.x
					}
				}
				w.view_len << w.pool_cell.len - base - w.view_at.last()
				check(w.view_len.last() <= cone_slots, 'w.view_len.last() <= cone_slots')
			}
		}
		check(w.pool_cell.len - base < 65536, 'w.pool_cell.len - base < 65536')
	}
}

// Layout is the shape of the table of missions for the tests' robot: the map
// of every room, the first room of each mission and how many rooms it has.
struct Layout {
mut:
	maps  []string
	first []int
	rooms []int
}

// layout reads it from the table. Only the tests call it.
@[markused]
fn layout() Layout {
	defs := missions()
	mut l := Layout{}
	for def in defs {
		l.first << l.maps.len
		l.rooms << def.rooms.len
		for room in def.rooms {
			l.maps << room.map
		}
	}
	return l
}
