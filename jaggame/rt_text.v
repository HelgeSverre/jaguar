module jaggame

import jagkit

// Text. A text layer is a grid of 8x8 character cells drawn over the
// sprites. Its cells are an array of the program (`<name>_cells`, one byte
// a cell: 0 is a blank, 1 is `!`, and so on in the order of ASCII from 32
// to 95), so printing is ordinary code that the interpreter runs too; the
// runtime draws the rows that changed once a frame.
//
// A layer has a colour, the variable `<name>_colour` (CRY, see `cry`).
// The font has capitals, digits and punctuation only.

struct TextInfo {
	name    string
	columns int
	rows    int
	x       int
	y       int
	colour  Expr
	cells   Expr
	dirty   Expr
mut:
	print_func  Func
	number_func Func
	clear_func  Func
	uses_print  bool
	uses_number bool
	uses_clear  bool
	colour_init u16
}

// TextConfig places a text layer.
pub struct TextConfig {
pub:
	columns int = 40 // a multiple of 8, so that a line fills whole phrases
	rows    int = 1
	x       int // the left edge in logical pixels
	y       int // the top edge in logical pixels
	colour  u16 // CRY; the layer's `colour` variable starts with it; 0 is white
}

// TextLayer is a handle on a text layer.
pub struct TextLayer {
pub:
	name    string
	index   int
	columns int
	rows    int
	colour  Expr // u16: the colour of the letters, CRY
	cells   Expr // u8 array
	dirty   Expr // u8 array: a row to draw again, one per row
	game    &Game
}

// text_layer declares a layer of text. Layers are drawn over all sprites,
// in the order they are declared.
pub fn (mut g Game) text_layer(name string, config TextConfig) TextLayer {
	if config.columns < 8 || config.columns % 8 != 0 || config.columns > 128 {
		g.problem('text layer `${name}`: the columns (${config.columns}) must be a multiple of 8, from 8 to 128, so that a line fills whole phrases')
	}
	if config.rows < 1 || config.rows > 64 {
		g.problem('text layer `${name}`: the rows (${config.rows}) must be 1..64')
	}
	if config.x < 0 || config.y < 0 || config.x + config.columns * 8 > logical_width
		|| config.y + config.rows * 8 > logical_height {
		g.problem('text layer `${name}`: ${config.columns * 8}x${config.rows * 8} pixels at (${config.x}, ${config.y}) does not fit the ${logical_width}x${logical_height} screen')
	}
	if g.texts.len >= max_text_layers {
		g.problem('text layer `${name}`: at most ${max_text_layers} layers')
	}
	cols := if config.columns < 1 { 8 } else { config.columns }
	rows := if config.rows < 1 { 1 } else { config.rows }
	start_colour := if config.colour == 0 { cry(255, 255, 255) } else { config.colour }
	colour := g.p.u16('${name}_colour', int(start_colour))
	cells := g.p.array_u8('${name}_cells', cols * rows)
	dirty := g.p.array_u8('${name}_dirty', rows)
	g.texts << TextInfo{
		name:        name
		columns:     cols
		rows:        rows
		x:           config.x
		y:           config.y
		colour:      colour
		cells:       cells
		dirty:       dirty
		colour_init: start_colour
	}
	return TextLayer{
		name:    name
		index:   g.texts.len - 1
		columns: cols
		rows:    rows
		colour:  colour
		cells:   cells
		dirty:   dirty
		game:    unsafe { g }
	}
}

// glyph_code is the cell value of a character.
fn glyph_code(c u8) int {
	return int(c) - jagkit.font_first
}

// cell is the index in the layer's cells of a column and a row: a number
// when both are literals, an expression otherwise.
fn (t TextLayer) cell(col Val, row Val) Val {
	if col is int {
		if row is int {
			return row * t.columns + col
		}
	}
	return lit(row).as_(.u16).mul(t.columns).add(lit(col).as_(.u16))
}

fn (t TextLayer) row_of(row Val) Val {
	if row is int {
		return row
	}
	return lit(row).as_(.u16)
}

// string_offset puts a string constant in the pool, once.
fn (mut g Game) string_offset(text string) int {
	if text in g.strings {
		return g.strings[text]
	}
	at := g.pool.len
	for c in text {
		g.pool << u8(glyph_code(c))
	}
	g.strings[text] = at
	return at
}

// print writes a string constant at a column and a row of the layer. The
// font has capitals, digits and punctuation; anything else, and a string
// that does not fit the row, is a build error. Columns and rows may be
// expressions; the machine does not check those.
pub fn (t TextLayer) print(mut c Code, col Val, row Val, text string) {
	mut g := t.game
	for ch in text {
		if int(ch) < jagkit.font_first || int(ch) >= jagkit.font_first + 64 {
			g.problem('text layer `${t.name}`: the font has no `${rune(ch)}` (in "${text}")')
			return
		}
	}
	if col is int {
		if row is int {
			if col < 0 || row < 0 || row >= t.rows || col + text.len > t.columns {
				g.problem('text layer `${t.name}`: "${text}" at column ${col}, row ${row} is outside the layer of ${t.columns}x${t.rows} cells')
				return
			}
		}
	}
	g.texts[t.index].uses_print = true
	f := g.text_print_func(t.index)
	offset := g.string_offset(text)
	c.call(f, t.cell(col, row), offset, text.len, t.row_of(row))
}

// number writes an unsigned number at a column and a row, right-aligned in
// `width` cells (1 to 10). A number with more digits shows its low digits.
// The value may be any unsigned integer expression.
pub fn (t TextLayer) number(mut c Code, col Val, row Val, value Val, width int) {
	mut g := t.game
	if width < 1 || width > 10 {
		g.problem('text layer `${t.name}`: a number takes 1 to 10 cells, not ${width}')
		return
	}
	if col is int {
		if row is int {
			if col < 0 || row < 0 || row >= t.rows || col + width > t.columns {
				g.problem('text layer `${t.name}`: a number of ${width} cells at column ${col}, row ${row} is outside the layer of ${t.columns}x${t.rows} cells')
				return
			}
		}
	}
	g.texts[t.index].uses_number = true
	f := g.text_number_func(t.index)
	c.call(f, t.cell(col, row), value, width, t.row_of(row))
}

// clear blanks the whole layer.
pub fn (t TextLayer) clear(mut c Code) {
	mut g := t.game
	g.texts[t.index].uses_clear = true
	c.call(g.text_clear_func(t.index))
}

fn (mut g Game) text_print_func(i int) Func {
	if g.texts[i].print_func.name == '' {
		g.texts[i].print_func = g.p.func('${g.texts[i].name}_print', [
			Param{'cell', .u16},
			Param{'from', .u16},
			Param{'count', .u16},
			Param{'row', .u16},
		], .void)
	}
	return g.texts[i].print_func
}

fn (mut g Game) text_number_func(i int) Func {
	if g.texts[i].number_func.name == '' {
		g.texts[i].number_func = g.p.func('${g.texts[i].name}_number', [
			Param{'cell', .u16},
			Param{'value', .u32},
			Param{'width', .u16},
			Param{'row', .u16},
		], .void)
	}
	return g.texts[i].number_func
}

fn (mut g Game) text_clear_func(i int) Func {
	if g.texts[i].clear_func.name == '' {
		g.texts[i].clear_func = g.p.func('${g.texts[i].name}_clear', [], .void)
	}
	return g.texts[i].clear_func
}

// define_text writes the functions the text layers use.
fn (mut g Game) define_text() {
	mut pool := invalid('there are no strings')
	if g.pool.len > 0 {
		pool = g.p.table_u8('rt_strings', g.pool.map(int(it)))
	}
	for i in 0 .. g.texts.len {
		t := g.texts[i]
		cells := t.cells
		dirty := t.dirty
		if t.uses_print {
			f := t.print_func
			mut c := g.p.define(f)
			k := c.local_u16('k')
			c.for_(k, 0, f.arg('count'))
			c.set(cells.at(f.arg('cell').add(k)), pool.at(f.arg('from').add(k)))
			c.end()
			c.set(dirty.at(f.arg('row')), 1)
		}
		if t.uses_number {
			g.define_number(t.number_func, cells, dirty)
		}
		if t.uses_clear {
			f := t.clear_func
			mut c := g.p.define(f)
			k := c.local_u16('k')
			c.for_(k, 0, t.columns * t.rows)
			c.set(cells.at(k), 0)
			c.end()
			c.for_(k, 0, t.rows)
			c.set(dirty.at(k), 1)
			c.end()
		}
	}
}

// define_number writes the function that turns a number into cells: the
// digits from the right, blanks where the number has run out.
fn (mut g Game) define_number(f Func, cells Expr, dirty Expr) {
	mut c := g.p.define(f)
	k := c.local_u16('k')
	rest := c.local_u32('rest')
	glyph := c.local_u8('glyph')
	c.set(rest, f.arg('value'))

	c.for_(k, 0, f.arg('width'))
	c.if_(rest.eq(0).both(k.gt(0)))
	c.set(glyph, 0)
	c.else_()
	c.set(glyph, rest.mod(10).add(glyph_code(`0`)).as_(.u8))
	c.end()
	c.set(cells.at(f.arg('cell').add(f.arg('width')).sub(1).sub(k)), glyph)
	c.set(rest, rest.div(10))
	c.end() // for each digit

	c.set(dirty.at(f.arg('row')), 1)
}
