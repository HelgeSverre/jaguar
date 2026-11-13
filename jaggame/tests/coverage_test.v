module main

import os

// Every public name in docs/jaggame/reference.md must be used by GHOSTGRID's
// game code, or by a test (jaggame's own, hello2's, GHOSTGRID's, or the
// robot's), or be in the short list below of names that only the runtime's
// own routines use, with the reason. This is the machine-checked half of the
// feature checklist in design.md: a feature that nothing uses fails here.

// internal is what no game and no test names, and why it is still exercised.
const internal = {
	'asm':            'emits machine code for the runtime: used by every runtime routine; games should not need it'
	'native':         'a machine routine with an interpreter twin: used by the tile queries, the line probes, the digits of a number and the sight walk, each tested on both sides'
	'native_ret':     'the same, for a routine with a result'
	'AsmFn':          'the type of the code `asm` and `native` take'
	'NativeFn':       'the type of the twin `native` takes'
	'emit':           'compiles the program into the image: called by `plain_image` and `build`, which every test calls'
	'peek8':          'a byte of memory: `peek16` and `peek32` are built on it'
	'Art':            'the handle `art_cry` and `png_pal` return'
	'Tileset':        'the handle `tileset` returns'
	'BackdropParams': 'the block `backdrop_params` returns, tested through the GPU mailbox'
	'Picture':        'the frame `Player.picture` returns, which every picture test reads'
}

// word_in tells whether a name occurs as a whole word in a text.
fn word_in(name string, text string) bool {
	mut at := 0
	for {
		i := text.index_after(name, at) or { return false }
		before := if i == 0 { ` ` } else { text[i - 1] }
		after := if i + name.len >= text.len { ` ` } else { text[i + name.len] }
		word := fn (c u8) bool {
			return c.is_alnum() || c == `_`
		}
		if !word(before) && !word(after) {
			return true
		}
		at = i + name.len
	}
	return false
}

// public_names reads the names out of the reference.
fn public_names(reference string) []string {
	mut names := []string{}
	for line in reference.split('\n') {
		if !line.starts_with('| `') {
			continue
		}
		mut decl := line['| `'.len..].all_before('`')
		decl = decl.trim_string_left('pub ')
		mut name := ''
		if decl.starts_with('fn (') {
			name = decl.all_after(') ').all_before('(')
		} else if decl.starts_with('fn ') {
			name = decl['fn '.len..].all_before('(')
		} else {
			for kind in ['const ', 'struct ', 'enum ', 'type ', 'interface '] {
				if decl.starts_with(kind) {
					name = decl[kind.len..].all_before(' ').all_before('=')
				}
			}
		}
		if name != '' && name !in names {
			names << name
		}
	}
	return names
}

fn sources(dirs []string, tests bool) string {
	mut text := ''
	for dir in dirs {
		for path in os.walk_ext(dir, '.v') {
			is_test := path.ends_with('_test.v') || path.contains('/robot/')
				|| path.contains('/tests/')
			if is_test == tests {
				text += os.read_file(path) or { '' } + '\n'
			}
		}
	}
	return text
}

fn test_every_name_in_the_reference_is_used_by_the_game_or_a_test() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	reference := os.read_file(os.join_path(root, 'docs', 'jaggame', 'reference.md'))!
	names := public_names(reference)
	assert names.len > 250, 'the reference was read: ${names.len} names'
	game := sources([os.join_path(root, 'demos', 'ghostgrid')], false)
	mut tests := sources([os.join_path(root, 'demos', 'ghostgrid'),
		os.join_path(root, 'demos', 'hello2')], true)
	tests += sources([os.join_path(root, 'jaggame')], true)
	mut in_game := 0
	mut in_tests := 0
	mut only_internal := 0
	mut missing := []string{}
	for name in names {
		if word_in(name, game) {
			in_game++
		} else if word_in(name, tests) {
			in_tests++
		} else if name in internal {
			only_internal++
		} else {
			missing << name
		}
	}
	println('${names.len} names in the reference: ${in_game} used by GHOSTGRID, ${in_tests} more by tests, ${only_internal} used by the runtime itself and by no game or test')
	assert missing.len == 0, 'nothing uses: ${missing}'
}
