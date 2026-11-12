module m68k

import hwtypes

// dispatch runs the handler selected by the decode table for the opcode
// held in `c.ir`.
fn (mut c Cpu) dispatch(mut bus hwtypes.Bus, op Op) {
	match op {
		.illegal { c.illegal(mut bus, vector_illegal) }
		.line_a { c.illegal(mut bus, vector_line_a) }
		.line_f { c.illegal(mut bus, vector_line_f) }
		.ori { c.op_alu_immediate(mut bus, .bit_or) }
		.andi { c.op_alu_immediate(mut bus, .bit_and) }
		.subi { c.op_alu_immediate(mut bus, .sub) }
		.addi { c.op_alu_immediate(mut bus, .add) }
		.eori { c.op_alu_immediate(mut bus, .bit_xor) }
		.cmpi { c.op_alu_immediate(mut bus, .cmp) }
		.logic_ccr { c.op_logic_ccr(mut bus) }
		.logic_sr { c.op_logic_sr(mut bus) }
		.bit_dynamic { c.op_bit_dynamic(mut bus) }
		.bit_static { c.op_bit_static(mut bus) }
		.movep { c.op_movep(mut bus) }
		.move_b { c.op_move(mut bus, .byte) }
		.move_w { c.op_move(mut bus, .word) }
		.move_l { c.op_move(mut bus, .long) }
		.movea_w { c.op_movea(mut bus, .word) }
		.movea_l { c.op_movea(mut bus, .long) }
		.negx { c.op_unary(mut bus, .negx) }
		.clr { c.op_unary(mut bus, .clr) }
		.neg { c.op_unary(mut bus, .neg) }
		.not { c.op_unary(mut bus, .not) }
		.tst { c.op_tst(mut bus) }
		.tas { c.op_tas(mut bus) }
		.nbcd { c.op_nbcd(mut bus) }
		.move_from_sr { c.op_move_from_sr(mut bus) }
		.move_to_ccr { c.op_move_to_ccr(mut bus) }
		.move_to_sr { c.op_move_to_sr(mut bus) }
		.chk { c.op_chk(mut bus) }
		.lea { c.op_lea(mut bus) }
		.pea { c.op_pea(mut bus) }
		.swap { c.op_swap() }
		.ext { c.op_ext() }
		.movem_to_mem { c.op_movem_to_mem(mut bus) }
		.movem_to_reg { c.op_movem_to_reg(mut bus) }
		.trap { c.op_trap(mut bus) }
		.link { c.op_link(mut bus) }
		.unlk { c.op_unlk(mut bus) }
		.move_to_usp { c.op_move_to_usp(mut bus) }
		.move_from_usp { c.op_move_from_usp(mut bus) }
		.reset { c.op_reset(mut bus) }
		.nop { c.cycles += 4 }
		.stop { c.op_stop(mut bus) }
		.rte { c.op_rte(mut bus) }
		.rts { c.op_rts(mut bus) }
		.trapv { c.op_trapv(mut bus) }
		.rtr { c.op_rtr(mut bus) }
		.jsr { c.op_jsr(mut bus) }
		.jmp { c.op_jmp(mut bus) }
		.addq { c.op_quick(mut bus, .add) }
		.subq { c.op_quick(mut bus, .sub) }
		.scc { c.op_scc(mut bus) }
		.dbcc { c.op_dbcc(mut bus) }
		.bsr { c.op_bsr(mut bus) }
		.bcc { c.op_bcc(mut bus) }
		.moveq { c.op_moveq() }
		.or_to_reg { c.op_alu_to_reg(mut bus, .bit_or) }
		.or_to_mem { c.op_alu_to_mem(mut bus, .bit_or) }
		.and_to_reg { c.op_alu_to_reg(mut bus, .bit_and) }
		.and_to_mem { c.op_alu_to_mem(mut bus, .bit_and) }
		.add_to_reg { c.op_alu_to_reg(mut bus, .add) }
		.add_to_mem { c.op_alu_to_mem(mut bus, .add) }
		.sub_to_reg { c.op_alu_to_reg(mut bus, .sub) }
		.sub_to_mem { c.op_alu_to_mem(mut bus, .sub) }
		.cmp { c.op_alu_to_reg(mut bus, .cmp) }
		.eor { c.op_eor(mut bus) }
		.adda { c.op_address_arith(mut bus, .add) }
		.suba { c.op_address_arith(mut bus, .sub) }
		.cmpa { c.op_address_arith(mut bus, .cmp) }
		.cmpm { c.op_cmpm(mut bus) }
		.addx { c.op_extended(mut bus, .add) }
		.subx { c.op_extended(mut bus, .sub) }
		.abcd { c.op_bcd(mut bus, .add) }
		.sbcd { c.op_bcd(mut bus, .sub) }
		.mulu { c.op_mul(mut bus, false) }
		.muls { c.op_mul(mut bus, true) }
		.divu { c.op_divu(mut bus) }
		.divs { c.op_divs(mut bus) }
		.exg { c.op_exg() }
		.shift_reg { c.op_shift_reg() }
		.shift_mem { c.op_shift_mem(mut bus) }
	}
}
