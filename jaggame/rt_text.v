module jaggame

import jagkit { idx, imm, lbl }

// Text. A text layer is a grid of 8x8 character cells drawn over the
// sprites. Its cells are an array of the program (`<name>_cells`, one byte
// a cell: 0 is a blank, 1 is `!`, and so on in the order of ASCII from 32
// to 95), so printing is ordinary code that the interpreter runs too; the
// runtime draws the rows that changed once a frame.
//
// A layer has a colour, the variable `<name>_colour` (CRY, see `cry`).
// The font has capitals, digits and punctuation only.
//
// Only what changed is drawn again: `print` and `number` mark a cell (in
// `<name>_stale`) and its row (in `<name>_dirty`) when they put a different
// glyph in it, and the machine draws the marked cells once a frame. Printing
// the same text again costs a compare for each character and nothing more.

struct TextInfo {
	name    string
	columns int
	rows    int
	x       int
	y       int
	colour  Expr
	cells   Expr
	dirty   Expr
	stale   Expr
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
	dirty   Expr // u8 array: a row that has a cell to draw again, one per row
	stale   Expr // u8 array: a cell to draw again, one per cell
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
	stale := g.p.array_u8('${name}_stale', cols * rows)
	g.texts << TextInfo{
		name:        name
		columns:     cols
		rows:        rows
		x:           config.x
		y:           config.y
		colour:      colour
		cells:       cells
		dirty:       dirty
		stale:       stale
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
		stale:   stale
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
		stale := t.stale
		if t.uses_print {
			f := t.print_func
			mut c := g.p.define(f)
			k := c.local_u16('k')
			at := c.local_u16('at')
			glyph := c.local_u8('glyph')
			c.for_(k, 0, f.arg('count'))
			c.set(glyph, pool.at(f.arg('from').add(k)))
			c.set(at, f.arg('cell').add(k))

			c.if_(cells.at(at).ne(glyph))
			c.set(cells.at(at), glyph)
			c.set(stale.at(at), 1)
			c.set(dirty.at(f.arg('row')), 1)
			c.end() // a different glyph
			c.end() // for each character
		}
		if t.uses_number {
			g.define_number(t)
		}
		if t.uses_clear {
			f := t.clear_func
			mut c := g.p.define(f)
			k := c.local_u16('k')
			c.for_(k, 0, t.columns * t.rows)
			c.set(cells.at(k), 0)
			c.set(stale.at(k), 1)
			c.end()
			c.for_(k, 0, t.rows)
			c.set(dirty.at(k), 1)
			c.end()
		}
	}
}

// define_number writes the function that turns a number into cells: the
// digits from the right, blanks where the number has run out. A cell that
// already shows the right glyph is left alone, and only a changed cell is
// marked to be drawn. It is machine code (the language's division is the
// slow part of a number) with the same behaviour in the interpreter.
fn (mut g Game) define_number(t TextInfo) {
	f := t.number_func
	mut c := g.p.define(f)
	name := t.name
	c.native(fn [f, name] (mut m jagkit.M68k) {
		emit_number(mut m, f, name)
	}, fn [f, name] (mut it Interpreter) ! {
		run_number(mut it, f, name)!
	})
}

// emit_number is the machine code of a number function: `f` has the
// parameters cell, value, width and row, and the layer's arrays are
// `<name>_cells`, `<name>_stale` and `<name>_dirty`. A value of 65535 or
// less takes one division by 10 a digit, a larger one two.
fn emit_number(mut m jagkit.M68k, f Func, name string) {
	value := lbl('${f.name}.value')
	more := m.unique('rt.digit')
	blank := m.unique('rt.blank')
	store := m.unique('rt.store')
	next := m.unique('rt.next')
	wide := m.unique('rt.wide')
	have := m.unique('rt.have')
	done := m.unique('rt.number_done')
	m.move(.l, value, d0)
	m.moveq(0, d1)
	m.move(.w, lbl('${f.name}.width'), d1)
	m.moveq(0, d2)
	m.move(.w, lbl('${f.name}.cell'), d2)
	m.lea(lbl('${name}_cells'), a1)
	m.add(.l, d2, a1)
	m.lea(lbl('${name}_stale'), a2)
	m.add(.l, d2, a2)
	m.move(.l, d1, d3)
	m.sub(.w, imm(1), d3) // the counter: the cell from the right, width-1 down to 0
	m.move(.w, d3, d4) // width-1 stands for the first digit
	m.moveq(0, d6)
	m.label(more)
	m.tst(.l, d0)
	m.b(.ne, blank + '_digit')
	m.cmp(.w, d4, d3)
	m.b(.eq, blank + '_digit') // the last cell shows a 0
	m.moveq(0, d1)
	m.bra(store)
	m.label(blank + '_digit')
	m.move(.l, d0, d1)
	m.swap(d1)
	m.tst(.w, d1)
	m.b(.ne, wide)
	m.move(.l, d0, d1)
	m.divu(imm(10), d1) // quotient in the low word, remainder in the high
	m.moveq(0, d2)
	m.move(.w, d1, d2)
	m.bra(have)
	m.label(wide)
	m.move(.l, d0, d1)
	m.clr(.w, d1)
	m.swap(d1)
	m.divu(imm(10), d1) // the upper word: quotient low, remainder high
	m.moveq(0, d2)
	m.move(.w, d1, d2)
	m.swap(d2) // the upper half of the answer
	m.move(.w, d0, d1) // the remainder and the lower word
	m.divu(imm(10), d1)
	m.move(.w, d1, d2)
	m.label(have)
	m.swap(d1) // the remainder
	m.add(.w, imm(glyph_code(`0`)), d1)
	m.move(.l, d2, d0)
	m.label(store)
	m.cmp(.b, idx(0, a1, d3), d1)
	m.b(.eq, next)
	m.move(.b, d1, idx(0, a1, d3))
	m.move(.b, imm(1), idx(0, a2, d3))
	m.moveq(1, d6)
	m.label(next)
	m.dbra(d3, more)
	m.tst(.b, d6)
	m.b(.eq, done)
	m.lea(lbl('${name}_dirty'), a3)
	m.moveq(0, d2)
	m.move(.w, lbl('${f.name}.row'), d2)
	m.move(.b, imm(1), idx(0, a3, d2))
	m.label(done)
}

// run_number is what the interpreter does for a number function: the same
// as `emit_number`, digit by digit.
fn run_number(mut it Interpreter, f Func, name string) ! {
	cell := int(it.get_label('${f.name}.cell', 0)!)
	mut rest := it.get_label('${f.name}.value', 0)!
	width := int(it.get_label('${f.name}.width', 0)!)
	row := int(it.get_label('${f.name}.row', 0)!)
	mut changed := false
	for k in 0 .. width {
		at := cell + width - 1 - k
		glyph := if rest == 0 && k > 0 { i64(0) } else { rest % 10 + glyph_code(`0`) }
		rest /= 10
		if it.get_label('${name}_cells', at)! != glyph {
			it.put_label('${name}_cells', at, glyph)!
			it.put_label('${name}_stale', at, 1)!
			changed = true
		}
	}
	if changed {
		it.put_label('${name}_dirty', row, 1)!
	}
}
