// Read-only inspection of a machine for diagnostics. Everything here uses
// peeks: it never advances time or acknowledges hardware.
module debug

import strings
import machine

// video_registers formats the video timing and interrupt state of TOM.
pub fn video_registers(m &machine.Machine) string {
	t := m.tom
	mut out := strings.new_builder(512)
	names := {
		'VMODE': u32(0x28)
		'HP':    0x2e
		'HDB1':  0x38
		'HDE':   0x3c
		'VP':    0x3e
		'VDB':   0x46
		'VDE':   0x48
		'VI':    0x4e
		'BG':    0x58
		'PIT0':  0x50
		'PIT1':  0x52
	}
	for name, offset in names {
		out.write_string('${name}=${t.regs[offset >> 1]:04x} ')
	}
	olp := (u32(t.regs[0x22 >> 1]) << 16) | t.regs[0x20 >> 1]
	out.writeln('')
	out.writeln('OLP=${olp:06x} VC=${t.vc} INT1 pending=${t.int_pending:02x} enable=${t.int_enable:02x} frame=${t.frame_width}x${t.frame_height}')
	out.writeln('JINT pending=${m.jerry.int_pending:02x} enable=${m.jerry.int_enable:02x} SCLK=${m.jerry.sclk} SMODE=${m.jerry.smode:x} JPIT=${m.jerry.regs[0]:04x},${m.jerry.regs[1]:04x},${m.jerry.regs[2]:04x},${m.jerry.regs[3]:04x}')
	return out.str()
}

// processors formats the execution state of the three processors.
pub fn processors(m &machine.Machine) string {
	mut out := strings.new_builder(512)
	out.writeln('68000 ${m.cpu.str_state()}')
	for name, c in {
		'GPU': m.gpu
		'DSP': m.dsp
	} {
		out.writeln('${name} pc=${c.pc:06x} running=${c.running} flags=${c.flags():05x} latches=${c.latches:02x} bank=${c.bank / 32} instructions=${c.instructions}')
	}
	return out.str()
}

// object_list decodes the display list from the object list pointer,
// following links as the object processor would for half-line `vc`.
pub fn object_list(m &machine.Machine, vc u32) string {
	t := m.tom
	mut out := strings.new_builder(1024)
	mut addr := ((u32(t.regs[0x22 >> 1]) << 16) | t.regs[0x20 >> 1]) & 0x3f_fff8
	for _ in 0 .. 64 {
		p0 := (u64(m.peek32(addr)) << 32) | m.peek32(addr + 4)
		link := u32(p0 >> 21) & 0x3f_fff8
		ypos := u32(p0 >> 3) & 0x7ff
		kind := u32(p0) & 7
		match kind {
			0, 1 {
				p1 := (u64(m.peek32(addr + 8)) << 32) | m.peek32(addr + 12)
				label := if kind == 0 { 'BITMAP' } else { 'SCALED' }
				xpos := int(u32(p1) & 0xfff)
				out.writeln('${addr:06x} ${label} y=${ypos} h=${u32(p0 >> 14) & 0x3ff} x=${xpos} data=${u32(p0 >> 40) & 0xff_fff8:06x} depth=${u32(p1 >> 12) & 7} pitch=${u32(p1 >> 15) & 7} dwidth=${u32(p1 >> 18) & 0x3ff} iwidth=${u32(p1 >> 28) & 0x3ff} index=${u32(p1 >> 38) & 0x7f} flags=${u32(p1 >> 45) & 0xf:x} link=${link:06x}')
				addr = link
			}
			2 {
				out.writeln('${addr:06x} GPU    data=${p0:016x}')
				addr += 8
			}
			3 {
				cc := u32(p0 >> 14) & 7
				taken := match cc {
					0 { vc == ypos || ypos == 0x7ff }
					1 { vc < ypos }
					2 { vc > ypos }
					else { false }
				}

				out.writeln('${addr:06x} BRANCH y=${ypos} cc=${cc} link=${link:06x} taken(vc=${vc})=${taken}')
				addr = if taken { link } else { addr + 8 }
			}
			4 {
				out.writeln('${addr:06x} STOP   int=${p0 & 8 != 0}')
				break
			}
			else {
				out.writeln('${addr:06x} ILLEGAL type ${kind} (${p0:016x})')
				break
			}
		}
	}
	return out.str()
}
