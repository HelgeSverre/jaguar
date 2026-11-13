module main

import jaggame
import jaggame.emulated
import os

// docs/jaggame/guide.md shows only code that is tested. Every ```v block in
// it must be a run of lines from a region of a test in this directory
// between `// guide:NAME` and `// guide:end`, and every ```text block must
// be text that a test here produces. This file also holds the guide's own
// examples.

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

fn test_the_statements_example_checks() {
	assert statements() == ''
}

// texts are the ```text blocks the guide may show.
fn texts() []string {
	return [mistakes(), listing(), expressions()]
}

struct Region {
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

fn regions() []Region {
	dir := os.dir(@FILE)
	mut found := []Region{}
	for name in os.ls(dir) or { [] } {
		if !name.ends_with('_test.v') {
			continue
		}
		mut inside := false
		mut lines := []string{}
		for line in os.read_lines(os.join_path(dir, name)) or { [] } {
			t := line.trim_space()
			if t.starts_with('// guide:') {
				if t == '// guide:end' {
					found << Region{name, dedent(lines)}
					lines = []string{}
					inside = false
				} else {
					inside = true
				}
				continue
			}
			if inside {
				lines << line
			}
		}
	}
	return found
}

struct Block {
	kind  string
	lines []string
	at    int // line number in the guide
}

fn guide_blocks() []Block {
	path := os.join_path(os.dir(@FILE), '..', '..', 'docs', 'jaggame', 'guide.md')
	mut blocks := []Block{}
	mut kind := ''
	mut lines := []string{}
	mut at := 0
	for n, line in os.read_lines(path) or { panic(err) } {
		if line.starts_with('```') {
			if kind == '' {
				kind = line[3..].trim_space()
				at = n + 1
				lines = []string{}
			} else {
				blocks << Block{kind, lines, at}
				kind = ''
			}
			continue
		}
		if kind != '' {
			lines << line
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
				assert all.any(contains_run(it.lines, code)), 'guide.md line ${b.at}: this V block is not in a guide region of a test'
			}
			'text' {
				assert b.lines.join('\n') in made, 'guide.md line ${b.at}: this text is not produced by a test:\n${b.lines.join('\n')}'
			}
			else {
				assert false, 'guide.md line ${b.at}: a ```${b.kind} block cannot be checked'
			}
		}
	}
}
