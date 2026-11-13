module main

import jaggame
import jaggame.emulated
import math

// Four complete programs, each run by the interpreter and on the emulated
// 68000. The results are checked against values worked out here in plain
// V, and every variable must agree between the two runs.
//
// The code between `// guide:` markers is quoted in docs/jaggame/guide.md;
// guide_test.v checks that the quotes match.

struct BothWays {
	it  &jaggame.Interpreter
	img jaggame.Image
	ram []u8
}

// run_both_ways runs `main` in the interpreter and in the emulator and
// fails on any variable that differs.
fn run_both_ways(p &jaggame.Program, main jaggame.Func) !BothWays {
	mut it := p.interpreter()!
	it.run(main.name)!
	img := p.plain_image(main)!
	mut runner := emulated.new()
	frames := runner.run(img.bytes, img.done, 600)!
	ram := runner.ram().clone()
	differences := img.differences(it, ram)
	if differences.len > 0 {
		return error('the interpreter and the 68000 disagree:\n' + differences.join('\n'))
	}
	println('${main.name}: ${img.payload.len} bytes, done in ${frames} frames')
	return BothWays{it, img, ram}
}

fn (b &BothWays) values(name string, count int) []i64 {
	mut out := []i64{}
	for i in 0 .. count {
		out << b.it.element(name, i) or { panic(err) }
	}
	return out
}

fn sort_input() []int {
	mut values := []int{}
	mut seed := u32(12345)
	for _ in 0 .. 32 {
		seed = seed * 1103515245 + 12345
		values << int(i16(seed >> 8))
	}
	values[5] = -32768
	values[6] = 32767
	values[7] = 0
	return values
}

fn test_insertion_sort() {
	values := sort_input()
	// guide:sort
	mut p := jaggame.new_program()
	input := p.table_i16('input', values)
	data := p.array_i16('data', 32)
	sort := p.func('sort', [], .void)
	mut c := p.define(sort)
	i := c.local_u16('i')
	j := c.local_u16('j')
	key := c.local_i16('key')
	c.for_(i, 0, 32)
	c.set(data.at(i), input.at(i))
	c.end()
	c.for_(i, 1, 32)
	c.set(key, data.at(i))
	c.set(j, i)
	// both() does not look at data.at(j - 1) once j is 0.
	c.while_(j.gt(0).both(data.at(j.sub(1)).gt(key)))
	c.set(data.at(j), data.at(j.sub(1)))
	c.dec(j)
	c.end()
	c.set(data.at(j), key)
	c.end()
	// guide:end
	run := run_both_ways(p, sort)!
	mut expected := values.map(i64(it))
	expected.sort()
	assert run.values('data', 32) == expected
}

fn test_primes() {
	limit := 2000
	// guide:primes
	mut p := jaggame.new_program()
	composite := p.array('composite', .bool, limit)
	primes := p.array_u16('primes', 400)
	count := p.u16('count')
	sieve := p.func('sieve', [], .void)
	mut c := p.define(sieve)
	n := c.local_u16('n')
	multiple := c.local_u32('multiple')
	c.for_(n, 2, limit)
	c.if_(composite.at(n).invert())
	c.set(primes.at(count), n)
	c.inc(count)
	// n * n would wrap as a u16: square it as a u32.
	c.set(multiple, n)
	c.set(multiple, multiple.mul(n))
	c.while_(multiple.lt(limit))
	c.set(composite.at(multiple), true)
	c.add_to(multiple, n)
	c.end()
	c.end()
	c.end()
	// guide:end
	run := run_both_ways(p, sieve)!
	mut expected := []i64{}
	for k in 2 .. limit {
		mut prime := true
		for d := 2; d * d <= k; d++ {
			if k % d == 0 {
				prime = false
				break
			}
		}
		if prime {
			expected << k
		}
	}
	assert run.it.value('count')! == expected.len
	assert run.values('primes', expected.len) == expected
}

fn sine_table() []f64 {
	mut sines := []f64{}
	for k in 0 .. 256 {
		sines << math.sin(2 * math.pi * f64(k) / 256)
	}
	return sines
}

fn test_a_sine_walk() {
	// guide:sine
	mut p := jaggame.new_program()
	sines := p.table_fix('sines', sine_table())
	path := p.array_fix('path', 64)
	angle := p.u16('angle') // 256 steps to a turn in the high byte
	x := p.fix('x')
	speed := p.fix('speed', 2.5)
	walk := p.func('walk', [], .void)
	mut c := p.define(walk)
	step := c.local_u8('step')
	c.for_(step, 0, 64)
	c.add_to(angle, 1000) // wraps around at 65536
	c.add_to(x, sines.at(angle.shr(8)).mul(speed))
	c.set(path.at(step), x)
	c.end()
	// guide:end
	run := run_both_ways(p, walk)!
	// The same in V: 16.16 values as integers, products rounded down.
	raw := sine_table().map(jaggame.fix_raw(it))
	mut a := 0
	mut position := i64(0)
	mut expected := []i64{}
	for _ in 0 .. 64 {
		a = (a + 1000) & 0xffff
		position += (raw[a >> 8] * jaggame.fix_raw(2.5)) >> 16
		expected << position
	}
	assert run.values('path', 64) == expected
}

fn test_records_and_functions_calling_functions() {
	// guide:records
	mut p := jaggame.new_program()
	guard := p.record('Guard', [jaggame.Field{'x', .fix}, jaggame.Field{'y', .fix},
		jaggame.Field{'state', .u8}, jaggame.Field{'timer', .u16}])
	guards := p.array_of('guards', guard, 8)
	nearest := p.u8('nearest')

	clamp := p.func('clamp', [jaggame.Param{'v', .fix}, jaggame.Param{'lo', .fix},
		jaggame.Param{'hi', .fix}], .fix)
	mut c := p.define(clamp)
	c.ret(clamp.arg('v').max(clamp.arg('lo')).min(clamp.arg('hi')))

	distance := p.func('distance', [jaggame.Param{'dx', .fix},
		jaggame.Param{'dy', .fix}], .fix)
	c = p.define(distance)
	c.ret(distance.arg('dx').abs().add(distance.arg('dy').abs()))

	// step moves guard i right until x is 100, then left until it is 0.
	step := p.func('step', [jaggame.Param{'i', .u8}], .void)
	c = p.define(step)
	g := guards.at(step.arg('i'))
	c.if_(g.field('state').eq(0))
	c.set(g.field('x'), clamp.call(g.field('x').add(1.5), 0, 100))
	c.if_(g.field('x').eq(100))
	c.set(g.field('state'), 1)
	c.end()
	c.else_()
	c.set(g.field('x'), clamp.call(g.field('x').sub(0.75), 0, 100))
	c.if_(g.field('x').eq(0))
	c.set(g.field('state'), 0)
	c.end()
	c.end()
	c.inc(g.field('timer'))

	// find is the guard nearest to (px, py).
	find := p.func('find', [jaggame.Param{'px', .fix}, jaggame.Param{'py', .fix}], .u8)
	c = p.define(find)
	i := c.local_u8('i')
	best := c.local_fix('best')
	d := c.local_fix('d')
	c.set(best, 32767)
	c.for_(i, 0, 8)
	c.set(d, distance.call(guards.at(i).field('x').sub(find.arg('px')),
		guards.at(i).field('y').sub(find.arg('py'))))
	c.if_(d.lt(best))
	c.set(best, d)
	c.set(nearest, i)
	c.end()
	c.end()
	c.ret(nearest)

	main := p.func('main', [], .void)
	found := p.u8('found')
	c = p.define(main)
	k := c.local_u8('k')
	c.for_(k, 0, 8)
	c.set(guards.at(k).field('x'), k.mul(12))
	c.set(guards.at(k).field('y'), k.mul(5))
	c.end()
	c.repeat(150)
	c.for_(k, 0, 8)
	c.call(step, k)
	c.end()
	c.end()
	c.set(found, find.call(50, 20))
	// guide:end
	run := run_both_ways(p, main)!

	// The same in V.
	one := i64(jaggame.fix_one)
	mut xs := []i64{len: 8, init: index * 12 * one}
	ys := []i64{len: 8, init: index * 5 * one}
	mut states := []int{len: 8}
	for _ in 0 .. 150 {
		for n in 0 .. 8 {
			if states[n] == 0 {
				xs[n] = math.min(math.max(xs[n] + one * 3 / 2, 0), 100 * one)
				if xs[n] == 100 * one {
					states[n] = 1
				}
			} else {
				xs[n] = math.min(math.max(xs[n] - one * 3 / 4, 0), 100 * one)
				if xs[n] == 0 {
					states[n] = 0
				}
			}
		}
	}
	mut want := 0
	mut closest := i64(32767) * one
	for n in 0 .. 8 {
		dist := math.abs(xs[n] - 50 * one) + math.abs(ys[n] - 20 * one)
		if dist < closest {
			closest = dist
			want = n
		}
	}
	for n in 0 .. 8 {
		assert run.it.field('guards', n, 'x')! == xs[n]
		assert run.it.field('guards', n, 'state')! == states[n]
		assert run.it.field('guards', n, 'timer')! == 150
	}
	assert run.it.value('found')! == want
}
