module jagkit

import debug
import risc

fn listing_m68k(code []u8, origin u32) []string {
	read := fn [code, origin] (addr u32) u16 {
		i := int(addr - origin)
		if i < 0 || i + 1 >= code.len {
			return 0
		}
		return (u16(code[i]) << 8) | code[i + 1]
	}
	mut out := []string{}
	mut pc := origin
	for pc < origin + u32(code.len) {
		text, n := debug.disassemble_m68k(read, pc)
		out << text
		pc += n
	}
	return out
}

fn listing_risc(code []u8, origin u32) []string {
	read := fn [code, origin] (addr u32) u16 {
		i := int(addr - origin)
		if i < 0 || i + 1 >= code.len {
			return 0
		}
		return (u16(code[i]) << 8) | code[i + 1]
	}
	mut out := []string{}
	mut pc := origin
	for pc < origin + u32(code.len) {
		text, n := debug.disassemble_risc(read, risc.Variant.gpu, pc)
		out << text
		pc += n
	}
	return out
}

const expected_m68k = 'move.l #$12345678,$00100000.l
move.w d0,$8(a1)
move.b $2(a0,d1.l),d2
movea.l #$00004000,a0
move.w $00004000.l,d3
move.l (a0)+,-(sp)
moveq #-1,d7
lea $004000(pc),a2
lea $00004000.l,a3
move.w #$2000,sr
movem.l d0-d1/a0/a6,-(sp)
movem.l (sp)+,d0-d1/a0/a6
clr.w $00f00058.l
neg.l d1
not.b d1
tst.w (a0)
swap d4
ext.w d4
ext.l d4
addq.w #1,d0
addi.w #$0064,d0
adda.l d1,a0
add.w d1,d2
add.w d1,(a0)
adda.l #$000003e8,a0
subq.l #8,a0
sub.b (a0)+,d0
cmpi.w #$0030,d0
cmpa.l a0,a1
cmp.b d1,d0
andi.w #$00ff,d0
and.l d0,d1
or.w d0,(a0)
ori.l #$00000001,d1
eor.w d0,d1
eori.b #$03,d1
mulu.w #$0028,d0
muls.w d1,d0
divu.w #$000a,d0
asl.l #1,d0
asr.w #8,d0
lsl.w d1,d0
lsr.l #3,d0
roxl.l #1,d0
rol.b #2,d0
ror.w #4,d0
btst #4,$00f14003.l
btst #9,d0
bclr #0,(a0)
bset #31,d1
bra.w $004000
bsr.w $0040ce
bne.w $004000
bcs.w $0040ce
dbra d0,$004000
jmp $00004000.l
jsr (a0)
rts
rte
nop
stop #$2000'

const expected_risc = 'movei #12345678,r1
movei #00f03060,r2
add r1,r2
addq #32,r3
addqt #1,r3
sub r1,r2
subq #1,r4
subqt #4,r4
neg r5
and r1,r2
or r1,r2
xor r1,r2
not r2
btst #3,r29
bset #10,r29
bclr #3,r29
mult r1,r2
imult r1,r2
div r1,r2
abs r2
shlq #8,r1
shrq #16,r1
sharq #31,r1
rorq #4,r1
cmp r1,r2
cmpq #-1,r2
move r1,r2
moveq #31,r2
move pc,r6
loadb (r1),r2
loadw (r1),r2
load (r1),r2
storeb r2,(r1)
storew r2,(r1)
store r2,(r1)
load (r14+4),r2
store r2,(r14+128)
jr ne,f0304e
nop
jr f03060
nop
jump eq,(r7)
nop
nop
mtoi r21,r13
store r15,(r23)'

// Every instruction the assemblers emit must read back, through the
// emulator's disassemblers, as what was asked for.
fn test_m68k_instructions_disassemble_as_written() {
	mut m := new_m68k(0x4000)
	m.label('top')
	m.move(.l, imm(0x12345678), abs(0x100000))
	m.move(.w, d0, at(8, a1))
	m.move(.b, idx(2, a0, d1), d2)
	m.move(.l, ptr('top'), a0)
	m.move(.w, lbl('top'), d3)
	m.move(.l, inc(a0), dec(sp))
	m.moveq(-1, d7)
	m.lea(rel('top'), a2)
	m.lea(lbl('top'), a3)
	m.move_to_sr(imm(0x2000))
	m.push([d0, d1, a0, a6])
	m.pop([d0, d1, a0, a6])
	m.clr(.w, abs(0xf00058))
	m.neg(.l, d1)
	m.not(.b, d1)
	m.tst(.w, ind(a0))
	m.swap(d4)
	m.ext(.w, d4)
	m.ext(.l, d4)
	m.add(.w, imm(1), d0)
	m.add(.w, imm(100), d0)
	m.add(.l, d1, a0)
	m.add(.w, d1, d2)
	m.add(.w, d1, ind(a0))
	m.add(.l, imm(1000), a0)
	m.sub(.l, imm(8), a0)
	m.sub(.b, inc(a0), d0)
	m.cmp(.w, imm(48), d0)
	m.cmp(.l, a0, a1)
	m.cmp(.b, d1, d0)
	m.and(.w, imm(0xff), d0)
	m.and(.l, d0, d1)
	m.orr(.w, d0, ind(a0))
	m.orr(.l, imm(1), d1)
	m.eor(.w, d0, d1)
	m.eor(.b, imm(3), d1)
	m.mulu(imm(40), d0)
	m.muls(d1, d0)
	m.divu(imm(10), d0)
	m.asl(.l, imm(1), d0)
	m.asr(.w, imm(8), d0)
	m.lsl(.w, d1, d0)
	m.lsr(.l, imm(3), d0)
	m.roxl(.l, imm(1), d0)
	m.rol(.b, imm(2), d0)
	m.ror(.w, imm(4), d0)
	m.btst(4, abs(0xf14003))
	m.btst(9, d0)
	m.bclr(0, ind(a0))
	m.bset(31, d1)
	m.bra('top')
	m.bsr('end')
	m.b(.ne, 'top')
	m.b(.cs, 'end')
	m.dbra(d0, 'top')
	m.jmp(lbl('top'))
	m.jsr(ind(a0))
	m.rts()
	m.rte()
	m.nop()
	m.stop(0x2000)
	m.label('end')
	code := m.assemble() or { panic(err) }
	assert listing_m68k(code, 0x4000).join('\n') == expected_m68k
}

fn test_risc_instructions_disassemble_as_written() {
	mut g := new_risc(0xf03000)
	g.label('start')
	g.movei(0x12345678, .r1)
	g.movei_label('data', .r2)
	g.add(.r1, .r2)
	g.addq(32, .r3)
	g.addqt(1, .r3)
	g.sub(.r1, .r2)
	g.subq(1, .r4)
	g.subqt(4, .r4)
	g.neg(.r5)
	g.and(.r1, .r2)
	g.orr(.r1, .r2)
	g.xor(.r1, .r2)
	g.not(.r2)
	g.btst(3, .r29)
	g.bset(10, .r29)
	g.bclr(3, .r29)
	g.mult(.r1, .r2)
	g.imult(.r1, .r2)
	g.div(.r1, .r2)
	g.abs(.r2)
	g.shlq(8, .r1)
	g.shrq(16, .r1)
	g.sharq(31, .r1)
	g.rorq(4, .r1)
	g.cmp(.r1, .r2)
	g.cmpq(-1, .r2)
	g.move(.r1, .r2)
	g.moveq(31, .r2)
	g.move_pc(.r6)
	g.loadb(.r1, .r2)
	g.loadw(.r1, .r2)
	g.load(.r1, .r2)
	g.storeb(.r2, .r1)
	g.storew(.r2, .r1)
	g.store(.r2, .r1)
	g.label('near')
	g.load_r14(4, .r2)
	g.store_r14(.r2, 128)
	g.jr(.ne, 'near')
	g.nop()
	g.jr(.always, 'data')
	g.nop()
	g.jump(.eq, .r7)
	g.nop()
	g.nop()
	g.align_long()
	g.label('data')
	g.long(0xdeadbeef)
	gc := g.assemble() or { panic(err) }
	assert listing_risc(gc, 0xf03000).join('\n') == expected_risc
}

fn test_mistakes_are_reported_together() {
	mut m := new_m68k(0x4000)
	m.moveq(200, d0)
	m.bra('nowhere')
	m.asl(.w, imm(9), d0)
	message := if _ := m.assemble() { '' } else { err.msg() }
	assert message.contains('moveq #200')
	assert message.contains('unknown label `nowhere`')
	assert message.contains('asl #9')

	mut g := new_risc(0xf03000)
	g.addq(33, .r0)
	g.load_r14(6, .r0)
	g.jr(.always, 'missing')
	risc_message := if _ := g.assemble() { '' } else { err.msg() }
	assert risc_message.contains('addq #33')
	assert risc_message.contains('+6')
	assert risc_message.contains('unknown label `missing`')
}

fn test_jag_image_is_accepted_by_the_loader() {
	payload := [u8(0x60), 0xfe]
	image := jag_image(0x4000, 0x4000, payload)
	assert image.len == 0x2e + 2
	assert image[0x1c..0x20] == 'JAGR'.bytes()
	assert image[0x22..0x26] == [u8(0), 0, 0x40, 0]
}

fn test_object_list_layout() {
	list := object_list(0x80000, ntsc, [
		Bitmap{
			x:      16
			y:      ntsc.vdb
			width:  160
			height: 120
			data:   0x90000
			hscale: 2
			vscale: 2
		},
		Bitmap{
			x:           16
			y:           ntsc.vdb
			width:       320
			height:      240
			data:        0x88000
			depth:       .bpp1
			transparent: true
		},
	])!
	assert list.offsets == [32, 64]
	assert list.bytes.len == 96
	// Two branches, then the stop object the second one falls into.
	assert list.bytes[7] & 7 == 3
	assert list.bytes[15] & 7 == 3
	assert list.bytes[23] & 7 == 4
	// The scaled tunnel, then the unscaled overlay.
	assert list.bytes[32 + 7] & 7 == 1
	assert list.bytes[64 + 7] & 7 == 0
	// Scale 2.0 in both directions, remainder 1.0.
	assert list.bytes[32 + 16 + 5..32 + 24] == [u8(0x20), 0x40, 0x40]
	if _ := object_list(0x80008, ntsc, []) {
		assert false, 'an unaligned list must be refused'
	}
	if _ := object_list(0x80000, ntsc, [Bitmap{ width: 30, height: 1 }]) {
		assert false, 'a line that does not fill phrases must be refused'
	}
}

fn test_cry_picks_the_nearest_hue() {
	assert cry(0, 0, 0) == 0
	assert cry(255, 255, 255) & 0xff == 255
	red := cry(200, 0, 0)
	assert red & 0xff == 200
	assert cry(100, 0, 0) >> 8 == red >> 8, 'brightness must not change the hue'
}
