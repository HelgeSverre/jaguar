# jagkit reference

Every public name in `jagkit`, with the comment from its source. This file is generated: see `jagkit/reference_test.v`. The guide is [`jagkit.md`](jagkit.md).

## The 68000 assembler

`jagkit/m68k.v`

| Declaration | |
|---|---|
| `enum Size` | Size is the operand size of a 68000 instruction. |
| `enum Cc` | Cc is the condition of a 68000 branch. |
| `struct Ea` | Ea is one operand of a 68000 instruction. The registers are the constants d0..d7, a0..a6 and sp; the functions below build the rest. |
| `fn ind(a Ea) Ea` | ind is `(An)`. |
| `fn inc(a Ea) Ea` | inc is `(An)+`. |
| `fn dec(a Ea) Ea` | dec is `-(An)`. |
| `fn at(offset int, a Ea) Ea` | at is `offset(An)`. |
| `fn idx(offset int, a Ea, x Ea) Ea` | idx is `offset(An,Xn.l)`: the base plus a whole index register. |
| `fn abs(address u32) Ea` | abs is the memory at a fixed address. |
| `fn imm(value i64) Ea` | imm is `#value`. |
| `fn lbl(name string) Ea` | lbl is the memory at a label, or the label itself for jumps. |
| `fn ptr(name string) Ea` | ptr is `#label`: the address of a label as a value. |
| `fn rel(name string) Ea` | rel is `label(pc)`. |
| `struct M68k` | M68k assembles a 68000 program. Mistakes are collected and reported together by `assemble`. |
| `fn new_m68k(origin u32) &M68k` | new_m68k starts a program that will be loaded at `origin`. |
| `fn (m &M68k) here() u32` | here is the address of the next byte to be emitted. |
| `fn (mut m M68k) label(name string)` | label names the current address. |
| `fn (mut m M68k) unique(prefix string) string` | unique returns a label name that has not been used, for local jumps. |
| `fn (m &M68k) address_of(name string) u32` | address_of returns the address of a label that is already defined. |
| `fn (m &M68k) symbols() map[string]u32` | symbols returns the address of every label defined so far. |
| `fn (mut m M68k) assemble() ![]u8` | assemble resolves the labels and returns the program. |
| `fn (mut m M68k) byte(value int)` | byte emits an 8-bit constant. |
| `fn (mut m M68k) word(value int)` | word emits a 16-bit constant. |
| `fn (mut m M68k) long(value u32)` | long emits a 32-bit constant. |
| `fn (mut m M68k) long_label(name string)` | long_label emits the address of a label. |
| `fn (mut m M68k) bytes(data []u8)` | bytes emits raw data. |
| `fn (mut m M68k) text(s string)` | text emits a zero-terminated string and pads to an even address. |
| `fn (mut m M68k) align(n u32)` | align pads with zeroes to a multiple of `n` bytes. |
| `fn (mut m M68k) move(size Size, src Ea, dst Ea)` | move copies src to dst; an address-register destination is `movea`. |
| `fn (mut m M68k) moveq(value int, dst Ea)` | moveq loads -128..127 into a whole data register. |
| `fn (mut m M68k) lea(src Ea, dst Ea)` | lea loads the address of src into an address register. |
| `fn (mut m M68k) move_to_sr(src Ea)` | move_to_sr sets the status register; supervisor only. |
| `fn (mut m M68k) push(registers []Ea)` | push is `movem.l registers,-(sp)`. |
| `fn (mut m M68k) pop(registers []Ea)` | pop is `movem.l (sp)+,registers`. |
| `fn (mut m M68k) clr(size Size, dst Ea)` | clr zeroes dst. |
| `fn (mut m M68k) neg(size Size, dst Ea)` | neg negates dst. |
| `fn (mut m M68k) not(size Size, dst Ea)` | not flips every bit of dst. |
| `fn (mut m M68k) tst(size Size, dst Ea)` | tst sets the flags for dst. |
| `fn (mut m M68k) swap(dst Ea)` | swap exchanges the two words of a data register. |
| `fn (mut m M68k) ext(size Size, dst Ea)` | ext sign-extends a byte to a word (`.w`) or a word to a long (`.l`). |
| `fn (mut m M68k) add(size Size, src Ea, dst Ea)` | add adds src to dst. |
| `fn (mut m M68k) sub(size Size, src Ea, dst Ea)` | sub subtracts src from dst. |
| `fn (mut m M68k) cmp(size Size, src Ea, dst Ea)` | cmp sets the flags of dst - src. |
| `fn (mut m M68k) and(size Size, src Ea, dst Ea)` | and keeps the bits set in both. |
| `fn (mut m M68k) orr(size Size, src Ea, dst Ea)` | orr is `or`: it keeps the bits set in either. |
| `fn (mut m M68k) eor(size Size, src Ea, dst Ea)` | eor flips the bits set in src. |
| `fn (mut m M68k) mulu(src Ea, dst Ea)` | mulu multiplies two unsigned words into a long. |
| `fn (mut m M68k) muls(src Ea, dst Ea)` | muls multiplies two signed words into a long. |
| `fn (mut m M68k) divu(src Ea, dst Ea)` | divu divides a long by a word: quotient in the low word, remainder above. |
| `fn (mut m M68k) asl(size Size, count Ea, dst Ea)` | asl shifts left, arithmetically. |
| `fn (mut m M68k) asr(size Size, count Ea, dst Ea)` | asr shifts right, keeping the sign. |
| `fn (mut m M68k) lsl(size Size, count Ea, dst Ea)` | lsl shifts left, filling with zeroes. |
| `fn (mut m M68k) lsr(size Size, count Ea, dst Ea)` | lsr shifts right, filling with zeroes. |
| `fn (mut m M68k) roxl(size Size, count Ea, dst Ea)` | roxl rotates left through the X flag. |
| `fn (mut m M68k) rol(size Size, count Ea, dst Ea)` | rol rotates left. |
| `fn (mut m M68k) ror(size Size, count Ea, dst Ea)` | ror rotates right. |
| `fn (mut m M68k) btst(n int, dst Ea)` | btst sets Z when a bit is clear. |
| `fn (mut m M68k) bclr(n int, dst Ea)` | bclr tests a bit, then clears it. |
| `fn (mut m M68k) bset(n int, dst Ea)` | bset tests a bit, then sets it. |
| `fn (mut m M68k) bra(name string)` | bra jumps to a label. |
| `fn (mut m M68k) bsr(name string)` | bsr calls a subroutine. |
| `fn (mut m M68k) b(cc Cc, name string)` | b branches when the condition holds. |
| `fn (mut m M68k) dbra(counter Ea, name string)` | dbra counts a data register's low word down and branches until it passes zero: the loop body runs count + 1 times. |
| `fn (mut m M68k) jmp(target Ea)` | jmp continues at target. |
| `fn (mut m M68k) jsr(target Ea)` | jsr calls the subroutine at target. |
| `fn (mut m M68k) rts()` | rts returns from a subroutine. |
| `fn (mut m M68k) rte()` | rte returns from an interrupt. |
| `fn (mut m M68k) nop()` | nop does nothing. |
| `fn (mut m M68k) stop(status int)` | stop loads the status register and waits for an interrupt. |

## The GPU and DSP assembler

`jagkit/risc.v`

| Declaration | |
|---|---|
| `enum Reg` | Reg is one of the 32 registers of the GPU or the DSP. |
| `enum Cond` | Cond is the condition of a RISC jump. After `cmp a,b` (which computes b - a) `cs` means b < a unsigned and `mi` means b < a signed. |
| `struct Risc` | Risc assembles a program for the GPU or the DSP. Both share one instruction format; the few opcodes that differ have their own methods. Mistakes (a quick value out of range, an unknown label) are collected and reported together by `assemble`. |
| `fn new_risc(origin u32) &Risc` | new_risc starts a program that will run at `origin`. |
| `fn (r &Risc) here() u32` | here is the address of the next word to be emitted. |
| `fn (mut r Risc) label(name string)` | label names the current address. |
| `fn (r &Risc) address_of(name string) u32` | address_of returns the address of a label that is already defined. |
| `fn (mut r Risc) assemble() ![]u8` | assemble resolves the labels and returns the program, big-endian. |
| `fn (mut r Risc) add(src Reg, dst Reg)` | add adds src to dst. |
| `fn (mut r Risc) addc(src Reg, dst Reg)` | addc adds src and the carry to dst. |
| `fn (mut r Risc) addq(n int, dst Reg)` | addq adds 1..32. |
| `fn (mut r Risc) addqt(n int, dst Reg)` | addqt adds without changing the flags. |
| `fn (mut r Risc) sub(src Reg, dst Reg)` | sub subtracts src from dst. |
| `fn (mut r Risc) subc(src Reg, dst Reg)` | subc subtracts src and the carry from dst. |
| `fn (mut r Risc) subq(n int, dst Reg)` | subq subtracts 1..32. |
| `fn (mut r Risc) subqt(n int, dst Reg)` | subqt subtracts without changing the flags. |
| `fn (mut r Risc) neg(dst Reg)` | neg negates dst. |
| `fn (mut r Risc) and(src Reg, dst Reg)` | and keeps the bits set in both. |
| `fn (mut r Risc) orr(src Reg, dst Reg)` | orr is `or`: it keeps the bits set in either. |
| `fn (mut r Risc) xor(src Reg, dst Reg)` | xor flips the bits set in src. |
| `fn (mut r Risc) not(dst Reg)` | not flips every bit of dst. |
| `fn (mut r Risc) btst(n int, dst Reg)` | btst sets Z when bit n is clear. |
| `fn (mut r Risc) bset(n int, dst Reg)` | bset sets bit n. |
| `fn (mut r Risc) bclr(n int, dst Reg)` | bclr clears bit n. |
| `fn (mut r Risc) mult(src Reg, dst Reg)` | mult multiplies the low 16 bits of both, unsigned, into 32 bits. |
| `fn (mut r Risc) imult(src Reg, dst Reg)` | imult multiplies the low 16 bits of both, signed, into 32 bits. |
| `fn (mut r Risc) div(src Reg, dst Reg)` | div divides dst by src, unsigned. |
| `fn (mut r Risc) abs(dst Reg)` | abs makes dst positive. |
| `fn (mut r Risc) shlq(n int, dst Reg)` | shlq shifts left by 1..32. |
| `fn (mut r Risc) shrq(n int, dst Reg)` | shrq shifts right by 1..32, filling with zeroes. |
| `fn (mut r Risc) sharq(n int, dst Reg)` | sharq shifts right by 1..32, keeping the sign. |
| `fn (mut r Risc) rorq(n int, dst Reg)` | rorq rotates right by 1..32. |
| `fn (mut r Risc) cmp(src Reg, dst Reg)` | cmp sets the flags of dst - src. |
| `fn (mut r Risc) cmpq(n int, dst Reg)` | cmpq sets the flags of dst - n for n in -16..15. |
| `fn (mut r Risc) move(src Reg, dst Reg)` | move copies src to dst. |
| `fn (mut r Risc) moveq(n int, dst Reg)` | moveq loads 0..31. |
| `fn (mut r Risc) movei(value u32, dst Reg)` | movei loads any 32-bit value. It takes three words and must not sit in the delay slot of a jump. |
| `fn (mut r Risc) movei_label(name string, dst Reg)` | movei_label loads the address of a label. |
| `fn (mut r Risc) move_pc(dst Reg)` | move_pc copies the address of this instruction. |
| `fn (mut r Risc) loadb(addr Reg, dst Reg)` | loadb reads a byte. |
| `fn (mut r Risc) loadw(addr Reg, dst Reg)` | loadw reads a word. |
| `fn (mut r Risc) load(addr Reg, dst Reg)` | load reads a long. |
| `fn (mut r Risc) storeb(src Reg, addr Reg)` | storeb writes a byte. |
| `fn (mut r Risc) storew(src Reg, addr Reg)` | storew writes a word. |
| `fn (mut r Risc) store(src Reg, addr Reg)` | store writes a long. |
| `fn (mut r Risc) load_r14(offset int, dst Reg)` | load_r14 reads the long at r14 + offset; the offset is 4..128. |
| `fn (mut r Risc) store_r14(src Reg, offset int)` | store_r14 writes a long to r14 + offset; the offset is 4..128. |
| `fn (mut r Risc) jr(cond Cond, name string)` | jr jumps to a label at most 16 words back or 15 words ahead. |
| `fn (mut r Risc) jump(cond Cond, addr Reg)` | jump goes to the address in a register. |
| `fn (mut r Risc) nop()` | nop does nothing. |
| `fn (mut r Risc) align_long()` | align_long pads with zero words to a multiple of four bytes. |
| `fn (mut r Risc) long(value u32)` | long emits a 32-bit constant. |
| `fn (mut r Risc) pad_to(address u32)` | pad_to emits zero words up to `address`. |

## Ready-made 68000 subroutines

`jagkit/routines.v`

| Declaration | |
|---|---|
| `const pad_fire = 0` | Bits of the pad, as `read_pad` reports them. A, B or C |
| `const pad_a = 1` |  |
| `const pad_b = 2` |  |
| `const pad_c = 3` |  |
| `const pad_up = 4` |  |
| `const pad_down = 5` |  |
| `const pad_left = 6` |  |
| `const pad_right = 7` |  |
| `fn (mut m M68k) pad_reader()` | pad_reader emits the subroutine `read_pad` and two word variables it keeps up to date: `pad`, the buttons of the first controller that are held, and `pressed`, the ones that went down since the last call. Call it once a frame. It changes d0 and d1. |
| `struct TextScreen` | TextScreen is a picture made of 8x8 character cells, one bit a pixel, somewhere in RAM. |
| `fn (t TextScreen) bytes() int` | bytes is the size of the screen in memory. |
| `fn (t TextScreen) bitmap(x int, y int, colour int) Bitmap` | bitmap is the object that shows the screen with its top left corner at (x, y). The letters have colour `colour` of the colour table, which must be odd; everything else is transparent. |
| `fn (mut m M68k) text_routines(screen TextScreen)` | text_routines emits the font and three subroutines for a text screen:  print       draws the zero-terminated string at a0 at column d0, row d1. number      turns d0 (0..65535) into `digits` digits and leaves a0 pointing at them, ready for `print`. clear_text  blanks the screen.  They change d0..d3 and a0..a3. The font has capitals, digits and punctuation only. |
| `fn (mut m M68k) print_at(column int, row int, text string)` | print_at emits a call that prints a string constant at a text cell. The string is stored in line, with a branch around it. |

## Display lists

`jagkit/objects.v`

| Declaration | |
|---|---|
| `enum Depth` | Depth is the pixel size of a bitmap object. Up to 8 bits a pixel selects a colour from the palette; 16 bits are a colour themselves. |
| `fn (d Depth) bits() int` | bits is the number of bits per pixel. |
| `struct Bitmap` | Bitmap describes one picture for the object processor. |
| `struct ObjectList` | ObjectList is a display list ready to be copied to its address. |
| `fn object_list(base u32, video Video, bitmaps []Bitmap) !ObjectList` | object_list lays out a display list for the address `base`, which must be a multiple of 32. The object processor rewrites the list while it draws, so a program copies a fresh one into place every frame.  The list starts with two branches that send the object processor to a stop object on the lines outside the display. |

## Images, byte order and colour

`jagkit/image.v`

| Declaration | |
|---|---|
| `fn jag_image(load u32, entry u32, payload []u8) []u8` | jag_image wraps a program in a Jaguar Server header (`JAGR`, type 3): the payload is loaded into RAM at `load` and started at `entry`. |
| `fn write_jag(path string, load u32, entry u32, payload []u8) !` | write_jag writes a program as a `.jag` file. |
| `fn big_endian16(words []u16) []u8` | big_endian16 serialises words the way the Jaguar reads them. |
| `fn big_endian32(longs []u32) []u8` | big_endian32 serialises longs the way the Jaguar reads them. |
| `fn cry(r int, g int, b int) u16` | cry returns the CRY pixel nearest to an RGB colour, each part 0..255. CRY keeps the brightness in its low byte and one of 256 hues in its high byte, so scaling the low byte fades a colour without changing it. |

## Memory layout

`jagkit/memory.v`

| Declaration | |
|---|---|
| `const ram_size = 0x200000` | ram_size is the Jaguar's main memory: two megabytes from address 0. |
| `struct Region` | Region is a stretch of main memory a program uses: the image itself, a picture buffer, a display list. |
| `fn check_regions(regions []Region) !` | check_regions makes sure that every region lies in main memory and that no two share a byte. Nothing on the Jaguar stops a program from drawing over its own code; this is the check to make at build time, with the image as one of the regions. |

## The font

`jagkit/font.v`

| Declaration | |
|---|---|
| `const font_first = 32` | font_first is the character code of the font's first glyph. |
| `fn font_8x8() []u8` | font_8x8 is the font as 8x8 cells, one byte a row, for ASCII 32..95: capitals, digits and punctuation. The glyph of character c starts at (c - font_first) * 8. |
| `fn glyph(c u8) []int` | glyph returns the seven rows of a character, five bits each with the left pixel in bit 4; a character the font lacks is blank. |

## The DSP synthesizer

`jagkit/synth.v`

| Declaration | |
|---|---|
| `const voice_bass_step = 4` | Offsets of the voice settings from the `voices` label of the DSP program. added to the phase every sample |
| `const voice_bass_volume = 8` |  |
| `const voice_lead_step = 12` |  |
| `const voice_lead_volume = 16` |  |
| `const voice_noise_volume = 20` |  |
| `const synth_sclk = 19` | synth_sclk sets the sample rate: about 20.8 kHz. |
| `fn synth() &Risc` | synth is the DSP program: start-up code and the sample interrupt. Start it at its `start` label; its settings are at its `voices` label. |
| `fn hertz_step(hertz f64) u32` | hertz_step is what a voice adds to its 32-bit phase every sample to sound a frequency. |
| `fn note_step(note int) u32` | note_step is the same for a MIDI note. |

## Hardware registers and video timing

`jagkit/hardware.v`

| Declaration | |
|---|---|
| `const olp = u32(0xf00020)` | TOM: video and the object processor. object list pointer, written with its words swapped |
| `const vmode = u32(0xf00028)` |  |
| `const bord1 = u32(0xf0002a)` |  |
| `const bord2 = u32(0xf0002c)` |  |
| `const hdb1 = u32(0xf00038)` |  |
| `const hdb2 = u32(0xf0003a)` |  |
| `const hde = u32(0xf0003c)` |  |
| `const vdb = u32(0xf00046)` |  |
| `const vde = u32(0xf00048)` |  |
| `const vi = u32(0xf0004e)` | half-line of the vertical interrupt |
| `const bg = u32(0xf00058)` |  |
| `const int1 = u32(0xf000e0)` | interrupt enables (low byte) and acknowledges (high byte) |
| `const int2 = u32(0xf000e2)` | written to let the next interrupt through |
| `const clut = u32(0xf00400)` | 256 colours, one word each |
| `const vmode_cry16 = 0x06c1` | vmode_cry16 is 16-bit CRY at four clocks per pixel, video on. |
| `const int1_video = 0x0001` |  |
| `const int1_video_ack = 0x0100` |  |
| `const g_flags = u32(0xf02100)` | The GPU. |
| `const g_pc = u32(0xf02110)` |  |
| `const g_ctrl = u32(0xf02114)` |  |
| `const gpu_ram = u32(0xf03000)` |  |
| `const gpu_ram_size = 0x1000` |  |
| `const joystick = u32(0xf14000)` | JERRY: controllers, sound and the DSP. row select on write, columns on read |
| `const joybuts = u32(0xf14002)` | fire buttons; bit 4 is set on NTSC machines |
| `const d_flags = u32(0xf1a100)` |  |
| `const d_pc = u32(0xf1a110)` |  |
| `const d_ctrl = u32(0xf1a114)` |  |
| `const l_dac = u32(0xf1a148)` |  |
| `const r_dac = u32(0xf1a14c)` |  |
| `const sclk = u32(0xf1a150)` |  |
| `const smode = u32(0xf1a154)` |  |
| `const dsp_ram = u32(0xf1b000)` |  |
| `const dsp_ram_size = 0x2000` |  |
| `const joystick_enable = 0x8100` | joystick_enable drives the row-select outputs and unmutes the sound; the low nibble selects one row of the first controller, active low. |
| `const interrupt_vector = u32(0x100)` | The 68000 vector every Jaguar interrupt arrives through. |
| `const risc_go = 1` | risc_go is written to G_CTRL or D_CTRL to start the processor. |
| `const flag_imask = 3` | DSP flag bits used by an interrupt handler. |
| `const dsp_flag_i2s_enable = 5` |  |
| `const dsp_flag_i2s_clear = 10` |  |
| `const dsp_i2s_vector = u32(0xf1b010)` | dsp_i2s_vector is where the DSP enters its sample interrupt handler. |
| `const smode_internal = 0x15` | smode_internal is the usual serial mode: clock from SCLK, word strobe on. |
| `struct Video` | Video is the display timing of one television standard, as the boot ROM would have set it up. |
| `const ntsc = video_timing('NTSC', 1409, 241, 823, 266, 26_590_906)` |  |
| `const pal = video_timing('PAL', 1381, 287, 843, 322, 26_593_900)` |  |
| `fn (v Video) sample_rate(sclk_value int) f64` | sample_rate is the DSP's sample interrupt frequency for a value of SCLK. |
