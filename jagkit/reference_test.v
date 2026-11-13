module jagkit

import os

// docs/jagkit-reference.md is written from the comments in this module:
//
//     JAGKIT_WRITE_REFERENCE=1 v test jagkit/reference_test.v
//
// This test fails when the file is out of date.

const reference_files = {
	'm68k.v':     'The 68000 assembler'
	'risc.v':     'The GPU and DSP assembler'
	'routines.v': 'Ready-made 68000 subroutines'
	'objects.v':  'Display lists'
	'image.v':    'Images, byte order and colour'
	'memory.v':   'Memory layout'
	'font.v':     'The font'
	'synth.v':    'The DSP synthesizer'
	'hardware.v': 'Hardware registers and video timing'
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
		is_public := line.starts_with('pub fn ') || line.starts_with('pub const ')
			|| line.starts_with('pub struct ') || line.starts_with('pub enum ')
		if is_public {
			mut signature := line.all_after('pub ').trim_right(' {')
			if signature.starts_with('const ') {
				// The value, with a trailing comment as the description.
				if signature.contains(' // ') {
					comment << signature.all_after(' // ')
					signature = signature.all_before(' // ')
				}
			}
			// The sixteen register constants are named in the comment on Ea.
			if !signature.ends_with('= Ea') {
				found << Entry{signature.trim_space(), comment.join(' ')}
			}
		}
		comment = []string{}
	}
	return found
}

fn reference() string {
	dir := os.dir(@FILE)
	mut out := ['# jagkit reference', '',
		'Every public name in `jagkit`, with the comment from its source. This file is generated: see `jagkit/reference_test.v`. The guide is [`jagkit.md`](jagkit.md).',
		'']
	for file, title in reference_files {
		source := os.read_file(os.join_path(dir, file)) or { panic(err) }
		out << '## ${title}'
		out << ''
		out << '`jagkit/${file}`'
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
	path := os.join_path(os.dir(@FILE), '..', 'docs', 'jagkit-reference.md')
	text := reference()
	if os.getenv('JAGKIT_WRITE_REFERENCE') != '' {
		os.write_file(path, text)!
	}
	assert os.read_file(path)! == text, 'run: JAGKIT_WRITE_REFERENCE=1 v test jagkit/reference_test.v'
}

fn test_every_public_name_has_a_comment() {
	dir := os.dir(@FILE)
	for file, _ in reference_files {
		for e in entries(os.read_file(os.join_path(dir, file))!) {
			// The register and bit constants explain themselves in groups.
			if e.signature.starts_with('const ') {
				continue
			}
			assert e.comment != '', '${file}: `${e.signature}` has no comment'
		}
	}
}
