module jaggame

// Tile sets and maps. A tile set is a PNG of 16x16 tiles; a room is a text
// of rows with one character for each tile; the legend says what each
// character means: a tile number and its flags, or a marker, a named place
// the game can ask for.
//
//	game.tileset('art/tiles.png')
//	game.legend_tile(`.`, 0, 0)
//	game.legend_tile(`#`, 1, jaggame.flag_solid)
//	game.legend_marker(`@`, 'start', 0, 0) // the player starts here; tile 0 is drawn under it
//	game.room('lab', '
//	#####
//	#@..#
//	#####
//	')
//
// Rooms are read when the game is built, so the legend may come after them,
// and every mistake in every room is reported together.

// The flags of a tile. A tile has the flags the legend gives it; the game
// reads them with `flags_at`. The last four are free for the game.
pub const flag_solid = 1 // blocks movement (`move_and_slide`, `solid_at`)
pub const flag_cover = 2 // a place to hide behind
pub const flag_exit = 4 // leads out of the room
pub const flag_item = 8 // something to pick up
pub const flag_user1 = 16
pub const flag_user2 = 32
pub const flag_user3 = 64
pub const flag_user4 = 128

// tile_size is the width and the height of a tile in pixels.
pub const tile_size = 16

// max_room_tiles is the most tiles a room may have in all (64 by 64), which
// is also the size of the picture buffer in units of tiles.
const max_room_tiles = 4096

// tile_none is what `tile_at` returns outside the room; it is solid.
pub const tile_none = 255

struct LegendTile {
	ch    rune
	tile  int
	flags int
}

struct LegendMarker {
	ch    rune
	name  string
	tile  int
	flags int
}

// Point is a position in a room, in tiles.
pub struct Point {
pub:
	x int
	y int
}

// Room is a handle on a room: `index` is the number to give `load_room`.
pub struct Room {
pub:
	index int
	name  string
}

struct RoomInfo {
	name string
	text string
mut:
	width   int
	height  int
	tiles   []u8
	markers map[string][]Point
}

// tileset reads the PNG as the game's tile set: tiles of 16x16 pixels, cut
// across and then down and numbered from 0. A game has one tile set, which
// shares the game's palette with the other 8-bit art. At most 255 tiles
// (255 is `tile_none`).
pub fn (mut g Game) tileset(path string) Tileset {
	if g.has_tileset {
		g.problem('tileset: the game already has a tile set; it has one')
		return Tileset{}
	}
	g.has_tileset = true
	g.use_map()
	g.tileset_path = path
	art := g.png_pal('tileset', path, tile_size, tile_size)
	if art.id < 0 {
		return Tileset{}
	}
	g.tileset_art = art.id
	g.tile_count = g.arts[art.id].frames
	return Tileset{
		count: g.tile_count
	}
}

// Tileset is a handle on the tile set.
pub struct Tileset {
pub:
	count int // the number of tiles
}

// legend_tile says that the character `ch` in a room is tile `tile` of the
// tile set, with `flags` (the `flag_` constants, added together). A tile's
// flags are a property of the tile: two characters that show one tile must
// give it the same flags.
pub fn (mut g Game) legend_tile(ch rune, tile int, flags int) {
	for l in g.legend_tiles {
		if l.ch == ch {
			g.problem('legend: the character `${ch}` is given twice')
			return
		}
	}
	for l in g.legend_markers {
		if l.ch == ch {
			g.problem('legend: the character `${ch}` is both a tile and the marker `${l.name}`')
			return
		}
	}
	if tile < 0 || tile > 254 {
		g.problem('legend: the character `${ch}` is tile ${tile}; tiles are 0..254')
	}
	if flags < 0 || flags > 255 {
		g.problem('legend: the character `${ch}` has flags ${flags}; flags are 0..255')
	}
	g.legend_tiles << LegendTile{ch, tile, flags}
}

// legend_marker says that the character `ch` in a room is a place called
// `name`: the game asks for its position (`marker_x`, `marker_y`) and the
// picture shows tile `tile` there, with `flags` as for `legend_tile`. Several
// characters may share a name; the places of a name are numbered in reading
// order, rows from the top.
pub fn (mut g Game) legend_marker(ch rune, name string, tile int, flags int) {
	for l in g.legend_tiles {
		if l.ch == ch {
			g.problem('legend: the character `${ch}` is both a tile and the marker `${name}`')
			return
		}
	}
	for l in g.legend_markers {
		if l.ch == ch {
			g.problem('legend: the character `${ch}` is given twice')
			return
		}
	}
	if !valid_name(name) {
		g.problem('legend: `${name}` is not a valid marker name')
	}
	if tile < 0 || tile > 254 {
		g.problem('legend: the marker `${name}` is drawn as tile ${tile}; tiles are 0..254')
	}
	g.legend_markers << LegendMarker{ch, name, tile, flags}
}

// room declares a room from a text of rows, one character a tile (a
// leading and a trailing line break are ignored). Rooms are numbered from 0
// in the order they are declared. Rows must be of equal length, the room
// from 1x1 to 64x64 tiles and 4096 tiles at most.
pub fn (mut g Game) room(name string, text string) Room {
	for r in g.rooms {
		if r.name == name {
			g.problem('room `${name}`: the name is already used')
		}
	}
	g.rooms << RoomInfo{
		name: name
		text: text
	}
	return Room{
		index: g.rooms.len - 1
		name:  name
	}
}

// marker_names are the names of the markers in the legend, once each, in
// the order they were declared.
fn (g &Game) marker_names() []string {
	mut names := []string{}
	for l in g.legend_markers {
		if l.name !in names {
			names << l.name
		}
	}
	return names
}

// room_rows are the rows of a room's text.
fn room_rows(text string) []string {
	mut rows := text.replace('\r', '').split('\n')
	if rows.len > 0 && rows[0].trim_space() == '' {
		rows = rows[1..].clone()
	}
	if rows.len > 0 && rows[rows.len - 1].trim_space() == '' {
		rows = rows[..rows.len - 1].clone()
	}
	return rows
}

// parse_rooms turns the text of every room into tiles and markers and
// records every mistake. It does so once.
fn (mut g Game) parse_rooms() {
	if g.rooms_parsed {
		return
	}
	g.rooms_parsed = true
	for i in 0 .. g.rooms.len {
		g.parse_room(i)
	}
	g.check_legend()
}

fn (mut g Game) parse_room(index int) {
	name := g.rooms[index].name
	rows := room_rows(g.rooms[index].text)
	if rows.len == 0 {
		g.problem('room `${name}`: it has no rows')
		return
	}
	width := rows[0].runes().len
	if width < 1 || width > 64 || rows.len > 64 || width * rows.len > max_room_tiles {
		g.problem('room `${name}`: ${width}x${rows.len} tiles; a room is 1..64 wide and high, with at most ${max_room_tiles} tiles')
		return
	}
	mut tiles := []u8{cap: width * rows.len}
	mut markers := map[string][]Point{}
	mut unknown := map[rune]string{}
	mut ragged := false
	for y, row in rows {
		runes := row.runes()
		if runes.len != width {
			g.problem('room `${name}`: row ${y + 1} has ${runes.len} characters, row 1 has ${width}')
			ragged = true
			continue
		}
		for x, ch in runes {
			if found := g.legend_tile_of(ch) {
				tiles << u8(found.tile)
			} else if m := g.legend_marker_of(ch) {
				tiles << u8(m.tile)
				markers[m.name] << Point{x, y}
			} else {
				tiles << 0
				if ch !in unknown {
					unknown[ch] = 'row ${y + 1}, column ${x + 1}'
				}
			}
		}
	}
	for ch, where in unknown {
		g.problem('room `${name}`: `${ch}` at ${where} is not in the legend')
	}
	if ragged {
		return
	}
	g.rooms[index].width = width
	g.rooms[index].height = rows.len
	g.rooms[index].tiles = tiles
	g.rooms[index].markers = markers.clone()
}

fn (g &Game) legend_tile_of(ch rune) ?LegendTile {
	for l in g.legend_tiles {
		if l.ch == ch {
			return l
		}
	}
	return none
}

fn (g &Game) legend_marker_of(ch rune) ?LegendMarker {
	for l in g.legend_markers {
		if l.ch == ch {
			return l
		}
	}
	return none
}

// check_legend makes sure the tiles the legend names exist, and that a
// tile has one set of flags.
fn (mut g Game) check_legend() {
	if (g.legend_tiles.len > 0 || g.legend_markers.len > 0 || g.rooms.len > 0) && !g.has_tileset {
		g.problem('the game has rooms or a legend but no tile set; call tileset() with the PNG of tiles')
		return
	}
	mut flags := map[int]string{}
	mut owner := map[int]rune{}
	for l in g.legend_tiles {
		if g.tile_count > 0 && l.tile >= g.tile_count {
			g.problem('legend: the character `${l.ch}` is tile ${l.tile}, but the tile set ${g.tileset_path} has ${g.tile_count} tiles')
		}
		if l.tile in owner && flags[l.tile] != l.flags.str() {
			g.problem('legend: tile ${l.tile} has flags ${flags[l.tile]} as `${owner[l.tile]}` and ${l.flags} as `${l.ch}`; the flags belong to the tile')
		}
		if l.tile !in owner {
			owner[l.tile] = l.ch
			flags[l.tile] = l.flags.str()
		}
	}
	for l in g.legend_markers {
		if g.tile_count > 0 && l.tile >= g.tile_count {
			g.problem('legend: the marker `${l.name}` is drawn as tile ${l.tile}, but the tile set ${g.tileset_path} has ${g.tile_count} tiles')
		}
		if l.tile in owner && flags[l.tile] != l.flags.str() {
			g.problem('legend: tile ${l.tile} has flags ${flags[l.tile]} as `${owner[l.tile]}` and ${l.flags} as the marker `${l.name}`; the flags belong to the tile')
		}
		if l.tile !in owner {
			owner[l.tile] = l.ch
			flags[l.tile] = l.flags.str()
		}
	}
}

// flag_table is the flags of every tile number, as the runtime stores them.
// Entry 255 (outside the room) is solid.
fn (g &Game) flag_table() []int {
	mut table := []int{len: 256}
	for l in g.legend_tiles {
		if l.tile >= 0 && l.tile < 255 {
			table[l.tile] = l.flags
		}
	}
	for l in g.legend_markers {
		if l.tile >= 0 && l.tile < 255 {
			table[l.tile] = l.flags
		}
	}
	table[tile_none] = flag_solid
	return table
}

// markers_of are the places of a marker name in a room, in tiles, in
// reading order. Rooms are read when the game is built, or by this call.
pub fn (mut g Game) markers_of(room Room, name string) []Point {
	g.parse_rooms()
	if room.index < 0 || room.index >= g.rooms.len {
		return []
	}
	return g.rooms[room.index].markers[name] or { []Point{} }
}

// room_size is the width and height of a room in tiles.
pub fn (mut g Game) room_size(room Room) (int, int) {
	g.parse_rooms()
	if room.index < 0 || room.index >= g.rooms.len {
		return 0, 0
	}
	return g.rooms[room.index].width, g.rooms[room.index].height
}
