module main

import jaggame

// The table of missions and the maps are data; these tests read them as the
// build does and check what no robot should have to find out: the maps are
// the size the game is laid out for, everything on them can be reached, and
// each mission is what its kind says.

fn rows_of(room RoomDef) []string {
	return room.map.trim('\n').split('\n')
}

// reach is every tile the figure can walk to from a tile of a map.
fn reach(rows []string, from jaggame.Point) map[int]bool {
	mut seen := map[int]bool{}
	mut queue := [from]
	seen[from.y * room_cols + from.x] = true
	mut head := 0
	for head < queue.len {
		here := queue[head]
		head++
		for step in [jaggame.Point{1, 0}, jaggame.Point{-1, 0},
			jaggame.Point{0, 1}, jaggame.Point{0, -1}] {
			next := jaggame.Point{here.x + step.x, here.y + step.y}
			if next.x < 0 || next.y < 0 || next.x >= room_cols || next.y >= room_rows {
				continue
			}
			if !passable(rows[next.y][next.x]) || seen[next.y * room_cols + next.x] {
				continue
			}
			seen[next.y * room_cols + next.x] = true
			queue << next
		}
	}
	return seen
}

fn chars_of(room RoomDef, ch u8) []jaggame.Point {
	mut found := []jaggame.Point{}
	for y, row in rows_of(room) {
		for x, c in row {
			if c == ch {
				found << jaggame.Point{x, y}
			}
		}
	}
	return found
}

fn count_chips(def MissionDef) int {
	mut n := 0
	for room in def.rooms {
		n += chars_of(room, `$`).len
	}
	return n
}

fn test_there_are_ten_missions_two_or_more_of_each_of_four_kinds() {
	defs := missions()
	assert defs.len == mission_count
	mut kinds := map[string]int{}
	mut titles := map[string]bool{}
	for def in defs {
		kinds[def.kind.label()]++
		assert def.title.len >= 3 && def.title.len <= 8, def.title
		assert !titles[def.title], 'a title is used once: ${def.title}'
		titles[def.title] = true
		assert def.ranks[0] < def.ranks[1] && def.ranks[1] < def.ranks[2], '${def.title}: S is the lowest score, then A, then B'
	}
	for label in ['SNEAK', 'COLLECT', 'TIMED', 'ROOMS'] {
		assert kinds[label] >= 2, '${label}: ${kinds[label]}'
	}
	println('missions by kind: ${kinds}')
}

fn test_every_map_is_the_size_the_game_is_laid_out_for() {
	for def in missions() {
		for k, room in def.rooms {
			rows := rows_of(room)
			assert rows.len == room_rows, '${def.title} room ${k}: ${rows.len} rows'
			for row in rows {
				assert row.len == room_cols, '${def.title} room ${k}: a row of ${row.len}'
			}
			assert room.guards.len <= max_guards && room.cameras.len <= max_cams
		}
	}
	assert room_cells == room_cols * room_rows
	assert keys_per_room == room_cells * 4 + max_cams * cam_steps
	assert flag_door == jaggame.flag_user1
}

fn test_everything_on_a_map_can_be_reached_from_where_the_figure_comes_in() {
	for def in missions() {
		for k, room in def.rooms {
			starts := if k == 0 { chars_of(room, `@`) } else { chars_of(room, `[`) }
			assert starts.len == 1, '${def.title} room ${k}: one way in'
			seen := reach(rows_of(room), starts[0])
			mut wanted := []jaggame.Point{}
			for ch in [u8(`$`), `X`, `D`, `U`, `]`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`] {
				wanted << chars_of(room, ch)
			}
			for p in wanted {
				assert seen[p.y * room_cols + p.x], '${def.title} room ${k}: ${rows_of(room)[p.y][p.x].ascii_str()} at ${p.x},${p.y} cannot be reached'
			}
			// the markers of a room exist for what the table says
			for g in room.guards {
				for ch in g.route {
					assert chars_of(room, ch).len == 1, '${def.title} room ${k}: waypoint ${rune(ch)}'
				}
			}
			for c in 0 .. room.cameras.len {
				assert chars_of(room, u8(`A` + c)).len == 1, '${def.title} room ${k}: camera ${c}'
			}
		}
	}
}

fn test_a_mission_is_what_its_rooms_hold() {
	for def in missions() {
		last := def.rooms.len - 1
		for k, room in def.rooms {
			assert chars_of(room, `X`).len == if k == last {
				1
			} else {
				0
			}, '${def.title} room ${k}: the exit is in the last room'
			assert chars_of(room, `D`).len == if k == last {
				0
			} else {
				1
			}, '${def.title} room ${k}: a door onward'
			assert chars_of(room, `U`).len == if k == 0 {
				0
			} else {
				1
			}, '${def.title} room ${k}: a door back'
		}
		match def.kind {
			.sneak {
				assert count_chips(def) == 0 && def.limit == 0 && def.rooms.len == 1, def.title
			}
			.collect {
				assert count_chips(def) >= 3 && def.rooms.len == 1, def.title
			}
			.timed {
				assert def.limit >= 30 && count_chips(def) == 0 && def.rooms.len == 1, def.title
			}
			.rooms {
				assert def.rooms.len >= 2 && count_chips(def) == 0, def.title
			}
		}
	}
	mut with_cameras := 0
	for def in missions() {
		for room in def.rooms {
			with_cameras += if room.cameras.len > 0 { 1 } else { 0 }
		}
	}
	assert with_cameras >= 4, 'cameras are in ${with_cameras} rooms'
}

fn test_the_game_builds_and_the_cone_tables_fit_the_image() {
	img := build()!
	assert img.symbols['rt.start'] == jaggame.load_address
	println('image: ${img.bytes.len} bytes')
	assert img.bytes.len < 0x7c000, 'the image stays below the display lists'
	rom := img.cartridge()!
	assert rom.len >= img.bytes.len + 0x2000
}
