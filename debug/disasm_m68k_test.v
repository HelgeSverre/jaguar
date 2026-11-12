module debug

const m68k_test_base = u32(0x4000)

struct M68kCase {
	words []u16
	text  string
}

// m68k_test_reader serves `words` starting at the test base address and zero elsewhere.
fn m68k_test_reader(words []u16) WordReader {
	return fn [words] (addr u32) u16 {
		index := int(addr - m68k_test_base) / 2
		return if addr >= m68k_test_base && index < words.len { words[index] } else { u16(0) }
	}
}

fn check_m68k_cases(cases []M68kCase) {
	for c in cases {
		text, length := disassemble_m68k(m68k_test_reader(c.words), m68k_test_base)
		assert text == c.text, 'opcode ${c.words[0]:04x}'
		assert length == u32(c.words.len * 2), '${c.text}: length'
	}
}

fn test_move() {
	check_m68k_cases([
		M68kCase{[u16(0x23fc), 0x1234, 0x5678, 0x0010, 0x0000], 'move.l #$12345678,$00100000.l'},
		M68kCase{[u16(0x3318)], 'move.w (a0)+,-(a1)'},
		M68kCase{[u16(0x1430), 0x1010], 'move.b $10(a0,d1.w),d2'},
		M68kCase{[u16(0x1430), 0x1810], 'move.b $10(a0,d1.l),d2'},
		M68kCase{[u16(0x1e33), 0xa0ff], 'move.b -$1(a3,a2.w),d7'},
		M68kCase{[u16(0x1200)], 'move.b d0,d1'},
		M68kCase{[u16(0x3481)], 'move.w d1,(a2)'},
		M68kCase{[u16(0x2008)], 'move.l a0,d0'},
		M68kCase{[u16(0x103c), 0x007f], 'move.b #$7f,d0'},
		M68kCase{[u16(0x303c), 0x1234], 'move.w #$1234,d0'},
		M68kCase{[u16(0x3638), 0x1234], 'move.w $1234.w,d3'},
		M68kCase{[u16(0x203a), 0x0030], 'move.l $004032(pc),d0'},
		M68kCase{[u16(0x303b), 0x98fe], 'move.w $004000(pc,a1.l),d0'},
		M68kCase{[u16(0x2d40), 0xfff8], 'move.l d0,-$8(a6)'},
		M68kCase{[u16(0x33c0), 0x00f0, 0x0058], 'move.w d0,$00f00058.l'},
		M68kCase{[u16(0x201f)], 'move.l (sp)+,d0'},
		M68kCase{[u16(0x2f00)], 'move.l d0,-(sp)'},
		M68kCase{[u16(0x2248)], 'movea.l a0,a1'},
		M68kCase{[u16(0x307c), 0x1234], 'movea.w #$1234,a0'},
		M68kCase{[u16(0x70ff)], 'moveq #-1,d0'},
		M68kCase{[u16(0x7e7f)], 'moveq #127,d7'},
	])
}

fn test_movem_and_movep() {
	check_m68k_cases([
		M68kCase{[u16(0x48e7), 0xfffe], 'movem.l d0-d7/a0-a6,-(sp)'},
		M68kCase{[u16(0x48e7), 0x3020], 'movem.l d2-d3/a2,-(sp)'},
		M68kCase{[u16(0x4cdf), 0x0107], 'movem.l (sp)+,d0-d2/a0'},
		M68kCase{[u16(0x4cdf), 0x7fff], 'movem.l (sp)+,d0-d7/a0-a6'},
		M68kCase{[u16(0x4890), 0x0205], 'movem.w d0/d2/a1,(a0)'},
		M68kCase{[u16(0x4ca8), 0xe002, 0x0010], 'movem.w $10(a0),d1/a5-sp'},
		M68kCase{[u16(0x48f9), 0x0003, 0x00f0, 0x3000], 'movem.l d0-d1,$00f03000.l'},
		M68kCase{[u16(0x4cfa), 0x0001, 0x000c], 'movem.l $004010(pc),d0'},
		M68kCase{[u16(0x0108), 0x0010], 'movep.w $10(a0),d0'},
		M68kCase{[u16(0x03ca), 0x0004], 'movep.l d1,$4(a2)'},
	])
}

fn test_address_and_control_flow() {
	check_m68k_cases([
		M68kCase{[u16(0x41fa), 0x0030], 'lea $004032(pc),a0'},
		M68kCase{[u16(0x43f9), 0x0080, 0x2a10], 'lea $00802a10.l,a1'},
		M68kCase{[u16(0x43d0)], 'lea (a0),a1'},
		M68kCase{[u16(0x45f0), 0x1010], 'lea $10(a0,d1.w),a2'},
		M68kCase{[u16(0x4fee), 0xfff8], 'lea -$8(a6),sp'},
		M68kCase{[u16(0x4850)], 'pea (a0)'},
		M68kCase{[u16(0x4878), 0x1234], 'pea $1234.w'},
		M68kCase{[u16(0x4eb9), 0x0080, 0x2a10], 'jsr $00802a10.l'},
		M68kCase{[u16(0x4e90)], 'jsr (a0)'},
		M68kCase{[u16(0x4eba), 0x000e], 'jsr $004010(pc)'},
		M68kCase{[u16(0x4ed1)], 'jmp (a1)'},
		M68kCase{[u16(0x4efb), 0x0002], 'jmp $004004(pc,d0.w)'},
		M68kCase{[u16(0x4ef9), 0x0000, 0x4000], 'jmp $00004000.l'},
		M68kCase{[u16(0x4e75)], 'rts'},
		M68kCase{[u16(0x4e73)], 'rte'},
		M68kCase{[u16(0x4e77)], 'rtr'},
		M68kCase{[u16(0x4e71)], 'nop'},
		M68kCase{[u16(0x4e70)], 'reset'},
		M68kCase{[u16(0x4e76)], 'trapv'},
		M68kCase{[u16(0x4e72), 0x2000], 'stop #$2000'},
		M68kCase{[u16(0x4afc)], 'illegal'},
		M68kCase{[u16(0x4e41)], 'trap #1'},
		M68kCase{[u16(0x4e4f)], 'trap #15'},
		M68kCase{[u16(0x4e56), 0xfff8], 'link a6,#-8'},
		M68kCase{[u16(0x4e5e)], 'unlk a6'},
		M68kCase{[u16(0x4e60)], 'move.l a0,usp'},
		M68kCase{[u16(0x4e69)], 'move.l usp,a1'},
		M68kCase{[u16(0x4390)], 'chk.w (a0),d1'},
		M68kCase{[u16(0x41bc), 0x0064], 'chk.w #$0064,d0'},
	])
}

fn test_branches() {
	check_m68k_cases([
		M68kCase{[u16(0x671e)], 'beq.s $004020'},
		M68kCase{[u16(0x6600), 0x00fe], 'bne.w $004100'},
		M68kCase{[u16(0x60fe)], 'bra.s $004000'},
		M68kCase{[u16(0x6000), 0x0000], 'bra.w $004002'},
		M68kCase{[u16(0x610e)], 'bsr.s $004010'},
		M68kCase{[u16(0x6100), 0xf000], 'bsr.w $003002'},
		M68kCase{[u16(0x6202)], 'bhi.s $004004'},
		M68kCase{[u16(0x6302)], 'bls.s $004004'},
		M68kCase{[u16(0x6402)], 'bcc.s $004004'},
		M68kCase{[u16(0x6502)], 'bcs.s $004004'},
		M68kCase{[u16(0x6802)], 'bvc.s $004004'},
		M68kCase{[u16(0x6902)], 'bvs.s $004004'},
		M68kCase{[u16(0x6a02)], 'bpl.s $004004'},
		M68kCase{[u16(0x6b02)], 'bmi.s $004004'},
		M68kCase{[u16(0x6c02)], 'bge.s $004004'},
		M68kCase{[u16(0x6d02)], 'blt.s $004004'},
		M68kCase{[u16(0x6e02)], 'bgt.s $004004'},
		M68kCase{[u16(0x6f00), 0xfffe], 'ble.w $004000'},
		M68kCase{[u16(0x51c8), 0x0010], 'dbra d0,$004012'},
		M68kCase{[u16(0x51c9), 0xfffc], 'dbra d1,$003ffe'},
		M68kCase{[u16(0x57ca), 0x0000], 'dbeq d2,$004002'},
		M68kCase{[u16(0x56cb), 0xfffe], 'dbne d3,$004000'},
		M68kCase{[u16(0x57c0)], 'seq d0'},
		M68kCase{[u16(0x50d0)], 'st (a0)'},
		M68kCase{[u16(0x51c1)], 'sf d1'},
		M68kCase{[u16(0x56e8), 0x0010], 'sne $10(a0)'},
		M68kCase{[u16(0x52e1)], 'shi -(a1)'},
	])
}

fn test_immediate_and_bit_operations() {
	check_m68k_cases([
		M68kCase{[u16(0x007c), 0x0700], 'ori.w #$0700,sr'},
		M68kCase{[u16(0x003c), 0x0001], 'ori.b #$01,ccr'},
		M68kCase{[u16(0x027c), 0xf8ff], 'andi.w #$f8ff,sr'},
		M68kCase{[u16(0x023c), 0x00fe], 'andi.b #$fe,ccr'},
		M68kCase{[u16(0x0a7c), 0x2000], 'eori.w #$2000,sr'},
		M68kCase{[u16(0x0a3c), 0x0010], 'eori.b #$10,ccr'},
		M68kCase{[u16(0x0000), 0x0080], 'ori.b #$80,d0'},
		M68kCase{[u16(0x0241), 0x00ff], 'andi.w #$00ff,d1'},
		M68kCase{[u16(0x0290), 0x0000, 0xffff], 'andi.l #$0000ffff,(a0)'},
		M68kCase{[u16(0x0442), 0x0010], 'subi.w #$0010,d2'},
		M68kCase{[u16(0x0680), 0x0001, 0x0000], 'addi.l #$00010000,d0'},
		M68kCase{[u16(0x0628), 0x0001, 0x0004], 'addi.b #$01,$4(a0)'},
		M68kCase{[u16(0x0a40), 0xffff], 'eori.w #$ffff,d0'},
		M68kCase{[u16(0x0c18), 0x0020], 'cmpi.b #$20,(a0)+'},
		M68kCase{[u16(0x0cb8), 0x1234, 0x5678, 0x1000], 'cmpi.l #$12345678,$1000.w'},
		M68kCase{[u16(0x0801), 0x0005], 'btst #5,d1'},
		M68kCase{[u16(0x0840), 0x001f], 'bchg #31,d0'},
		M68kCase{[u16(0x08d0), 0x0007], 'bset #7,(a0)'},
		M68kCase{[u16(0x08b9), 0x0000, 0x00f0, 0x0020], 'bclr #0,$00f00020.l'},
		M68kCase{[u16(0x083a), 0x0003, 0x000c], 'btst #3,$004010(pc)'},
		M68kCase{[u16(0x0101)], 'btst d0,d1'},
		M68kCase{[u16(0x013c), 0x0012], 'btst d0,#$12'},
		M68kCase{[u16(0x0350)], 'bchg d1,(a0)'},
		M68kCase{[u16(0x05a1)], 'bclr d2,-(a1)'},
		M68kCase{[u16(0x0fe8), 0x0010], 'bset d7,$10(a0)'},
	])
}

fn test_arithmetic() {
	check_m68k_cases([
		M68kCase{[u16(0xd041)], 'add.w d1,d0'},
		M68kCase{[u16(0xd498)], 'add.l (a0)+,d2'},
		M68kCase{[u16(0xd111)], 'add.b d0,(a1)'},
		M68kCase{[u16(0xd048)], 'add.w a0,d0'},
		M68kCase{[u16(0xd0bc), 0x0000, 0x0010], 'add.l #$00000010,d0'},
		M68kCase{[u16(0xd778), 0x1234], 'add.w d3,$1234.w'},
		M68kCase{[u16(0xd0c0)], 'adda.w d0,a0'},
		M68kCase{[u16(0xd3fc), 0x0000, 0x0100], 'adda.l #$00000100,a1'},
		M68kCase{[u16(0xd380)], 'addx.l d0,d1'},
		M68kCase{[u16(0xd308)], 'addx.b -(a0),-(a1)'},
		M68kCase{[u16(0x5040)], 'addq.w #8,d0'},
		M68kCase{[u16(0x5288)], 'addq.l #1,a0'},
		M68kCase{[u16(0x9041)], 'sub.w d1,d0'},
		M68kCase{[u16(0x9190)], 'sub.l d0,(a0)'},
		M68kCase{[u16(0x9028), 0x007f], 'sub.b $7f(a0),d0'},
		M68kCase{[u16(0x93c8)], 'suba.l a0,a1'},
		M68kCase{[u16(0x94d0)], 'suba.w (a0),a2'},
		M68kCase{[u16(0x9742)], 'subx.w d2,d3'},
		M68kCase{[u16(0x998b)], 'subx.l -(a3),-(a4)'},
		M68kCase{[u16(0x5310)], 'subq.b #1,(a0)'},
		M68kCase{[u16(0x594f)], 'subq.w #4,sp'},
		M68kCase{[u16(0xb041)], 'cmp.w d1,d0'},
		M68kCase{[u16(0xb088)], 'cmp.l a0,d0'},
		M68kCase{[u16(0xb210)], 'cmp.b (a0),d1'},
		M68kCase{[u16(0xb07c), 0x1234], 'cmp.w #$1234,d0'},
		M68kCase{[u16(0xb3c8)], 'cmpa.l a0,a1'},
		M68kCase{[u16(0xb0fc), 0x0010], 'cmpa.w #$0010,a0'},
		M68kCase{[u16(0xb308)], 'cmpm.b (a0)+,(a1)+'},
		M68kCase{[u16(0xb78a)], 'cmpm.l (a2)+,(a3)+'},
		M68kCase{[u16(0xc0c1)], 'mulu.w d1,d0'},
		M68kCase{[u16(0xc5fc), 0x000a], 'muls.w #$000a,d2'},
		M68kCase{[u16(0x80c1)], 'divu.w d1,d0'},
		M68kCase{[u16(0x87d0)], 'divs.w (a0),d3'},
		M68kCase{[u16(0xc300)], 'abcd d0,d1'},
		M68kCase{[u16(0xc308)], 'abcd -(a0),-(a1)'},
		M68kCase{[u16(0x8702)], 'sbcd d2,d3'},
		M68kCase{[u16(0x870a)], 'sbcd -(a2),-(a3)'},
		M68kCase{[u16(0x4800)], 'nbcd d0'},
		M68kCase{[u16(0x4811)], 'nbcd (a1)'},
	])
}

fn test_logic_and_unary() {
	check_m68k_cases([
		M68kCase{[u16(0xc041)], 'and.w d1,d0'},
		M68kCase{[u16(0xc0bc), 0x0000, 0xffff], 'and.l #$0000ffff,d0'},
		M68kCase{[u16(0xc110)], 'and.b d0,(a0)'},
		M68kCase{[u16(0x8041)], 'or.w d1,d0'},
		M68kCase{[u16(0x8010)], 'or.b (a0),d0'},
		M68kCase{[u16(0x81a1)], 'or.l d0,-(a1)'},
		M68kCase{[u16(0xb141)], 'eor.w d0,d1'},
		M68kCase{[u16(0xb390)], 'eor.l d1,(a0)'},
		M68kCase{[u16(0xb528), 0x0010], 'eor.b d2,$10(a0)'},
		M68kCase{[u16(0xc141)], 'exg d0,d1'},
		M68kCase{[u16(0xc149)], 'exg a0,a1'},
		M68kCase{[u16(0xc189)], 'exg d0,a1'},
		M68kCase{[u16(0x4a2c), 0x02c7], 'tst.b $2c7(a4)'},
		M68kCase{[u16(0x4a40)], 'tst.w d0'},
		M68kCase{[u16(0x4a98)], 'tst.l (a0)+'},
		M68kCase{[u16(0x4ad0)], 'tas (a0)'},
		M68kCase{[u16(0x4ac1)], 'tas d1'},
		M68kCase{[u16(0x4240)], 'clr.w d0'},
		M68kCase{[u16(0x42a7)], 'clr.l -(sp)'},
		M68kCase{[u16(0x4239), 0x00f0, 0x0000], 'clr.b $00f00000.l'},
		M68kCase{[u16(0x4481)], 'neg.l d1'},
		M68kCase{[u16(0x4010)], 'negx.b (a0)'},
		M68kCase{[u16(0x4643)], 'not.w d3'},
		M68kCase{[u16(0x4843)], 'swap d3'},
		M68kCase{[u16(0x4880)], 'ext.w d0'},
		M68kCase{[u16(0x48c1)], 'ext.l d1'},
		M68kCase{[u16(0x40c0)], 'move.w sr,d0'},
		M68kCase{[u16(0x44c0)], 'move.w d0,ccr'},
		M68kCase{[u16(0x46fc), 0x2700], 'move.w #$2700,sr'},
		M68kCase{[u16(0x46d8)], 'move.w (a0)+,sr'},
	])
}

fn test_shifts_and_rotates() {
	check_m68k_cases([
		M68kCase{[u16(0xe540)], 'asl.w #2,d0'},
		M68kCase{[u16(0xe001)], 'asr.b #8,d1'},
		M68kCase{[u16(0xe2aa)], 'lsr.l d1,d2'},
		M68kCase{[u16(0xe34b)], 'lsl.w #1,d3'},
		M68kCase{[u16(0xe990)], 'roxl.l #4,d0'},
		M68kCase{[u16(0xe071)], 'roxr.w d0,d1'},
		M68kCase{[u16(0xe71a)], 'rol.b #3,d2'},
		M68kCase{[u16(0xeeb8)], 'ror.l d7,d0'},
		M68kCase{[u16(0xe7f8), 0x1234], 'rol.w $1234.w'},
		M68kCase{[u16(0xe0d0)], 'asr.w (a0)'},
		M68kCase{[u16(0xe1d8)], 'asl.w (a0)+'},
		M68kCase{[u16(0xe2e1)], 'lsr.w -(a1)'},
		M68kCase{[u16(0xe3e8), 0x0010], 'lsl.w $10(a0)'},
		M68kCase{[u16(0xe4d2)], 'roxr.w (a2)'},
		M68kCase{[u16(0xe5f9), 0x00f0, 0x0000], 'roxl.w $00f00000.l'},
		M68kCase{[u16(0xe6d3)], 'ror.w (a3)'},
	])
}

// Opcodes that exist only on later CPUs, or use an addressing mode the
// instruction does not accept, are data words of length 2.
fn test_invalid_opcodes() {
	invalid := {
		u16(0x1008): 'move.b a0,d0'
		0x1040:      'movea.b d0,a0'
		0x35c0:      'move.w d0,(d16,pc)'
		0x7100:      'moveq with bit 8 set'
		0x41c0:      'lea d0,a0'
		0x4ed8:      'jmp (a0)+'
		0x4e74:      'rtd (68010)'
		0x4e7a:      'movec (68010)'
		0x42c0:      'move ccr,d0 (68010)'
		0x48d8:      'movem to (a0)+'
		0x4ce0:      'movem from -(a0)'
		0x4c00:      'mulu.l (68020)'
		0x0c7a:      'cmpi.w #,(d16,pc) (68010)'
		0x0648:      'addi.w #,a0'
		0x00bc:      'ori.l #,sr'
		0x06c0:      'addi with size 3'
		0x0e00:      'moves (68010)'
		0x083c:      'btst #,#'
		0x017c:      'bchg d0,#'
		0x5208:      'addq.b #1,a0'
		0xd008:      'add.b a0,d0'
		0xc048:      'and.w a0,d0'
		0xc180:      'exg with data mode 0'
		0x8140:      'pack (68020)'
		0xe0c0:      'asr.w d0 memory form'
		0xe8c0:      'bftst (68020)'
	}
	for opcode, reason in invalid {
		text, length := disassemble_m68k(m68k_test_reader([opcode, 0x1234, 0x5678]), m68k_test_base)
		assert text == 'dc.w $${opcode:04x}', reason
		assert length == 2, reason
	}
}

fn test_line_a_and_line_f() {
	check_m68k_cases([
		M68kCase{[u16(0xa000)], 'dc.w $a000 ; line-A'},
		M68kCase{[u16(0xf123)], 'dc.w $f123 ; line-F'},
	])
}

fn test_every_opcode_decodes() {
	for extension in [u16(0x0000), 0xffff] {
		for opcode in 0 .. 0x10000 {
			read := fn [opcode, extension] (addr u32) u16 {
				return if addr == m68k_test_base { u16(opcode) } else { extension }
			}
			text, length := disassemble_m68k(read, m68k_test_base)
			assert text != '', 'opcode ${opcode:04x}'
			assert length >= 2 && length <= 10 && length % 2 == 0, 'opcode ${opcode:04x}: ${text}'
		}
	}
}
