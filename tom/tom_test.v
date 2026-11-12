module tom

import hwtypes

// bitmap_object writes a two-phrase bitmap object.
fn bitmap_object(mut b hwtypes.RamBus, addr u32, link u32, data u32, ypos u64, height u64, xpos u64, depth u64, iwidth u64, flags u64) {
	p0 := (u64(data >> 3) << 43) | (u64(link >> 3) << 24) | (height << 14) | (ypos << 3)
	p1 := (flags << 45) | (iwidth << 28) | (iwidth << 18) | (u64(1) << 15) | (depth << 12) | (xpos & 0xfff)
	b.write64(addr, p0)
	b.write64(addr + 8, p1)
}

fn stop_object(mut b hwtypes.RamBus, addr u32, interrupt bool) {
	b.write64(addr, if interrupt { u64(0xc) } else { u64(4) })
}

const list = u32(0x1000)
const image = u32(0x2000)

// ready returns TOM with video enabled and the object list at `list`.
fn ready(mut bus hwtypes.RamBus) &Tom {
	mut t := new(.ntsc)
	t.reset()
	t.write16(reg_vmode, 0x0647, mut bus) // RGB16, video on, no background fill
	t.write16(reg_vdb, 0, mut bus)
	t.write16(reg_vde, 0xffff, mut bus)
	t.write16(reg_olp_low, u16(list), mut bus)
	t.write16(reg_olp_high, u16(list >> 16), mut bus)
	return t
}

// compose runs the object list for one half-line.
fn (mut t Tom) compose(mut bus hwtypes.RamBus, vc u32) {
	t.vc = vc
	t.begin_line(mut bus)
}

fn test_bitmap_object_draws_and_writes_back() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	bitmap_object(mut bus, list, list + 16, image, 40, 2, 10, 4, 1, 0)
	stop_object(mut bus, list + 16, false)
	bus.write64(image, 0x1111_2222_3333_4444)
	bus.write64(image + 8, 0x5555_6666_7777_8888)

	t.compose(mut bus, 38)
	assert t.lbuf[10] == 0, 'above the object: nothing drawn'
	assert (bus.read64(list) >> 14) & 0x3ff == 2, 'height untouched before YPOS'

	t.compose(mut bus, 40)
	assert t.lbuf[10..14] == [u16(0x1111), 0x2222, 0x3333, 0x4444]
	assert (bus.read64(list) >> 14) & 0x3ff == 1, 'height counts down'
	assert u32(bus.read64(list) >> 40) & 0xff_fff8 == image + 8, 'data advances by DWIDTH'

	t.compose(mut bus, 42)
	assert t.lbuf[10..14] == [u16(0x5555), 0x6666, 0x7777, 0x8888]
	assert (bus.read64(list) >> 14) & 0x3ff == 0

	t.lbuf[10] = 0
	t.compose(mut bus, 44)
	assert t.lbuf[10] == 0, 'a finished object draws nothing'
}

fn test_palette_transparency_and_reflection() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	t.write16(clut_base + 2 * 0x21, 0xaaaa, mut bus)
	t.write16(clut_base + 2 * 0x2f, 0xbbbb, mut bus)
	// 4 bits per pixel, palette index 0x10 (upper nibble 2 after shifting),
	// transparent and reflected.
	p0 := (u64(image >> 3) << 43) | (u64((list + 16) >> 3) << 24) | (u64(1) << 14)
	p1 := (u64(5) << 45) | (u64(0x10) << 38) | (u64(1) << 28) | (u64(1) << 18) | (u64(1) << 15) | (u64(2) << 12) | 20
	bus.write64(list, p0)
	bus.write64(list + 8, p1)
	stop_object(mut bus, list + 16, false)
	bus.write64(image, 0x1f00_0000_0000_0000)
	t.lbuf[18] = 0x7777

	t.compose(mut bus, 0)
	assert t.lbuf[20] == 0xaaaa
	assert t.lbuf[19] == 0xbbbb, 'reflected objects draw right to left'
	assert t.lbuf[18] == 0x7777, 'colour zero is transparent'
}

fn test_branch_objects_select_by_line() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	// Branch to the stop when VC > 100, otherwise fall through to a bitmap.
	bus.write64(list, (u64((list + 0x40) >> 3) << 24) | (u64(2) << 14) | (u64(100) << 3) | 3)
	bitmap_object(mut bus, list + 8, list + 0x40, image, 0, 1000, 0, 4, 1, 0)
	stop_object(mut bus, list + 0x40, false)
	bus.write64(image, 0xffff_0000_0000_0000)

	t.compose(mut bus, 100)
	assert t.lbuf[0] == 0xffff
	t.lbuf[0] = 0
	t.compose(mut bus, 102)
	assert t.lbuf[0] == 0
}

fn test_stop_object_interrupt_and_looping_list_terminates() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	stop_object(mut bus, list, true)
	t.compose(mut bus, 0)
	assert t.int_pending & (1 << u32(Irq.object)) != 0

	// A branch that always links to itself must not hang the host.
	bus.write64(list, (u64(list >> 3) << 24) | (u64(0x7ff) << 3) | 3)
	t.compose(mut bus, 0)
	assert t.objects >= max_objects_per_line
}

fn test_gpu_object_suspends_until_obf_is_written() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	bus.write64(list, 0xdead_beef_0000_0002)
	bitmap_object(mut bus, list + 8, list + 0x40, image, 0, 1, 0, 4, 1, 0)
	stop_object(mut bus, list + 0x40, false)
	bus.write64(image, 0x4242_0000_0000_0000)

	t.compose(mut bus, 0)
	assert t.op_suspended
	assert t.gpu_irqs & (1 << gpu_irq_object) != 0
	assert t.lbuf[0] == 0, 'the list waits for the GPU'
	assert t.read16(reg_ob + 4) == 0xdead, 'OB2 holds the object high word'

	t.write16(reg_obf, 0, mut bus)
	assert !t.op_suspended
	assert t.lbuf[0] == 0x4242
}

fn test_scaled_object_doubles_pixels_and_lines() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	p0 := (u64(image >> 3) << 43) | (u64((list + 32) >> 3) << 24) | (u64(2) << 14) | 1
	p1 := (u64(1) << 28) | (u64(1) << 18) | (u64(1) << 15) | (u64(4) << 12)
	bus.write64(list, p0)
	bus.write64(list + 8, p1)
	bus.write64(list + 16, 0x40_4040) // remainder, vscale, hscale = 2.0
	stop_object(mut bus, list + 32, false)
	bus.write64(image, 0x000a_000b_000c_000d)
	bus.write64(image + 8, 0x001a_001b_001c_001d)

	t.compose(mut bus, 0)
	assert t.lbuf[0..8] == [u16(0xa), 0xa, 0xb, 0xb, 0xc, 0xc, 0xd, 0xd]
	assert (bus.read64(list) >> 14) & 0x3ff == 2, 'first source line shows twice'
	t.compose(mut bus, 2)
	assert t.lbuf[0] == 0xa
	assert (bus.read64(list) >> 14) & 0x3ff == 1
	t.compose(mut bus, 4)
	assert t.lbuf[0] == 0x1a
}

fn test_rgb16_channel_order() {
	assert rgb16_to_rgb(0xf800) == 0xff_0000, 'red is bits 15..11'
	assert rgb16_to_rgb(0x07c0) == 0x00_00ff, 'blue is bits 10..6'
	assert rgb16_to_rgb(0x003f) == 0x00_ff00, 'green is bits 5..0'
	assert cry_to_rgb(0x00ff) == 0xff_ffff || cry_to_rgb(0x0000) == 0
}

fn test_interrupt_latch_enable_and_clear() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	t.raise(.video)
	assert !t.irq_asserted(), 'a pending source needs its enable'
	t.write16(reg_int1, 0x0001, mut bus)
	assert t.irq_asserted(), 'enabling an already pending source asserts'
	t.write16(reg_int1, 0x0101, mut bus)
	assert !t.irq_asserted()
	assert t.read16(reg_int1) == 0
}

fn test_frame_completes_after_all_half_lines() {
	mut bus := hwtypes.new_ram_bus(0x10_0000)
	mut t := ready(mut bus)
	t.write16(reg_vp, 523, mut bus)
	mut frames := 0
	for _ in 0 .. 524 * 3 {
		if t.half_line(mut bus) {
			frames++
		}
	}
	assert frames == 3
	assert t.frame_sequence == 3
}
