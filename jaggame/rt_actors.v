module jaggame

// Actors: an array of records tied to sprites. It is records plus sprites
// plus (if the game wants one) a state machine, and nothing else: actor `i`
// owns sprite `first + i` of the pool, its record holds where it is, which
// way it faces, whether it is alive and whatever fields the game adds, and
// the loop `each` visits the live ones.
//
//	guards := game.actors('guards', [jaggame.Field{'wp', .u8}], 4, 1)
//	i := c.local_u16('i')
//	guards.each(mut c, i)
//	…guards.x(i)…
//	c.end()

// Actors is an array of actor records. Every actor has the fields `x` and
// `y` (`fix`, the top left corner of its sprite in the world, in pixels),
// `face` (`u8`, a direction as an angle: 0 right, 64 down, 128 left, 192
// up) and `live` (`bool`), then the fields the game gave.
@[heap]
pub struct Actors {
pub:
	name    string
	count   int
	first   int  // the sprite of actor 0
	records Expr // the array of records
	spawn_f Func
mut:
	game   &Game
	fields []Field
}

// actors declares an array of `count` actors whose sprites are `first` to
// `first + count - 1` of the pool, with extra fields. Actors start dead and
// their sprites hidden; `spawn` makes one live.
pub fn (mut g Game) actors(name string, extra []Field, count int, first int) &Actors {
	if first < 0 || first + count > g.config.sprites {
		g.problem('actors `${name}`: sprites ${first}..${first + count - 1} are not in the pool of ${g.config.sprites}')
	}
	mut fields := [Field{'x', .fix}, Field{'y', .fix}, Field{'face', .u8},
		Field{'live', .bool}]
	fields << extra
	record := g.p.record('${name}_record', fields)
	records := g.p.array_of(name, record, count)
	spawner := g.p.func('${name}_spawn', [Param{'x', .fix}, Param{'y', .fix}], .u16)
	mut a := &Actors{
		name:    name
		count:   count
		first:   first
		records: records
		spawn_f: spawner
		game:    g
		fields:  fields
	}
	a.define_spawn()
	return a
}

// at is the record of actor `i`, whose fields are values and destinations.
pub fn (a &Actors) at(i Val) Expr {
	return a.records.at(i)
}

// field is a field of actor `i`.
pub fn (a &Actors) field(i Val, name string) Expr {
	return a.records.at(i).field(name)
}

// x is the x position of actor `i` in world pixels, a `fix`.
pub fn (a &Actors) x(i Val) Expr {
	return a.field(i, 'x')
}

// y is the y position of actor `i`, a `fix`.
pub fn (a &Actors) y(i Val) Expr {
	return a.field(i, 'y')
}

// face is the direction of actor `i` as an angle (`u8`).
pub fn (a &Actors) face(i Val) Expr {
	return a.field(i, 'face')
}

// live is true while actor `i` is alive.
pub fn (a &Actors) live(i Val) Expr {
	return a.field(i, 'live')
}

// sprite is the sprite that actor `i` owns.
pub fn (a &Actors) sprite(i Val) Sprite {
	if i is int {
		return a.game.sprite_at(i + a.first)
	}
	return a.game.sprite_at(lit(i).add(a.first))
}

// spawn is a call that makes the first dead actor live at a position: it
// clears the record, sets `x`, `y` and `live`, shows the sprite, and gives the
// number of the actor, or 65535 when all are alive. The sprite's picture is
// the game's to set. Use `c.call(actors.spawn_f, x, y)` when the number is not
// wanted.
pub fn (a &Actors) spawn(x Val, y Val) Expr {
	return a.spawn_f.call(x, y)
}

// remove kills actor `i` and hides its sprite.
pub fn (a &Actors) remove(mut c Code, i Val) {
	c.set(a.live(i), false)
	a.sprite(i).hide(mut c)
}

// each opens a loop over the live actors: `i` (a `u16` local) takes the
// number of each in turn. `end()` closes it; `break_` and `continue_` work.
pub fn (a &Actors) each(mut c Code, i Expr) {
	c.for_where(i, 0, a.count, a.live(i))
}

// show puts the actor's sprite where the actor is, `ox` and `oy` pixels
// from its position (a sprite is drawn from its corner, an actor's position
// may be elsewhere).
pub fn (a &Actors) show(mut c Code, i Val, ox int, oy int) {
	s := a.sprite(i)
	c.set(s.x, a.x(i).as_(.i16).add(ox))
	c.set(s.y, a.y(i).as_(.i16).add(oy))
}

fn (mut a Actors) define_spawn() {
	mut g := a.game
	mut c := g.p.define(a.spawn_f)
	i := c.local_u16('i')

	c.for_(i, 0, a.count)

	c.if_(a.live(i).invert())
	for f in a.fields {
		if f.name == 'live' {
			continue
		}
		c.set(a.field(i, f.name), 0)
	}
	c.set(a.x(i), a.spawn_f.arg('x'))
	c.set(a.y(i), a.spawn_f.arg('y'))
	c.set(a.live(i), true)
	c.set(a.sprite(i).visible, true)
	c.ret(i)
	c.end() // a dead one
	c.end() // for each
	c.ret(65535)
}
