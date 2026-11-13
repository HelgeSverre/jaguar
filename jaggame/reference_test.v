module jaggame

import os

// docs/jaggame/reference.md is written from the comments in this module:
//
//     JAGGAME_WRITE_REFERENCE=1 v test jaggame/reference_test.v
//
// (`just reference` does it too.) This test fails when the file is out of
// date.

const reference_files = {
	'lang_types.v':        'Types'
	'lang_expr.v':         'Expressions'
	'lang_program.v':      'Programs: variables, tables, records and functions'
	'lang_code.v':         'Statements'
	'lang_check.v':        'Checking'
	'lang_print.v':        'Printing'
	'interp.v':            'The interpreter'
	'codegen.v':           'The code generator'
	'image.v':             'Plain images'
	'rt_game.v':           'The runtime: games'
	'rt_sprites.v':        'The runtime: sprites and animations'
	'assets_png.v':        'Assets: PNG import'
	'assets_canvas.v':     'Assets: drawing pictures for a game'
	'assets_map.v':        'Assets: tile sets, legends and rooms'
	'rt_tiles.v':          'The runtime: the tile layer, rooms and the camera'
	'rt_collide.v':        'The runtime: collision'
	'rt_text.v':           'The runtime: text'
	'rt_pad.v':            'The runtime: the pad'
	'rt_time.v':           'The runtime: timers'
	'rt_scenes.v':         'The runtime: scenes'
	'rt_menu.v':           'The runtime: menus'
	'rt_sound.v':          'The runtime: sound and music'
	'rt_build.v':          'The runtime: building a game'
	'rt_interp.v':         'The runtime: running a game in the interpreter'
	'emulated/emulated.v': 'Running images in the emulator (module jaggame.emulated)'
	'emulated/player.v':   'Driving a machine in a test (module jaggame.emulated)'
}

struct Entry {
	signature string
	comment   string
}

// entries collects the public declarations of a file with the comment
// above each.
fn entries(source string) []Entry {
	mut found := []Entry{}
	mut comment := []string{}
	for line in source.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('//') {
			comment << trimmed.trim_left('/').trim_space()
			continue
		}
		if trimmed.starts_with('@[') {
			continue
		}
		is_public := line.starts_with('pub fn ') || line.starts_with('pub const ')
			|| line.starts_with('pub struct ') || line.starts_with('pub enum ')
			|| line.starts_with('pub type ')
		if is_public {
			found << Entry{line.all_after('pub ').trim_right(' {').trim_space(), comment.join(' ')}
		}
		comment = []string{}
	}
	return found
}

// declared_name is the name a declaration introduces: `add` in
// `fn (a Expr) add(b Val) Expr`.
fn declared_name(signature string) string {
	mut rest := signature
	if rest.starts_with('fn (') {
		rest = rest.all_after(') ')
	} else {
		rest = rest.all_after(' ')
	}
	return rest.all_before('(').all_before(' ').trim_space()
}

fn reference() string {
	dir := os.dir(@FILE)
	mut out := ['# jaggame reference', '',
		'Every public name in `jaggame`, with the comment from its source. This file is generated: see `jaggame/reference_test.v`. The guide is [`guide.md`](guide.md); the design is [`design.md`](design.md).',
		'']
	for file, title in reference_files {
		source := os.read_file(os.join_path(dir, file)) or { panic(err) }
		out << '## ${title}'
		out << ''
		out << '`jaggame/${file}`'
		out << ''
		out << '| Declaration | |'
		out << '|---|---|'
		for e in entries(source) {
			out << '| `${e.signature.replace('|', '\\|')}` | ${e.comment.replace('|', '\\|')} |'
		}
		out << ''
	}
	return out.join('\n')
}

fn test_the_reference_is_up_to_date() {
	path := os.join_path(os.dir(@FILE), '..', 'docs', 'jaggame', 'reference.md')
	text := reference()
	if os.getenv('JAGGAME_WRITE_REFERENCE') != '' {
		os.write_file(path, text)!
	}
	assert os.read_file(path)! == text, 'run: JAGGAME_WRITE_REFERENCE=1 v test jaggame/reference_test.v'
}

fn test_every_public_name_has_a_comment() {
	dir := os.dir(@FILE)
	for file, _ in reference_files {
		for e in entries(os.read_file(os.join_path(dir, file))!) {
			assert e.comment != '', '${file}: `${e.signature}` has no comment'
			name := declared_name(e.signature)
			assert e.comment.starts_with(name), '${file}: the comment on `${e.signature}` should start with `${name}`'
		}
	}
}
