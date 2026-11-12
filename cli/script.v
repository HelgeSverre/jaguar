module cli

import jerry
import machine

// Press holds one controller button on port 0 over a range of frames.
struct Press {
	button jerry.Button
	first  int // first frame the button is held
	last   int // last frame the button is held
}

// parse_press reads `button@frame[+frames]`, e.g. `b@600+10`. Without a
// length the button is held for six frames.
fn parse_press(text string) !Press {
	name := text.all_before('@')
	timing := text.all_after('@')
	if !text.contains('@') || timing == '' {
		return error('press "${text}": expected button@frame[+frames]')
	}
	first := timing.all_before('+').int()
	length := if timing.contains('+') { timing.all_after('+').int() } else { 6 }
	if length < 1 {
		return error('press "${text}": length must be at least one frame')
	}
	return Press{
		button: parse_button(name)!
		first:  first
		last:   first + length - 1
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

// apply_presses sets the controller to what the script holds during `frame`.
fn apply_presses(mut m machine.Machine, presses []Press, frame int) {
	for press in presses {
		if frame == press.first {
			m.set_button(0, press.button, true)
		} else if frame == press.last + 1 {
			m.set_button(0, press.button, false)
		}
	}
}
