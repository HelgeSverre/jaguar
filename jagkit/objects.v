module jagkit

// Depth is the pixel size of a bitmap object. Up to 8 bits a pixel selects
// a colour from the palette; 16 bits are a colour themselves.
pub enum Depth {
	bpp1
	bpp2
	bpp4
	bpp8
	bpp16
}

// bits is the number of bits per pixel.
pub fn (d Depth) bits() int {
	return 1 << int(d)
}

// Bitmap describes one picture for the object processor.
pub struct Bitmap {
pub:
	x           int // pixels from the left edge of the display
	y           int // half-lines from the top of the frame
	width       int // pixels shown per line; must fill whole 64-bit phrases
	height      int // lines of image data
	data        u32 // address of the pixels; a multiple of 8
	depth       Depth = .bpp16
	stride      int  // pixels from one line to the next; 0 means `width`
	palette     int  // base colour for depths below 8 bits; even
	transparent bool // colour 0 is not drawn
	hscale      f64  // horizontal magnification; 0 means unscaled
	vscale      f64  // vertical magnification; 0 means unscaled
}

// ObjectList is a display list ready to be copied to its address.
pub struct ObjectList {
pub:
	base    u32
	bytes   []u8
	offsets []int // byte offset of each bitmap's first phrase
}

const object_slot = 32 // scaled objects must sit on a four-phrase boundary
const first_slot = 32
const stop_offset = 16

// object_list lays out a display list for the address `base`, which must be
// a multiple of 32. The object processor rewrites the list while it draws,
// so a program copies a fresh one into place every frame.
//
// The list starts with two branches that send the object processor to a
// stop object on the lines outside the display.
pub fn object_list(base u32, video Video, bitmaps []Bitmap) !ObjectList {
	if base % object_slot != 0 {
		return error('object list address 0x${base:06x} is not a multiple of ${object_slot}')
	}
	stop := base + stop_offset
	mut phrases := []u64{len: (first_slot + bitmaps.len * object_slot) / 8}
	phrases[0] = branch(.after, video.vde, stop)
	phrases[1] = branch(.after, video.vdb - 1, base + first_slot)
	phrases[2] = 4 // stop
	mut offsets := []int{}
	for i, b in bitmaps {
		offset := first_slot + i * object_slot
		link := if i + 1 < bitmaps.len { base + u32(offset + object_slot) } else { stop }
		encoded := b.encode(link)!
		for j, phrase in encoded {
			phrases[offset / 8 + j] = phrase
		}
		offsets << offset
	}
	mut bytes := []u8{cap: phrases.len * 8}
	for p in phrases {
		for shift := 56; shift >= 0; shift -= 8 {
			bytes << u8(p >> u32(shift))
		}
	}
	return ObjectList{
		base:    base
		bytes:   bytes
		offsets: offsets
	}
}

enum BranchWhen {
	on     // the line is YPOS
	before // the line comes before YPOS
	after  // the line comes after YPOS
}

fn branch(when BranchWhen, ypos int, target u32) u64 {
	return u64(3) | (u64(ypos & 0x7ff) << 3) | (u64(when) << 14) | (u64(target >> 3) << 24)
}

// encode returns the two phrases of a bitmap, or three when it is scaled.
fn (b Bitmap) encode(link u32) ![]u64 {
	bits := b.depth.bits()
	stride := if b.stride == 0 { b.width } else { b.stride }
	if b.width * bits % 64 != 0 || stride * bits % 64 != 0 {
		return error('a ${b.width}-pixel line at ${bits} bits does not fill whole phrases')
	}
	if b.data % 8 != 0 {
		return error('bitmap data at 0x${b.data:06x} is not on a phrase boundary')
	}
	if b.height < 1 || b.height > 1023 || b.palette % 2 != 0 || b.palette < 0 || b.palette > 254 {
		return error('bitmap height or palette out of range')
	}
	scaled := b.hscale != 0 || b.vscale != 0
	kind := if scaled { u64(1) } else { u64(0) }
	first := kind | (u64(b.y & 0x7ff) << 3) | (u64(b.height) << 14) | (u64(link >> 3) << 24) | (u64(b.data >> 3) << 43)
	mut second := u64(b.x & 0xfff) | (u64(b.depth) << 12) | (u64(1) << 15) | (u64(stride * bits / 64) << 18) | (u64(b.width * bits / 64) << 28) | (u64(b.palette >> 1) << 38)
	if b.transparent {
		second |= u64(1) << 47
	}
	if !scaled {
		return [first, second]
	}
	h := fixed_3_5(if b.hscale == 0 { 1.0 } else { b.hscale })!
	v := fixed_3_5(if b.vscale == 0 { 1.0 } else { b.vscale })!
	// The remainder starts at 1.0, so the first source line is consumed
	// after its share of display lines.
	return [first, second, h | (v << 8) | (u64(0x20) << 16)]
}

// fixed_3_5 converts a magnification to three integer and five fraction bits.
fn fixed_3_5(scale f64) !u64 {
	value := int(scale * 32 + 0.5)
	if value < 1 || value > 255 {
		return error('scale ${scale} is outside 1/32..7.97')
	}
	return u64(value)
}
