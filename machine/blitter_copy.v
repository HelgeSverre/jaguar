module machine

// blit_copy16 handles plain copies entirely within a physical RAM bank.
// Fight for Life repeatedly copies a 320x240 background into pitch-3 phrase
// storage. Avoiding the general blitter data path for each pixel saves host
// work; it does not omit guest writes or change the functional timing model.
@[direct_array_access]
pub fn (mut m Machine) blit_copy16(src u32, dst u32, pixels u32, src_pitch u32, dst_pitch u32) bool {
	if pixels == 0 || src_pitch < 1 || src_pitch > 4 || dst_pitch < 1 || dst_pitch > 4 {
		return false
	}
	s := src & address_mask
	d := dst & address_mask
	if (s | d) & 1 != 0 || s >= ram_mirror_end || d >= ram_mirror_end {
		return false
	}
	// Validate the whole row before writing anything. Leave address wrapping,
	// unmapped memory, ROM and device access to the ordinary bus path.
	sslot := u64((s & 7) >> 1) + pixels - 1
	dslot := u64((d & 7) >> 1) + pixels - 1
	send := u64(s & (ram_size - 8)) + (sslot >> 2) * src_pitch * 8 + (sslot & 3) * 2 + 1
	dend := u64(d & (ram_size - 8)) + (dslot >> 2) * dst_pitch * 8 + (dslot & 3) * 2 + 1
	if send >= ram_size || dend >= ram_size {
		return false
	}
	mut si := s & (ram_size - 1)
	mut di := d & (ram_size - 1)
	for _ in 0 .. pixels {
		// Read the whole source word before writing, including aliased RAM.
		hi := m.ram[si]
		lo := m.ram[si + 1]
		m.ram[di] = hi
		m.ram[di + 1] = lo
		si += 2
		di += 2
		if si & 7 == 0 { si += (src_pitch - 1) * 8 }
		if di & 7 == 0 { di += (dst_pitch - 1) * 8 }
	}
	return true
}
