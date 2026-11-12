// MAW: a tunnel flyer for the Atari Jaguar, written as a V program that
// assembles itself. Run it to produce the image:
//
//     v run demos/maw            # writes demos/maw.jag
//
// The GPU draws the tunnel, the DSP is the synthesizer, the 68000 runs the
// game. render.v, sound.v and game.v hold the three programs; art.v
// computes every picture and table.
module main

import os
import jagkit

const message = '                MAW ...  A GAME FOR THE ATARI JAGUAR, ASSEMBLED BY A V PROGRAM.  THE GPU DRAWS THE TUNNEL, THE DSP PLAYS THE TUNE AND THE 68000 KEEPS THE SCORE.  NO ASSEMBLER WAS INVOLVED: EVERY BYTE OF THIS IMAGE WAS COMPUTED.  GREETINGS TO EVERYONE STILL WRITING CODE FOR MACHINES THAT ARE NO LONGER MADE ...'

fn main() {
	output := if os.args.len > 1 { os.args[1] } else { 'demos/maw.jag' }
	built := build() or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(output, built.image) or {
		eprintln(err)
		exit(1)
	}
	println('${output}: ${built.image.len} bytes')
}

// whole_longs pads a program to a multiple of four bytes, for copying.
fn whole_longs(code []u8) []u8 {
	mut padded := code.clone()
	for padded.len % 4 != 0 {
		padded << 0
	}
	return padded
}

// Built is the finished image and where its 68000 labels ended up.
struct Built {
	image   []u8
	symbols map[string]u32
}

// build assembles the three programs and their data into one image.
fn build() !Built {
	mut gpu := renderer()
	gpu_code := whole_longs(gpu.assemble()!)
	mut dsp := synthesizer()
	dsp_code := whole_longs(dsp.assemble()!)
	if gpu_code.len > jagkit.gpu_ram_size || dsp_code.len > jagkit.dsp_ram_size {
		return error('a RISC program does not fit its RAM')
	}

	mut m := jagkit.new_m68k(load_address)
	mut g := Game{
		m:       m
		mailbox: gpu.address_of('shared')
		voices:  dsp.address_of('voices')
	}
	g.start_up(gpu_code.len / 4, dsp_code.len / 4, dsp.address_of('start'))
	g.frame_interrupt()
	g.refresh_list()
	g.cycle_colours()
	g.music()
	g.read_pad()
	g.states()
	g.gates()
	g.paint_gate()
	g.scroller()
	g.text_routines()
	g.variables()

	m.label('message')
	m.text(message)
	m.label('font')
	m.bytes(font_bitmap())
	m.label('bounce')
	m.bytes(bounce(64, 10))
	m.label('rainbow')
	m.bytes(jagkit.big_endian16(rainbow(64)))
	m.label('sway')
	m.bytes(sway())
	m.label('kick_sweep')
	m.bytes(jagkit.big_endian32(kick_sweep()))
	m.label('bass_line')
	m.bytes(jagkit.big_endian32(bass_line()))
	m.label('lead_line')
	m.bytes(jagkit.big_endian32(lead_line()))
	m.label('gpu_program')
	m.bytes(gpu_code)
	m.label('dsp_program')
	m.bytes(dsp_code)
	m.label('tunnel_table')
	m.bytes(jagkit.big_endian32(tunnel_table()))
	m.label('palettes')
	m.bytes(jagkit.big_endian16(palettes()))

	// The wall, a copy of the rings each gate's lane covers, the lane and
	// the frames of lightning.
	texture := wall_texture()
	m.label('texture')
	m.bytes(texture)
	for i, ring in gate_rows {
		m.label('wall_${i}')
		m.bytes(texture[(ring - lane_rings) * 256..ring * 256])
	}
	m.label('lane')
	m.bytes(lane_texture())
	m.label('sparks')
	for frame in 0 .. spark_frames {
		m.bytes(spark_texture(frame))
	}
	m.align(8)
	m.label('zap')
	m.bytes(zap())

	title := logo('MAW', 8)
	// Sprites: the ship level and leaning both ways, then the explosion.
	mut sprites := [ship(0), ship(1), ship(-1)]
	for frame in 0 .. blast_frames {
		sprites << blast(frame)
	}
	m.align(8)
	m.label('logo')
	m.bytes(jagkit.big_endian16(title.pixels))
	for i, sprite in sprites {
		m.align(8)
		m.label('sprite_${i}')
		m.bytes(jagkit.big_endian16(sprite.pixels))
	}

	// One set of display lists for each television standard: a list for
	// every scene, for each of the two tunnel buffers.
	for video in [jagkit.ntsc, jagkit.pal] {
		left := (video.width - 320) / 2
		top := video.vdb + (video.height - 240) / 2 * 2
		scroller_top := top + 2 * 196
		ship_y := top + 2 * 208 // the middle of the ship
		text := jagkit.Bitmap{
			x:           left
			y:           top
			width:       text_columns * 8
			height:      text_rows * 8
			data:        text_address
			depth:       .bpp1
			transparent: true
		}
		// The same text one pixel down and right, in black.
		shadow := jagkit.Bitmap{
			...text
			x:       left + 1
			y:       top + 2
			palette: 4
		}
		mut names := []string{}
		for scene in 0 .. scene_count {
			for b, buffer in [buffer_a, buffer_b] {
				mut bitmaps := [
					jagkit.Bitmap{
						x:      left
						y:      top
						width:  tunnel_width
						height: tunnel_height
						data:   buffer
						hscale: 2
						vscale: 2
					},
				]
				if scene == scene_title / 8 {
					bitmaps << jagkit.Bitmap{
						x:           left + (320 - title.width) / 2
						y:           top + 2 * 28
						width:       title.width
						height:      title.height
						data:        m.address_of('logo')
						transparent: true
					}
				} else if scene < scene_wreck / 8 {
					sprite := sprites[scene - scene_ship / 8]
					bitmaps << jagkit.Bitmap{
						x:           left + (320 - sprite.width) / 2
						y:           ship_y - sprite.height
						width:       sprite.width
						height:      sprite.height
						data:        m.address_of('sprite_${scene - scene_ship / 8}')
						transparent: true
					}
				}
				if scene >= scene_blast / 8 && scene < scene_wreck / 8 {
					// Lightning around the wreck.
					bitmaps << jagkit.Bitmap{
						x:           left + (320 - zap_size) / 2
						y:           ship_y - zap_size
						width:       zap_size
						height:      zap_size
						data:        m.address_of('zap')
						depth:       .bpp1
						palette:     6
						transparent: true
					}
				}
				bitmaps << shadow
				bitmaps << text
				if scene == scene_title / 8 {
					bitmaps << jagkit.Bitmap{
						x:           left
						y:           scroller_top
						width:       (strip_bytes - 8) * 8
						stride:      strip_bytes * 8
						height:      strip_lines
						data:        strip_address
						depth:       .bpp1
						palette:     2
						transparent: true
						hscale:      2.5
						vscale:      2.5
					}
				}
				mut bytes := jagkit.object_list(list_address, video, bitmaps)!.bytes.clone()
				for bytes.len < list_bytes {
					bytes << 0
				}
				name := 'list_${video.name}_${scene}_${b}'
				m.label(name)
				m.bytes(bytes)
				names << name
			}
		}
		m.label('profile_${video.name.to_lower()}')
		m.word(video.hdb)
		m.word(video.hde)
		m.word(video.vdb)
		m.word(video.vde | 1)
		m.word(scroller_top)
		m.word(0)
		for name in names {
			m.long_label(name)
		}
	}

	payload := m.assemble()!
	return Built{
		image:   jagkit.jag_image(load_address, m.address_of('entry'), payload)
		symbols: m.symbols()
	}
}
