module jaggame

import jaggame.emulated

fn smoke_game() !Image {
	mut g := new_game(Config{ sprites: 4, layers: 2 })
	pixels := []u16{len: 16 * 16, init: cry(255, 128, 0)}
	g.art_cry('box', 16, 16, 1, pixels)
	mut c := g.define_init()
	mut s := g.sprite(0)
	s.put(mut c, 'box', 100, 50, 0)
	return g.build()!
}

fn test_smoke() {
	img := smoke_game() or { panic(err) }
	mut p := emulated.boot(img.bytes, false) or { panic(err) }
	p.frames(5)
	ram := p.m.ram
	println('frame ${img.value(ram, 'frame')!}')
	front := p.peek32(img.symbols['rt.front'])
	println('front ${front:x}')
	for o in p.list_objects(front) {
		println('${o}')
	}
	pic := p.picture()
	box := pic.bounds(0, 0, pic.width, pic.height, fn (px u32) bool {
		return px != 0
	})
	println('${pic.width}x${pic.height} ${box}')
}
