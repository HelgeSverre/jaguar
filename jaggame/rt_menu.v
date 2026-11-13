module jaggame

// Menus. A menu is a list of text items on a text layer with a cursor that
// the pad moves: up and down move it (once at the press, and again and again
// while the button is held, after a delay), A or Pause chooses the item under
// it and B goes back. The menu is variables and ordinary code, so the
// interpreter runs it too; what it says each frame is in variables the
// game reads:
//
//	menu := game.menu('missions', layer, 4, 6, ['MISSION 1', 'BACK'])
//	menu.open(mut c)            // in the scene's enter: draws it
//	menu.update(mut c)          // in the scene's update, every frame
//	c.if_(menu.chosen.eq(0))    // chosen is the item that was chosen this frame, 255 for none
//	c.if_(menu.backed)          // B was pressed
//	c.if_(menu.moved)           // the cursor moved this frame: a sound, say

const menu_none = 255

// Menu is a handle on a menu: its variables, all valid for the frame in
// which `update` ran.
pub struct Menu {
pub:
	name   string
	items  []string
	col    int  // the column of the cursor on the layer; the items start two to the right
	row    int  // the row of the first item
	cursor Expr // u8: the item the cursor is on
	chosen Expr // u8: the item chosen this frame (A or Pause), 255 when none
	backed Expr // bool: B went down this frame
	moved  Expr // bool: the cursor moved this frame
	hold   Expr // u16: frames the up or down button has been held
	layer  TextLayer
	game   &Game
}

// menu declares a menu of `items` on a text layer, with the cursor in
// column `col` and the first item in row `row`; the items are written two
// columns to the right. An item is a string constant, as `print` takes.
pub fn (mut g Game) menu(name string, layer TextLayer, col int, row int, items []string) Menu {
	if items.len < 1 || items.len > 32 {
		g.problem('menu `${name}`: it has ${items.len} items; it must have 1..32')
	}
	for i, item in items {
		if col + 2 + item.len > layer.columns || row + i >= layer.rows || col < 0 || row < 0 {
			g.problem('menu `${name}`: item ${i} (`${item}`) does not fit the layer `${layer.name}` of ${layer.columns} by ${layer.rows} cells at column ${col}, row ${row}')
		}
	}
	return Menu{
		name:   name
		items:  items
		col:    col
		row:    row
		cursor: g.p.u8('${name}_cursor')
		chosen: g.p.u8('${name}_chosen', menu_none)
		backed: g.p.bool('${name}_backed')
		moved:  g.p.bool('${name}_moved')
		hold:   g.p.u16('${name}_hold')
		layer:  layer
		game:   unsafe { g }
	}
}

// open writes the items on the layer, puts the cursor on the first and
// forgets the last choice. Call it when the scene that shows the menu
// begins.
pub fn (m Menu) open(mut c Code) {
	for i, item in m.items {
		m.layer.print(mut c, m.col + 2, m.row + i, item)
	}
	c.set(m.cursor, 0)
	c.set(m.chosen, menu_none)
	c.set(m.backed, false)
	c.set(m.moved, false)
	c.set(m.hold, 0)
	m.draw_cursor(mut c)
}

// draw_cursor writes the cursor next to the item it is on and blanks the
// others; a mark that is already right costs a compare.
fn (m Menu) draw_cursor(mut c Code) {
	for i in 0 .. m.items.len {
		c.if_(m.cursor.eq(i))
		m.layer.print(mut c, m.col, m.row + i, '>')
		c.else_()
		m.layer.print(mut c, m.col, m.row + i, ' ')
		c.end()
	}
}

// update reads the pad for one frame: it moves the cursor (with repeat while
// a direction is held: the delay before it starts and the pace after are in
// seconds, so they are the same on both television standards), and sets
// `chosen`, `backed` and `moved`.
pub fn (m Menu) update(mut c Code) {
	g := m.game
	count := m.items.len
	first := g.seconds(0.3)
	again := g.seconds(0.1)
	c.set(m.chosen, menu_none)
	c.set(m.backed, false)
	c.set(m.moved, false)

	// Down or up: the first press moves at once, a held one repeats.
	c.if_(g.held(.down).either(g.held(.up)))
	c.if_(m.hold.eq(0))
	c.set(m.moved, true)
	c.else_if(m.hold.ge(first))
	c.set(m.moved, true)
	c.set(m.hold, first.sub(again))
	c.end() // first press, or a repeat
	c.if_(m.hold.lt(65535))
	c.inc(m.hold)
	c.end()
	c.else_()
	c.set(m.hold, 0)
	c.end() // a direction held

	c.if_(m.moved)
	c.if_(g.held(.down))
	c.inc(m.cursor)

	c.if_(m.cursor.ge(count))
	c.set(m.cursor, 0)
	c.end() // past the last
	c.else_()

	c.if_(m.cursor.eq(0))
	c.set(m.cursor, count - 1)
	c.else_()
	c.dec(m.cursor)
	c.end() // from the first
	c.end() // down or up
	m.draw_cursor(mut c)
	c.end() // the cursor moved

	c.if_(g.pressed(.a).either(g.pressed(.pause)))
	c.set(m.chosen, m.cursor)
	c.end() // A or Pause

	c.if_(g.pressed(.b))
	c.set(m.backed, true)
	c.end() // B
}
