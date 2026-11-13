module jaggame

import jagkit

// build checks the game, compiles it with the runtime and returns the
// image. The game can be built once. Every mistake in the description of
// the game (and every type error in its code) is reported together.
pub fn (mut g Game) build() !Image {
	if g.built {
		return error('game: a game can be built once')
	}
	g.built = true
	g.define_runtime()
	g.check_art()
	layout := g.layout()

	mut dsp := jagkit.synth()
	mut dsp_code := []u8{}
	if g.sounds {
		dsp_code = dsp.assemble()!
		for dsp_code.len % 4 != 0 {
			dsp_code << 0
		}
	}
	voices := if g.sounds { dsp.address_of('voices') } else { u32(0) }

	mut m := jagkit.new_m68k(load_address)
	g.emit_start(mut m, layout, dsp_code.len / 4,
		if g.sounds { dsp.address_of('start') } else { 0 })
	g.emit_handler(mut m, voices)
	g.emit_read_pad(mut m)
	g.emit_text_routines(mut m, layout)
	g.emit_build_list(mut m)
	low := g.p.emit_lowered(mut m)!

	g.emit_art_data(mut m)
	g.emit_runtime_data(mut m, dsp_code)!
	g.emit_profiles(mut m, layout)!
	payload := m.assemble() or { return error('jaggame compiler bug: ${err.msg()}') }

	mut regions := [
		jagkit.Region{'stack and vectors', 0, int(load_address)},
		jagkit.Region{'image', load_address, payload.len},
		jagkit.Region{'display list 0', layout.lists[0], layout.list_bytes},
		jagkit.Region{'display list 1', layout.lists[1], layout.list_bytes},
	]
	for i, t in g.texts {
		regions << jagkit.Region{'text layer `${t.name}`', layout.text[i], t.columns * t.rows * 8}
	}
	jagkit.check_regions(regions)!
	return Image{
		low:     low
		bytes:   jagkit.jag_image(load_address, m.address_of('rt.start'), payload)
		payload: payload
		symbols: m.symbols()
	}
}

// check_art makes sure the pictures and the palette agree.
fn (mut g Game) check_art() {
	mut deepest := -1
	for a in g.arts {
		if a.bits == 8 {
			for px in a.pixels {
				if int(px) > deepest {
					deepest = int(px)
				}
			}
		}
	}
	room := 256 - 2 * g.texts.len
	if deepest >= 0 && g.palette.len == 0 {
		g.problem('there is a palette picture but no palette; call palette() with the colours')
	}
	if g.palette.len > room {
		g.problem('the palette has ${g.palette.len} colours; with ${g.texts.len} text layers there is room for ${room}')
	}
	if deepest >= g.palette.len && g.palette.len > 0 {
		g.problem('a palette picture uses colour ${deepest}, but the palette has ${g.palette.len}')
	}
}

// emit_runtime_data writes the variables the machine code keeps for itself,
// the palette, the font and the synthesizer.
fn (g &Game) emit_runtime_data(mut m jagkit.M68k, dsp_code []u8) ! {
	m.align(4)
	for name in ['rt.left', 'rt.top', 'rt.back', 'rt.front', 'rt.back_template', 'rt.front_template',
		'rt.template_0', 'rt.template_1'] {
		m.label(name)
		m.long(0)
	}
	if g.arts.len == 0 {
		m.label('rt.arts') // the table is empty; the label must exist
		m.bytes([]u8{len: 32})
	}
	m.label('rt.palette')
	for c in g.palette {
		m.word(int(c))
	}
	m.align(4)
	m.label('rt.dsp_program')
	m.bytes(dsp_code)
	m.label('rt.font')
	m.bytes(jagkit.font_8x8())
	m.align(4)
}
