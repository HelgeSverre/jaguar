// The sound of GHOSTGRID: a handful of effects and two tracks of music, both
// written for this game. The effects are described by pitch and length; the
// music is patterns of sixteen rows (an eighth of a bar each) in four
// channels: lead, harmony, bass and drums.
module main

import jaggame

// define_sounds declares the effects and the music.
fn (mut m Mission) define_sounds() {
	mut game := m.game
	// guide:gg_sfx
	// Footsteps are soft bursts of low noise; a run is louder. A knock is two
	// thuds. The tone voice has the stings: the more important a sound, the
	// higher its priority, and a sound cuts off one of lower or equal priority.
	game.sfx('step', jaggame.Sfx{
		noise:    true
		priority: 2
		volume:   700
		decay:    2
		steps:    [jaggame.SfxStep{150, 0.06}]
	})
	game.sfx('run', jaggame.Sfx{
		noise:    true
		priority: 3
		volume:   1300
		decay:    2
		steps:    [jaggame.SfxStep{220, 0.07}]
	})
	game.sfx('knock', jaggame.Sfx{
		noise:    true
		priority: 4
		volume:   2600
		decay:    3
		slide:    2
		steps:    [jaggame.SfxStep{300, 0.08}, jaggame.SfxStep{0, 0.05},
			jaggame.SfxStep{260, 0.1}]
	})
	game.sfx('spotted', jaggame.Sfx{
		priority: 6
		volume:   2200
		steps:    [jaggame.SfxStep{880, 0.07}, jaggame.SfxStep{1175, 0.07},
			jaggame.SfxStep{880, 0.07}, jaggame.SfxStep{1175, 0.14}]
	})
	game.sfx('caught', jaggame.Sfx{
		priority: 9
		volume:   2400
		decay:    5
		steps:    [jaggame.SfxStep{440, 0.15}, jaggame.SfxStep{330, 0.15},
			jaggame.SfxStep{220, 0.4}]
	})
	game.sfx('complete', jaggame.Sfx{
		priority: 9
		volume:   2000
		decay:    4
		steps:    [jaggame.SfxStep{523, 0.12}, jaggame.SfxStep{659, 0.12},
			jaggame.SfxStep{784, 0.12}, jaggame.SfxStep{1047, 0.4}]
	})
	game.sfx('menu_move', jaggame.Sfx{
		priority: 5
		volume:   1200
		decay:    3
		steps:    [jaggame.SfxStep{660, 0.05}]
	})
	game.sfx('menu_select', jaggame.Sfx{
		priority: 5
		volume:   1800
		decay:    3
		steps:    [jaggame.SfxStep{660, 0.05}, jaggame.SfxStep{990, 0.1}]
	})
	game.sfx('denied', jaggame.Sfx{
		priority: 5
		volume:   1500
		decay:    3
		steps:    [jaggame.SfxStep{180, 0.09}, jaggame.SfxStep{140, 0.12}]
	})
	game.sfx('chip', jaggame.Sfx{
		priority: 6
		volume:   1800
		decay:    3
		steps:    [jaggame.SfxStep{1320, 0.05}, jaggame.SfxStep{1760, 0.09}]
	})
	game.sfx('door', jaggame.Sfx{
		noise:    true
		priority: 6
		volume:   1500
		decay:    3
		slide:    3
		steps:    [jaggame.SfxStep{400, 0.12}, jaggame.SfxStep{250, 0.12}]
	})
	game.sfx('timeup', jaggame.Sfx{
		priority: 9
		volume:   2400
		decay:    5
		steps:    [jaggame.SfxStep{300, 0.2}, jaggame.SfxStep{300, 0.05},
			jaggame.SfxStep{200, 0.4}]
	})
	// guide:end

	// guide:gg_tracks
	// The calm track: slow, in D minor, a lot of air. The alert track: twice
	// as fast, pulsing on the root and its neighbour a semitone above, with
	// the drums driving. Each pattern is sixteen rows; `.` holds a note and
	// `-` stops it.
	game.track('calm', jaggame.Track{
		rows_per_second: 5.5
		patterns:        [
			jaggame.Pattern{
				lead:    'D4 . . . . . F4 . . . A3 . . . . .'
				harmony: 'A3 . . . . . . . G3 . . . . . . .'
				bass:    'D2 . . . . . . . . . A1 . . . . .'
				drums:   'k . . . . . . . . . . . h . . .'
			},
			jaggame.Pattern{
				lead:    'A4 . . . G4 . F4 . . . E4 . . . . .'
				harmony: 'D4 . . . . . . . C4 . . . . . . .'
				bass:    'D2 . . . . . . . Bb1 . . . . . . .'
				drums:   'k . . . . . h . k . . . . . h .'
			},
			jaggame.Pattern{
				lead:    'F4 . A4 . C5 . . . A4 . . . G4 . . .'
				harmony: 'F3 . . . . . . . E3 . . . . . . .'
				bass:    'F2 . . . . . . . A1 . . . . . . .'
				drums:   'k . h . . . h . k . h . . . h .'
			},
			jaggame.Pattern{
				lead:    'D5 . . . C5 . . . A4 . . . . . . -'
				harmony: 'A3 . . . . . . . F3 . . . . . . .'
				bass:    'G1 . . . . . . . A1 . . . . . . .'
				drums:   'k . . . . . . . h . . . . . . .'
			},
		]
		order:           [0, 1, 2, 1, 0, 1, 2, 3]
	})
	game.track('alert', jaggame.Track{
		rows_per_second: 11.0
		patterns:        [
			jaggame.Pattern{
				lead:    'E5 . E5 F5 E5 . B4 . C5 . C5 Db5 C5 . G4 .'
				harmony: 'E4 . E4 . E4 . E4 . F4 . F4 . F4 . F4 .'
				bass:    'E2 . E2 E2 . E2 E2 . F2 . F2 F2 . F2 F2 .'
				drums:   'k h s h k h s h k h s h k s k s'
			},
			jaggame.Pattern{
				lead:    'B4 . B4 C5 B4 . F4 . G4 . G4 Ab4 G4 . D4 .'
				harmony: 'B3 . B3 . B3 . B3 . C4 . C4 . C4 . C4 .'
				bass:    'B1 . B1 B1 . B1 B1 . C2 . C2 C2 . C2 C2 .'
				drums:   'k h s h k h s h k h s h s s s s'
			},
		]
		order:           [0, 0, 1, 0]
	})
	// guide:end
}
