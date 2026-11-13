module cli

import os
import jerry
import machine

// Press holds one controller button on port 0 over a range of frames.
pub struct Press {
pub:
	button jerry.Button
	first  int // first frame the button is held
	last   int // last frame the button is held
}

// parse_press reads `button@frame[+frames]`, e.g. `b@600+10`. Without a
// length the button is held for six frames.
pub fn parse_press(text string) !Press {
	name := text.all_before('@')
	timing := text.all_after('@')
	if !text.contains('@') || timing == '' {
		return error('press "${text}": expected button@frame[+frames]')
	}
	frame_text := timing.all_before('+')
	length_text := if timing.contains('+') { timing.all_after('+') } else { '6' }
	if !is_count(frame_text) || !is_count(length_text) {
		return error('press "${text}": expected button@frame[+frames] with whole numbers')
	}
	first := frame_text.int()
	length := length_text.int()
	if length < 1 {
		return error('press "${text}": length must be at least one frame')
	}
	return Press{
		button: parse_button(name)!
		first:  first
		last:   first + length - 1
	}
}

// is_count reports whether a text is a whole number, digits only.
fn is_count(text string) bool {
	return text.len > 0 && text.bytes().all(it.is_digit())
}

// parse_presses reads a press script: presses in the form of `parse_press`,
// separated by spaces or line breaks, with `#` starting a comment that runs
// to the end of the line. An error names the source and the line.
pub fn parse_presses(text string, source string) ![]Press {
	mut presses := []Press{}
	for number, line in text.split_into_lines() {
		for word in line.all_before('#').fields() {
			presses << parse_press(word) or {
				return error('${source}:${number + 1}: ${err.msg()}')
			}
		}
	}
	return presses
}

// read_presses reads a press script from a file.
pub fn read_presses(path string) ![]Press {
	text := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	return parse_presses(text, path)
}

// presses_of turns a log of the first pad, the held buttons of every frame
// as bits of `jerry.Button`, into presses, in the order they go down.
pub fn presses_of(log []u32) []Press {
	mut presses := []Press{}
	mut since := []int{len: 32, init: -1}
	for frame in 0 .. log.len + 1 {
		held := if frame < log.len { log[frame] } else { u32(0) }
		for bit in 0 .. 32 {
			down := held & (u32(1) << bit) != 0
			if down && since[bit] < 0 {
				since[bit] = frame
			} else if !down && since[bit] >= 0 {
				presses << Press{
					button: unsafe { jerry.Button(bit) }
					first:  since[bit]
					last:   frame - 1
				}
				since[bit] = -1
			}
		}
	}
	presses.sort_with_compare(fn (a &Press, b &Press) int {
		return if a.first != b.first { a.first - b.first } else { int(a.button) - int(b.button) }
	})
	return presses
}

// str is a press in the form `parse_press` reads, `b@600+10`.
pub fn (p Press) str() string {
	return '${button_name(p.button)}@${p.first}+${p.last - p.first + 1}'
}

// script_of is presses as a script, one to a line.
pub fn script_of(presses []Press) string {
	return presses.map(it.str()).join('\n') + '\n'
}

fn button_name(button jerry.Button) string {
	return match button {
		.zero { '0' }
		.one { '1' }
		.two { '2' }
		.three { '3' }
		.four { '4' }
		.five { '5' }
		.six { '6' }
		.seven { '7' }
		.eight { '8' }
		.nine { '9' }
		else { button.str() }
	}
}

fn parse_button(name string) !jerry.Button {
	return match name.to_lower() {
		'up' { jerry.Button.up }
		'down' { jerry.Button.down }
		'left' { jerry.Button.left }
		'right' { jerry.Button.right }
		'a' { jerry.Button.a }
		'b' { jerry.Button.b }
		'c' { jerry.Button.c }
		'option' { jerry.Button.option }
		'pause' { jerry.Button.pause }
		'0' { jerry.Button.zero }
		'1' { jerry.Button.one }
		'2' { jerry.Button.two }
		'3' { jerry.Button.three }
		'4' { jerry.Button.four }
		'5' { jerry.Button.five }
		'6' { jerry.Button.six }
		'7' { jerry.Button.seven }
		'8' { jerry.Button.eight }
		'9' { jerry.Button.nine }
		'star' { jerry.Button.star }
		'hash' { jerry.Button.hash }
		else { error('unknown button "${name}"') }
	}
}

// hold_presses holds every button the script holds during `frame`, as after
// a host event let go of them all.
pub fn hold_presses(mut m machine.Machine, presses []Press, frame int) {
	for press in presses {
		if frame >= press.first && frame <= press.last {
			m.set_button(0, press.button, true)
		}
	}
}

// apply_presses sets the controller to what the script holds during `frame`.
pub fn apply_presses(mut m machine.Machine, presses []Press, frame int) {
	for press in presses {
		if frame == press.first {
			m.set_button(0, press.button, true)
		} else if frame == press.last + 1 {
			m.set_button(0, press.button, false)
		}
	}
}
