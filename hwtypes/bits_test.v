module hwtypes

fn test_sign_extension() {
	assert sext8(0x80) == 0xffff_ff80
	assert sext8(0x17f) == 0x7f
	assert sext16(0xfffe) == 0xffff_fffe
	assert sext16(0x1_7fff) == 0x7fff
	assert sext(0x10, 5) == 0xffff_fff0
	assert sext(0x0f, 5) == 0x0f
	assert sext(0x8000_0000, 32) == 0x8000_0000
}

fn test_shifts_are_defined_at_boundaries() {
	assert asr32(0x8000_0000, 31) == 0xffff_ffff
	assert asr32(0x8000_0000, 32) == 0xffff_ffff
	assert asr32(0x7fff_ffff, 40) == 0
	assert rol32(0x8000_0001, 1) == 0x0000_0003
	assert rol32(0x1234_5678, 32) == 0x1234_5678
	assert ror32(0x0000_0003, 1) == 0x8000_0001
	assert ror32(0x1234_5678, 0) == 0x1234_5678
}
