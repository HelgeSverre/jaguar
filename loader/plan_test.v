module loader

import loader.fixtures

fn samples() [][]u8 {
	text := fixtures.CoffSection{
		name:  '.text'
		addr:  0x4000
		data:  fixtures.nops(0x40)
		flags: fixtures.coff_text
	}
	bss := fixtures.CoffSection{
		name:  '.bss'
		addr:  0x6000
		size:  0x80
		flags: fixtures.coff_bss
	}
	return [
		fixtures.cartridge(0x2400, 0x04, 0x802000),
		byte_swapped(fixtures.cartridge(0x2400, 0x04, 0x802000)),
		fixtures.jagr_type2(0x5000, 0x3C, fixtures.nops(0x40)),
		fixtures.jagr_type3(0x5000, 0, 0x5000, fixtures.nops(0x40)),
		fixtures.Abs{
			text:      fixtures.nops(0x40)
			data:      fixtures.nops(0x10)
			bss:       0x20
			text_base: 0x802000
			data_base: 0x802040
			bss_base:  0x4000
		}.bytes(),
		fixtures.Gemdos{
			text: fixtures.nops(0x40)
		}.bytes(),
		fixtures.Coff{
			sections: [text, bss]
			entry:    0x4000
		}.bytes(),
		fixtures.program(0x5000, 0x1800),
		fixtures.program(0x802000, 0),
	]
}

fn test_same_bytes_and_options_give_the_same_plan() {
	options := [Options{}, Options{
		entry: 0x802002
	}, Options{
		format:    .raw_binary
		load_addr: 0x8000
	}]
	for image in samples() {
		for opts in options {
			first := plan(image, opts) or {
				assert refusal_message(image.clone(), opts) == err.msg()
				continue
			}
			second := plan(image.clone(), opts)!
			assert first == second
			assert first.describe() == second.describe()
		}
	}
}

fn refusal_message(image []u8, opts Options) string {
	plan(image, opts) or { return err.msg() }
	return 'no error'
}

fn test_every_sample_kind_is_detected() {
	kinds := samples().map(plan(it, Options{})!.kind)
	assert kinds == [ImageKind.cartridge, .cartridge, .jaguar_server, .jaguar_server, .dri_abs,
		.dri_abs, .coff, .raw_binary, .alpine_rom]
}

fn test_hashes_are_sha256_of_the_bytes() {
	p := plan('ab'.bytes().repeat(0x100), Options{})!
	q := plan('ab'.bytes().repeat(0x100), Options{ load_addr: 0x8000 })!
	assert p.original_hash == q.original_hash
	abcd := plan([u8(0x61), 0x62, 0x63, 0x64], Options{})!
	// sha256("abcd")
	assert abcd.original_hash == '88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589'
}

fn test_describe_shows_the_whole_plan() {
	text := plan(samples()[4], Options{})!.describe()
	for expected in ['kind: dri_abs (DRI ABS (0x601b))', 'entry: 0x802000', 'cart boot: yes',
		'ambiguous: no', 'text: 0x802000..0x80203f (64 bytes)', 'data: 0x802040..0x80204f (16 bytes)',
		'0x004000..0x00401f (32 bytes)', 'sha256: '] {
		assert text.contains(expected), expected
	}
	raw := plan(samples()[7], Options{})!.describe()
	for expected in ['kind: raw_binary (headerless)', 'ambiguous: yes', 'candidates:', 'notes:',
		'raw_binary at 0x005000, entry 0x005000, score '] {
		assert raw.contains(expected), expected
	}
	swapped := plan(samples()[1], Options{})!.describe()
	assert swapped.contains('sha256 normalized: ')
	assert swapped.contains('normalizations:\n  byte-swapped')
}

fn test_error_messages_carry_their_code() {
	plan([]u8{len: 64, init: 0xFF}, Options{}) or {
		assert err is LoadError
		assert err.msg().starts_with('blank_image: ')
		return
	}
	assert false
}

// check_invariants asserts what every returned plan promises.
fn check_invariants(p LoadPlan) {
	assert p.segments.len > 0
	assert p.entry & 1 == 0
	assert p.original_hash.len == 64
	assert p.normalized_hash.len == 64
	for s in p.segments {
		assert s.data.len > 0
		assert is_loadable(s.addr, u64(s.data.len))
	}
	for z in p.zero_fill {
		assert z.len > 0
		assert is_loadable(z.addr, u64(z.len))
	}
	assert p.describe().len > 0
}

// survives runs `plan` and checks that it returned a sound plan or a LoadError.
fn survives(image []u8, opts Options) {
	p := plan(image, opts) or {
		assert err is LoadError
		return
	}
	check_invariants(p)
}

fn test_truncations_never_panic() {
	for image in samples() {
		for cut in 0 .. 0x120 {
			if cut <= image.len {
				survives(image[..cut], Options{})
			}
		}
		for cut := 0x120; cut < image.len; cut += 0x55 {
			survives(image[..cut], Options{})
		}
	}
}

fn test_corrupted_headers_never_panic() {
	mut rng := fixtures.Rng{}
	extremes := [u8(0x00), 0x01, 0x7F, 0x80, 0xFE, 0xFF]
	for image in samples() {
		header := if image.len < 0x100 { image.len } else { 0x100 }
		for _ in 0 .. 400 {
			mut mutated := image.clone()
			for _ in 0 .. 1 + rng.below(4) {
				at := rng.below(header)
				mutated[at] = if rng.below(2) == 0 {
					extremes[rng.below(extremes.len)]
				} else {
					u8(rng.next())
				}
			}
			survives(mutated, Options{})
		}
		// The cartridge header lives at 0x400, beyond the common prefix.
		if image.len > 0x408 {
			for _ in 0 .. 200 {
				mut mutated := image.clone()
				mutated[0x400 + rng.below(8)] = u8(rng.next())
				survives(mutated, Options{})
			}
		}
	}
}

fn test_random_bytes_never_panic() {
	mut rng := fixtures.Rng{}
	magics := [[u8(0x60), 0x1A], [u8(0x60), 0x1B], [u8(0x01), 0x50],
		[u8(0x4E), 0xB9]]
	for round in 0 .. 600 {
		mut image := rng.bytes(rng.below(0x300))
		if image.len >= 0x20 && round % 2 == 0 {
			magic := magics[rng.below(magics.len)]
			image[0] = magic[0]
			image[1] = magic[1]
			if round % 4 == 0 {
				image[0x1C] = `J`
				image[0x1D] = `A`
				image[0x1E] = `G`
				image[0x1F] = `R`
				image[0x20] = 0
				image[0x21] = u8(2 + rng.below(2))
			}
		}
		survives(image, Options{})
	}
}

fn test_random_options_never_panic() {
	mut rng := fixtures.Rng{}
	kinds := [ImageKind.cartridge, .jaguar_server, .dri_abs, .coff, .alpine_rom, .raw_binary]
	addresses := [u32(0), 1, 0x4000, 0x1FFFFE, 0x200000, 0x7FFFFE, 0x800000, 0xDFFFFE, 0xE00000,
		0xF00000, 0xFFFFFFFE, 0xFFFFFFFF]
	for image in samples() {
		for _ in 0 .. 120 {
			survives(image, Options{
				format:    if rng.below(3) == 0 {
					?ImageKind(none)
				} else {
					kinds[rng.below(kinds.len)]
				}
				load_addr: if rng.below(2) == 0 {
					?u32(none)
				} else {
					addresses[rng.below(addresses.len)]
				}
				entry:     if rng.below(2) == 0 {
					?u32(none)
				} else {
					addresses[rng.below(addresses.len)]
				}
			})
		}
	}
}
