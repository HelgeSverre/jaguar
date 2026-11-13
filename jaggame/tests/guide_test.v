module main

import jaggame
import jaggame.emulated
import os

// docs/jaggame/guide.md shows only code that is tested. Every ```v block in
// it is named by an HTML comment on the line above it, `<!-- guide:NAME -->`,
// and must be a run of lines from the region of that name: the lines of a
// test in this directory (or of the hello2 demo) between `// guide:NAME` and
// `// guide:end`. Every ```text block must be text that a test here
// produces. This file also holds the guide's own examples.

fn first_program() (&jaggame.Program, jaggame.Func) {
	// guide:first
	mut p := jaggame.new_program()
	score := p.u16('score')
	lives := p.u8('lives', 3)

	bonus := p.func('bonus', [jaggame.Param{'level', .u16}], .u16)
	mut c := p.define(bonus)
	c.ret(bonus.arg('level').mul(100).add(50))

	main := p.func('main', [], .void)
	c = p.define(main)
	level := c.local_u8('level')

	c.for_(level, 1, 4)
	c.add_to(score, bonus.call(level))
	c.end()
	c.dec(lives)
	// guide:end
	return p, main
}

fn test_the_first_program() {
	p, main := first_program()
	// guide:run
	mut it := p.interpreter()!
	it.run('main')!
	assert it.value('score')! == 750
	assert it.value('lives')! == 2

	img := p.plain_image(main)!
	mut runner := emulated.new()
	runner.run(img.bytes, img.done, 60)!
	assert img.value(runner.ram(), 'score')! == 750
	assert img.differences(it, runner.ram()) == []
	// guide:end
}

fn mistakes() string {
	// guide:mistakes
	mut p := jaggame.new_program()
	speed := p.fix('speed', 1.5)
	x := p.i16('x')
	hits := p.u8('hits')
	update := p.func('update', [], .void)
	mut c := p.define(update)
	c.set(x, x.add(speed))

	c.if_(hits)
	c.set(hits, hits.add(x))
	c.end()
	c.set(x, 40000)
	p.check() or { return err.msg() }
	// guide:end
	return ''
}

fn test_mistakes_are_reported_together() {
	assert mistakes().count('\n') == 4
}

fn listing() string {
	p, main := first_program()
	return p.listing(main)
}

fn expressions() string {
	// guide:expressions
	mut p := jaggame.new_program()
	score := p.u16('score')
	lives := p.u8('lives', 3)
	speed := p.fix('speed', 1.5)
	bag := p.array_u8('bag', 16)
	sines := p.table_i16('sines', [0, 3212, 6393, 9512])

	a := score.add(10) // u16
	b := score.lt(lives) // bool: the u8 widens to u16
	d := speed.mul(lives) // fix: lives becomes 3.0
	e := bag.at(3).add(1) // u8: 255 + 1 wraps to 0
	f := sines.at(score.and(3)).as_(.i32).mul(2) // i32
	g := score + lives.as_(.u16) // operators work between two Exprs
	// guide:end
	return [a, b, d, e, f, g].map(p.show(it)).join('\n')
}

fn test_expressions_print_as_they_are_written() {
	assert expressions() == 'score.add(10)\nscore.lt(lives)\nspeed.mul(lives)\nbag.at(3).add(1)\nsines.at(score.and(3)).as_(.i32).mul(2)\nscore.add(lives.as_(.u16))'
}

fn statements() string {
	// guide:statements
	mut p := jaggame.new_program()
	x := p.i16('x')
	alert := p.bool('alert')
	steps := p.u16('steps')
	walk := p.func('walk', [jaggame.Param{'far', .i16}], .void)
	mut c := p.define(walk)
	i := c.local_u8('i')

	c.if_(walk.arg('far').gt(100))
	c.set(alert, true)
	c.else_if(walk.arg('far').gt(50))
	c.inc(steps)
	c.else_()
	c.ret_void()
	c.end()

	c.for_(i, 0, 8) // i is 0..7
	c.if_(x.ge(walk.arg('far')))
	c.break_()
	c.end()
	c.add_to(x, 10)
	c.end()

	c.while_(x.gt(0).both(alert))
	c.sub_from(x, 3)
	c.end()

	c.repeat(3)
	c.inc(steps)
	c.end()
	// guide:end
	p.check() or { return err.msg() }
	return ''
}

// door is a state machine with two states: it stays closed for three frames
// and open for two, and logs where it has been.
fn door() (&jaggame.Program, jaggame.Func) {
	// guide:machine
	mut p := jaggame.new_program()
	log := p.array_u8('log', 12)
	n := p.u8('n')
	mut door := p.machine_global('door')

	mut c := door.state('closed')
	c.set(log.at(n), 0)
	c.inc(n)

	c.if_(c.time_in_state().ge(2))
	c.to('open') // the state changes now; the body of `open` runs from the next frame
	c.end()

	c = door.state('open')
	c.set(log.at(n), 1)
	c.inc(n)

	c.if_(c.time_in_state().ge(1))
	c.to('closed')
	c.end()

	c = door.on_enter('open') // runs at the transition, with time_in_state 0
	c.set(log.at(n), 9)
	c.inc(n)

	tick := p.func('tick', [], .void)
	c = p.define(tick)
	door.run(mut c, 0) // one frame of the machine, for the record 0
	// guide:end
	return p, tick
}

fn machine_log() string {
	p, tick := door()
	mut it := p.interpreter() or { panic(err) }
	for _ in 0 .. 10 {
		it.run('tick') or { panic(err) }
	}
	mut line := []string{}
	for i in 0 .. 10 {
		line << (it.element('log', i) or { panic(err) }).str()
	}
	_ = tick
	return line.join(' ')
}

// machine_mistakes is a machine with the three mistakes a machine can make.
fn machine_mistakes() string {
	// guide:machine_mistakes
	mut p := jaggame.new_program()
	mut guard := p.machine_global('guard')
	mut c := guard.state('patrol')
	c.to('chase') // there is no such state
	guard.state('patrol') // a state is declared once
	p.machine_global('camera') // a machine needs states
	p.check() or { return err.msg() }
	// guide:end
	return ''
}

fn test_the_machine_examples() {
	p, _ := door()
	p.check()!
	// closed, closed, closed (then it opens: on_enter logs 9), open, open (closes), closed ...
	assert machine_log() == '0 0 0 9 1 1 0 0 0 9'
	assert machine_mistakes().count('\n') == 3
}

// asset_mistakes is a game whose files and map are wrong, and what the
// build says about it, without the folder the files are in.
fn asset_mistakes() string {
	dir := os.join_path(os.temp_dir(), 'jaggame_guide_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	mut wide := jaggame.new_canvas(40, 16)
	wide.fill(0, 0, 40, 16, 20, 40, 60)
	wide.save(dir + '/tiles.png') or { panic(err) }
	// guide:asset_mistakes
	mut game := jaggame.new_game(jaggame.Config{ sprites: 2 })
	game.tileset(dir + '/tiles.png') // 40 pixels wide: not whole tiles of 16
	game.png_cry('logo', dir + '/logo.png', 16, 16) // there is no such file
	game.legend_tile(`#`, 1, jaggame.flag_solid)
	game.legend_tile(`#`, 2, 0) // a character is given once
	game.room('lab', '
#####
#..@#
##
')
	game.build() or { return err.msg().replace(dir + '/', '') }
	// guide:end
	return ''
}

fn test_the_asset_mistakes_are_reported_together() {
	text := asset_mistakes()
	assert text.contains('tiles.png: the picture is 40x16 pixels, which a grid of 16x16 does not divide')
	assert text.contains('logo.png: the file does not exist')
	assert text.contains('the character `#` is given twice')
	assert text.contains('row 3 has 2 characters, row 1 has 5')
	assert text.contains('`.` at row 2, column 2 is not in the legend')
	assert text.count('\n') == 6
}

fn test_the_game_mistakes_are_reported_together() {
	assert game_mistakes().count('\n') == 6
}

fn test_the_statements_example_checks() {
	assert statements() == ''
}

fn game_mistakes() string {
	// guide:game_mistakes
	mut game := jaggame.new_game(jaggame.Config{ sprites: 4 })
	game.art_cry('ball', 30, 30, 1, []u16{len: 900})
	hud := game.text_layer('hud', jaggame.TextConfig{ columns: 12, rows: 2 })

	mut c := game.define_init()
	ball := game.sprite(6)
	ball.put(mut c, 'bal', 10, 10, 0)
	ball.play(mut c, 'spin', true)
	hud.print(mut c, 5, 0, 'Score')
	game.build() or { return err.msg() }
	// guide:end
	return ''
}

// texts are the ```text blocks the guide may show.
fn texts() []string {
	return [mistakes(), listing(), expressions(), game_mistakes(),
		asset_mistakes(), machine_mistakes(), machine_log()]
}

struct Region {
	name  string
	file  string
	lines []string
}

// dedent removes the indentation that every non-empty line shares.
fn dedent(lines []string) []string {
	mut least := 1000
	for l in lines {
		if l.trim_space() != '' {
			least = int_min(least, l.len - l.trim_left('\t ').len)
		}
	}
	return lines.map(if it.trim_space() == '' { '' } else { it[least..] })
}

// guide_sources are the files that hold guide regions: the tests of this
// directory and the demos the guide walks through.
fn guide_sources() []string {
	dir := os.dir(@FILE)
	mut files := []string{}
	for name in os.ls(dir) or { [] } {
		if name.ends_with('_test.v') {
			files << os.join_path(dir, name)
		}
	}
	files << os.join_path(dir, '..', '..', 'demos', 'hello2', 'main.v')
	files << os.join_path(dir, '..', '..', 'demos', 'hello2', 'hello2_test.v')
	for name in ['main.v', 'mission.v', 'guards.v'] {
		files << os.join_path(dir, '..', '..', 'demos', 'ghostgrid', name)
	}
	files << os.join_path(dir, '..', '..', 'demos', 'ghostgrid', 'ghostgrid_test.v')
	return files
}

fn regions() []Region {
	mut found := []Region{}
	for path in guide_sources() {
		mut name := ''
		mut lines := []string{}
		for line in os.read_lines(path) or { panic(err) } {
			t := line.trim_space()
			if t.starts_with('// guide:') {
				if t == '// guide:end' {
					assert name != '', '${path}: // guide:end without a region'
					found << Region{name, os.file_name(path), dedent(lines)}
					name = ''
					lines = []string{}
				} else {
					name = t['// guide:'.len..]
				}
				continue
			}
			if name != '' {
				lines << line
			}
		}
		assert name == '', '${path}: the region ${name} is not closed'
	}
	return found
}

struct Block {
	kind  string
	name  string // from the comment above a ```v block
	lines []string
	at    int // line number in the guide
}

fn guide_blocks() []Block {
	path := os.join_path(os.dir(@FILE), '..', '..', 'docs', 'jaggame', 'guide.md')
	mut blocks := []Block{}
	mut kind := ''
	mut lines := []string{}
	mut at := 0
	mut name := ''
	mut last_comment := ''
	for n, line in os.read_lines(path) or { panic(err) } {
		if line.starts_with('```') {
			if kind == '' {
				kind = line[3..].trim_space()
				at = n + 1
				lines = []string{}
				name = last_comment
			} else {
				blocks << Block{kind, name, lines, at}
				kind = ''
			}
			continue
		}
		if kind != '' {
			lines << line
		} else if line.starts_with('<!-- guide:') && line.ends_with(' -->') {
			last_comment = line['<!-- guide:'.len..line.len - ' -->'.len]
		} else if line.trim_space() != '' {
			last_comment = '' // the comment must come right before the block
		}
	}
	return blocks
}

fn contains_run(haystack []string, needle []string) bool {
	if needle.len == 0 {
		return true
	}
	for start in 0 .. haystack.len - needle.len + 1 {
		if haystack[start..start + needle.len] == needle {
			return true
		}
	}
	return false
}

fn test_every_code_block_in_the_guide_is_tested() {
	all := regions()
	made := texts()
	blocks := guide_blocks()
	assert blocks.len > 0
	for b in blocks {
		match b.kind {
			'v' {
				code := dedent(b.lines)
				assert b.name != '', 'guide.md line ${b.at}: a V block needs a <!-- guide:NAME --> comment on the line above it'
				named := all.filter(it.name == b.name)
				assert named.len == 1, 'guide.md line ${b.at}: there must be exactly one guide region called ${b.name}, there are ${named.len}'
				assert contains_run(named[0].lines, code), 'guide.md line ${b.at}: this V block is not a run of lines from the region ${b.name} in ${named[0].file}'
			}
			'text' {
				assert b.lines.join('\n') in made, 'guide.md line ${b.at}: this text is not produced by a test:\n${b.lines.join('\n')}'
			}
			'sh' {} // commands to type, not code
			else {
				assert false, 'guide.md line ${b.at}: a ```${b.kind} block cannot be checked'
			}
		}
	}
}
