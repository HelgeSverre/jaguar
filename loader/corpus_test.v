module loader

import os

// Plans every image in the directory named by VJAG_ROM_DIR and prints counts
// by kind and variant. Skipped when the variable is unset, so the suite never
// depends on a private corpus. Set VJAG_ROM_VERBOSE for one line per file.
//
// Two refusals are expected of real collections and do not fail the run:
// blank dumps, and Jaguar Server variants that are not specified.
fn test_corpus_images_all_get_a_plan() {
	dir := os.getenv('VJAG_ROM_DIR')
	if dir == '' {
		println('VJAG_ROM_DIR not set; corpus run skipped')
		return
	}
	verbose := os.getenv('VJAG_ROM_VERBOSE') != ''
	mut names := os.ls(dir) or { panic(err) }
	names.sort()
	mut by_variant := map[string]int{}
	mut raw_bases := map[string]int{}
	mut refused := map[string]int{}
	mut failures := 0
	mut total := 0
	for name in names {
		path := os.join_path(dir, name)
		if name.starts_with('.') || !os.is_file(path) {
			continue
		}
		total++
		image := os.read_bytes(path) or { panic(err) }
		p := plan(image, Options{}) or {
			code := if err is LoadError { err.code } else { ErrorCode.bad_header }
			if code in [.blank_image, .unsupported_variant] {
				refused['${code}']++
			} else {
				failures++
				println('FAILED (${image.len} bytes): ${err.msg()}')
			}
			if verbose {
				println('${name}: ${err.msg()}')
			}
			continue
		}
		by_variant['${p.kind} / ${p.variant}']++
		if p.ambiguous {
			raw_bases[hex32(p.segments[0].addr)]++
		}
		if verbose {
			clear := if p.notes.any(it.contains('not clearly ahead')) { ' UNCLEAR' } else { '' }
			println('${name}: ${p.kind} / ${p.variant} @${hex32(p.segments[0].addr)} entry ${hex32(p.entry)}${clear}')
			for c in p.candidates {
				println('    ${hex32(c.load_addr)} ${c.score}: ${c.reason}')
			}
		}
	}
	println('${total} images')
	print_counts('kind / variant', by_variant)
	print_counts('heuristic load base', raw_bases)
	print_counts('expected refusal', refused)
	assert failures == 0
}

fn print_counts(title string, counts map[string]int) {
	mut keys := counts.keys()
	keys.sort()
	for key in keys {
		println('${title}: ${key}: ${counts[key]}')
	}
}
