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
