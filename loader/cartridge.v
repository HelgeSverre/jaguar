module loader

// Cartridge images are mapped byte for byte at 0x800000. The first 0x2000
// bytes are the boot/security area; inside it, at 0x400, sit four identical
// memory-configuration bytes (0x04 on nearly every released cartridge) and at
// 0x404 the big-endian start address. That pair is the recognition anchor.
//
// Two dump artifacts are undone before mapping, each recorded with its reason
// and both hashes: byte-swapped pairs, and a 0x200-byte header some copiers
// prepend. Neither is applied unless it is what makes the header valid.

const cart_header_offset = 0x400
const cart_boot_area_len = 0x2000
const cart_max_len = 0x600000
const copier_header_len = 0x200
const cart_default_entry = u32(0x802000)
// Bits 1..4 of the memory-configuration byte select ROM width and speed;
// every other bit is clear in a valid header.
const cart_config_mask = u8(0x1E)

// CartLayout says where a valid cartridge header was found and what it holds.
struct CartLayout {
	skip    int  // bytes of prepended header to strip
	swapped bool // byte pairs are exchanged
	config  u8   // memory-configuration byte
	entry   u32  // start address from 0x404
}

// find_cart_layout looks for the header as dumped, then byte-swapped, then
// behind a copier header, then both. The first valid reading wins, so an
// image that is already valid is never normalized.
fn find_cart_layout(image []u8) ?CartLayout {
	for skip in [0, copier_header_len] {
		for swapped in [false, true] {
			if layout := cart_layout_at(image, skip, swapped) {
				return layout
			}
		}
	}
	return none
}

// cart_layout_at validates the header of the payload starting at `skip`.
fn cart_layout_at(image []u8, skip int, swapped bool) ?CartLayout {
	if image.len - skip < cart_boot_area_len {
		return none
	}
	at := skip + cart_header_offset
	header := if swapped { byte_swapped(image[at..at + 8]) } else { image[at..at + 8] }
	config := header[0]
	if config & ~cart_config_mask != 0 || !all_bytes_are(header[..4], config) {
		return none
	}
	entry := word32(header, 4)
	if entry & 1 != 0 || !in_window(entry, 2, cart_base, cart_end) {
		return none
	}
	return CartLayout{skip, swapped, config, entry}
}

// plan_cartridge maps the (normalized) payload at 0x800000.
fn plan_cartridge(image []u8, layout CartLayout, opts Options) !Draft {
	reject_load_addr(opts, 'a cartridge')!
	mut d := Draft{
		kind:    .cartridge
		variant: 'memory config 0x${layout.config:02x}'
		entry:   layout.entry
	}
	stripped := image[layout.skip..]
	check_cart_size(stripped.len)!
	if layout.skip > 0 {
		d.normalizations << 'stripped ${hex32(u32(layout.skip))}-byte prepended header: the cartridge header at 0x400/0x404 is only valid behind it'
	}
	if layout.swapped {
		d.normalizations << 'byte-swapped: the cartridge header at 0x400/0x404 is only valid with byte pairs exchanged'
	}
	payload := if layout.swapped { byte_swapped(stripped) } else { stripped }
	if d.normalizations.len > 0 {
		d.normalized = payload
	}
	if u64(layout.entry) >= u64(cart_base) + u64(payload.len) {
		d.notes << 'entry ${hex32(layout.entry)} lies beyond the ${payload.len} image bytes; it relies on board mirroring'
	}
	d.segments << Segment{cart_base, payload, 'cart'}
	return d
}

// check_cart_size bounds an image to the 6 MiB cartridge window. Larger
// images need a mapper, which is an unsupported extension, not a truncation.
fn check_cart_size(len int) ! {
	if len > cart_max_len {
		return fail(.too_large,
			'cartridge image has ${len} bytes; the cartridge window holds ${cart_max_len} (6 MiB) and mappers are not supported')
	}
}

// has_erased_cart_header recognizes a cartridge dump whose whole boot area
// (and with it the header) reads 0xFF while code follows at 0x2000.
fn has_erased_cart_header(image []u8) bool {
	if image.len < cart_boot_area_len + 2 || image.len > cart_max_len {
		return false
	}
	return all_bytes_are(image[..cart_boot_area_len], 0xFF)
		&& is_plausible_opcode(word16(image, cart_boot_area_len))
}

// plan_erased_cartridge maps such a dump like any cartridge and starts it at
// the conventional 0x802000, since the header that would say so is gone.
fn plan_erased_cartridge(image []u8, opts Options) !Draft {
	reject_load_addr(opts, 'a cartridge')!
	return Draft{
		kind:     .cartridge
		variant:  'erased header'
		entry:    cart_default_entry
		segments: [Segment{cart_base, image, 'cart'}]
		notes:    [
			'the first ${hex32(cart_boot_area_len)} bytes (boot area and header) are erased to 0xff; entry assumed at the conventional ${hex32(cart_default_entry)}',
			'retail boot cannot authenticate this image; only direct boot can start it',
		]
	}
}

// plan_forced_cartridge maps an image the caller declares to be a cartridge.
// Without a valid header the caller must also supply the entry.
fn plan_forced_cartridge(image []u8, opts Options) !Draft {
	if layout := find_cart_layout(image) {
		return plan_cartridge(image, layout, opts)
	}
	reject_load_addr(opts, 'a cartridge')!
	check_cart_size(image.len)!
	entry := opts.entry or {
		return fail(.bad_header,
			'no valid cartridge header at 0x400/0x404; give an explicit entry to map the image anyway')
	}

	return Draft{
		kind:     .cartridge
		variant:  'headerless (forced)'
		entry:    entry
		segments: [Segment{cart_base, image, 'cart'}]
		notes:    ['mapped as a cartridge on request; no valid header at 0x400/0x404']
	}
}
