module jaggame

import jagkit { idx, imm, lbl }

// The tile queries in machine code. They are what a game calls most, from
// collision to (in later slices) line of sight, so the compiled versions
// were too slow: `tile_at` took about 1,300 cycles. Each routine has the
// behaviour of its twin in V for the interpreter, and the tests run both.

// emit_cell_at writes the machine code of `tile_at` and `flags_at`: the
// parameters x and y of function `f` are positions in pixels; the result
// goes in d0, the tile number or (with `flags`) the tile's flags, and 255 for
// a position outside the room.
fn emit_cell_at(mut m jagkit.M68k, f Func, flags bool) {
	outside := m.unique('rt.outside')
	done := m.unique('rt.cell_done')
	m.move(.l, lbl('${f.name}.x'), d0)
	m.asr(.l, imm(4), d0)
	m.move(.l, lbl('${f.name}.y'), d1)
	m.asr(.l, imm(4), d1)
	m.move(.w, lbl('rt_room_w'), d2)
	m.ext(.l, d2)
	m.move(.w, lbl('rt_room_h'), d3)
	m.ext(.l, d3)
	m.tst(.l, d0)
	m.b(.mi, outside)
	m.cmp(.l, d2, d0)
	m.b(.ge, outside)
	m.tst(.l, d1)
	m.b(.mi, outside)
	m.cmp(.l, d3, d1)
	m.b(.ge, outside)
	m.mulu(d2, d1)
	m.add(.l, d0, d1)
	m.lea(lbl('rt_map'), a0)
	m.moveq(0, d0)
	m.move(.b, idx(0, a0, d1), d0)
	if flags {
		m.lea(lbl('rt_tile_flags'), a0)
		m.move(.b, idx(0, a0, d0), d0)
	}
	m.bra(done)
	m.label(outside)
	m.move(.l, imm(if flags { flag_solid } else { tile_none }), d0)
	m.label(done)
}

// run_cell_at is what the interpreter does for `tile_at` and `flags_at`.
fn run_cell_at(mut it Interpreter, f Func, flags bool) ! {
	x := it.get_label('${f.name}.x', 0)! >> 4
	y := it.get_label('${f.name}.y', 0)! >> 4
	w := it.get_label('rt_room_w', 0)!
	h := it.get_label('rt_room_h', 0)!
	if x < 0 || y < 0 || x >= w || y >= h {
		it.result = if flags { i64(flag_solid) } else { i64(tile_none) }
		return
	}
	tile := it.get_label('rt_map', int(y * w + x))!
	it.result = if flags { it.get_label('rt_tile_flags', int(tile))! } else { tile }
}

// emit_line_solid writes the machine code of `col_solid` and `row_solid`:
// whether any tile along a column (`vertical`: from row r0 to r1) or along
// a row (from column c0 to c1) is solid or outside the room. The result,
// 1 or 0, goes in d0.
fn emit_line_solid(mut m jagkit.M68k, f Func, vertical bool) {
	yes := m.unique('rt.solid')
	no := m.unique('rt.clear')
	again := m.unique('rt.along')
	done := m.unique('rt.line_done')
	fixed := if vertical { '${f.name}.col' } else { '${f.name}.row' }
	from := if vertical { '${f.name}.r0' } else { '${f.name}.c0' }
	to := if vertical { '${f.name}.r1' } else { '${f.name}.c1' }
	m.move(.l, lbl(fixed), d0)
	m.move(.l, lbl(from), d1)
	m.move(.l, lbl(to), d2)
	m.move(.w, lbl('rt_room_w'), d3)
	m.ext(.l, d3)
	m.move(.w, lbl('rt_room_h'), d4)
	m.ext(.l, d4)
	m.cmp(.l, d1, d2)
	m.b(.lt, no) // nothing to look at
	// The line itself, and its ends, must be in the room.
	m.tst(.l, d0)
	m.b(.mi, yes)
	m.tst(.l, d1)
	m.b(.mi, yes)
	if vertical {
		m.cmp(.l, d3, d0)
		m.b(.ge, yes)
		m.cmp(.l, d4, d2)
		m.b(.ge, yes)
	} else {
		m.cmp(.l, d4, d0)
		m.b(.ge, yes)
		m.cmp(.l, d3, d2)
		m.b(.ge, yes)
		m.mulu(d3, d0) // the row's first cell
	}
	m.lea(lbl('rt_map'), a0)
	m.lea(lbl('rt_tile_flags'), a1)
	m.label(again)
	if vertical {
		m.move(.l, d1, d5)
		m.mulu(d3, d5)
		m.add(.l, d0, d5)
	} else {
		m.move(.l, d0, d5)
		m.add(.l, d1, d5)
	}
	m.moveq(0, d6)
	m.move(.b, idx(0, a0, d5), d6)
	m.move(.b, idx(0, a1, d6), d6)
	m.btst(0, d6) // flag_solid
	m.b(.ne, yes)
	m.add(.l, imm(1), d1)
	m.cmp(.l, d1, d2)
	m.b(.ge, again)
	m.label(no)
	m.moveq(0, d0)
	m.bra(done)
	m.label(yes)
	m.moveq(1, d0)
	m.label(done)
}

// run_line_solid is what the interpreter does for `col_solid` and `row_solid`.
fn run_line_solid(mut it Interpreter, f Func, vertical bool) ! {
	fixed := it.get_label(if vertical { '${f.name}.col' } else { '${f.name}.row' }, 0)!
	from := it.get_label(if vertical { '${f.name}.r0' } else { '${f.name}.c0' }, 0)!
	to := it.get_label(if vertical { '${f.name}.r1' } else { '${f.name}.c1' }, 0)!
	w := it.get_label('rt_room_w', 0)!
	h := it.get_label('rt_room_h', 0)!
	it.result = 0
	for k := from; k <= to; k++ {
		col := if vertical { fixed } else { k }
		row := if vertical { k } else { fixed }
		if col < 0 || row < 0 || col >= w || row >= h {
			it.result = 1
			return
		}
		tile := it.get_label('rt_map', int(row * w + col))!
		if it.get_label('rt_tile_flags', int(tile))! & flag_solid != 0 {
			it.result = 1
			return
		}
	}
}

// emit_set_tile writes the machine code of `set_tile` (the parameters x, y
// and tile of function `f`) and, with `by_place` false, of `set_cell` (cell
// and tile): the map gets the tile and the cell is put in the queue of
// cells to draw, or counted as lost when the queue is full. A place outside
// the room is ignored.
fn emit_set_tile(mut m jagkit.M68k, f Func, by_place bool) {
	done := m.unique('rt.set_done')
	full := m.unique('rt.set_full')
	if by_place {
		m.move(.l, lbl('${f.name}.x'), d0)
		m.move(.l, lbl('${f.name}.y'), d1)
		m.move(.w, lbl('rt_room_w'), d2)
		m.ext(.l, d2)
		m.move(.w, lbl('rt_room_h'), d3)
		m.ext(.l, d3)
		m.tst(.l, d0)
		m.b(.mi, done)
		m.cmp(.l, d2, d0)
		m.b(.ge, done)
		m.tst(.l, d1)
		m.b(.mi, done)
		m.cmp(.l, d3, d1)
		m.b(.ge, done)
		m.mulu(d2, d1)
		m.add(.l, d0, d1)
	} else {
		m.moveq(0, d1)
		m.move(.w, lbl('${f.name}.cell'), d1)
		m.moveq(0, d2)
		m.move(.w, lbl('rt_load_cells'), d2)
		m.cmp(.l, d2, d1)
		m.b(.cc, done)
	}
	m.moveq(0, d4)
	m.move(.b, lbl('${f.name}.tile'), d4)
	m.lea(lbl('rt_map'), jagkit.a0)
	m.move(.b, d4, idx(0, jagkit.a0, d1))
	m.moveq(0, d4)
	m.move(.b, lbl('rt_tile_count'), d4)
	m.cmp(.l, imm(tile_queue_size), d4)
	m.b(.cc, full)
	m.move(.l, d4, d5)
	m.lsl(.l, imm(1), d5)
	m.lea(lbl('rt_tile_queue'), jagkit.a1)
	m.move(.w, d1, idx(0, jagkit.a1, d5))
	m.add(.l, imm(1), d4)
	m.move(.b, d4, lbl('rt_tile_count'))
	m.bra(done)
	m.label(full)
	m.move(.w, lbl('rt_tile_lost'), d4)
	m.add(.l, imm(1), d4)
	m.move(.w, d4, lbl('rt_tile_lost'))
	m.label(done)
}

// run_set_tile is what the interpreter does for `set_tile` and `set_cell`.
fn run_set_tile(mut it Interpreter, f Func, by_place bool) ! {
	w := it.get_label('rt_room_w', 0)!
	h := it.get_label('rt_room_h', 0)!
	mut cell := i64(0)
	if by_place {
		x := it.get_label('${f.name}.x', 0)!
		y := it.get_label('${f.name}.y', 0)!
		if x < 0 || y < 0 || x >= w || y >= h {
			return
		}
		cell = y * w + x
	} else {
		cell = it.get_label('${f.name}.cell', 0)!
		if cell >= it.get_label('rt_load_cells', 0)! {
			return
		}
	}
	it.put_label('rt_map', int(cell), it.get_label('${f.name}.tile', 0)!)!
	count := it.get_label('rt_tile_count', 0)!
	if count < tile_queue_size {
		it.put_label('rt_tile_queue', int(count), cell)!
		it.put_label('rt_tile_count', 0, count + 1)!
	} else {
		it.put_label('rt_tile_lost', 0, it.get_label('rt_tile_lost', 0)! + 1)!
	}
}
