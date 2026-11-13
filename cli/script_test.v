module cli

import jerry

fn test_press_defaults_to_six_frames() {
	press := parse_press('b@600')!
	assert press.button == jerry.Button.b
	assert press.first == 600
	assert press.last == 605
}

fn test_press_takes_a_length() {
	press := parse_press('Left@1500+60')!
	assert press.button == jerry.Button.left
	assert press.first == 1500
	assert press.last == 1559
}

fn test_malformed_presses_are_rejected() {
	for text in ['b', 'b@', 'fire@10', 'a@10+0'] {
		parse_press(text) or { continue }
		assert false, '"${text}" should not parse'
	}
}

fn test_a_press_script_takes_lines_spaces_and_comments() {
	text := '# the robot\nb@600+10  # start\n\nleft@700+30 up@710\n'
	presses := parse_presses(text, 'run.press')!
	assert presses.map(it.str()) == ['b@600+10', 'left@700+30', 'up@710+6']
}

fn test_a_bad_line_is_named() {
	parse_presses('a@1\n\nfire@10\n', 'run.press') or {
		assert err.msg() == 'run.press:3: unknown button "fire"'
		return
	}
	assert false, 'the script should not parse'
}

fn test_a_frame_must_be_a_number() {
	for text in ['a@x', 'a@10+y', 'a@-3', 'a@10+'] {
		parse_press(text) or { continue }
		assert false, '"${text}" should not parse'
	}
}

fn test_a_pad_log_becomes_presses_that_read_back() {
	a := u32(1) << u32(jerry.Button.a)
	one := u32(1) << u32(jerry.Button.one)
	log := [u32(0), a, a, a | one, one, 0, a]
	presses := presses_of(log)
	assert presses.map(it.str()) == ['a@1+3', '1@3+2', 'a@6+1']
	assert parse_presses(script_of(presses), 'log')!.map(it.str()) == presses.map(it.str())
}
