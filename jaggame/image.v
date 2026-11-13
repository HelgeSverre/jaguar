module jaggame

import jagkit { imm, lbl }

// load_address is where a plain image is loaded; the stack grows down
// from it.
pub const load_address = u32(0x4000)

// Image is a compiled program ready for the emulator, with its symbols
// and what is needed to read its variables back.
pub struct Image {
	low &Lowered
pub:
	bytes   []u8 // the .jag file
	payload []u8 // the program as it is in memory from load_address
	symbols map[string]u32
	done    u32 // the byte set to 1 when the entry function has returned
}

// plain_image compiles a program into an image that calls `entry` once,
// sets the byte at `done` to 1 and then waits forever. It sets up nothing
// else: no video, no interrupts. It is what tests and plain computations
// run.
pub fn (p &Program) plain_image(entry Func) !Image {
	if entry.params.len > 0 || entry.ret != .void {
		return error('the entry function `${entry.name}` must take no parameters and return nothing')
	}
	mut m := jagkit.new_m68k(load_address)
	m.label('jaggame.start')
	m.move_to_sr(imm(0x2700))
	m.lea(jagkit.abs(load_address), sp)
	m.jsr(lbl(entry.name))
	m.move(.b, imm(1), lbl('jaggame.done'))
	m.label('jaggame.idle')
	m.bra('jaggame.idle')
	low := p.emit_lowered(mut m)!
	m.label('jaggame.done')
	m.byte(0)
	m.align(2)
	payload := m.assemble() or { return error('jaggame compiler bug: ${err.msg()}') }
	jagkit.check_regions([
		jagkit.Region{'stack and vectors', 0, int(load_address)},
		jagkit.Region{'image', load_address, payload.len},
	])!
	return Image{
		low:     low
		bytes:   jagkit.jag_image(load_address, m.address_of('jaggame.start'), payload)
		payload: payload
		symbols: m.symbols()
		done:    m.address_of('jaggame.done')
	}
}

// read_raw reads a value of a type from memory, big-endian. A bool is
// returned as the byte it is, so that a stray value shows.
fn read_raw(ram []u8, address u32, t Type) i64 {
	mut raw := u64(0)
	for i in 0 .. t.size() {
		raw = (raw << 8) | ram[address + u32(i)]
	}
	if t == .bool {
		return i64(raw)
	}
	return t.wrap(i64(raw))
}

// slot_value reads one of the values the interpreter keeps for a variable,
// numbered the same way.
fn (img &Image) slot_value(ram []u8, var int, slot int) i64 {
	v := img.low.vars[var]
	base := img.symbols[v.label]
	if v.kind == .records {
		r := img.low.records[v.record]
		i := slot / r.fields.len
		f := slot % r.fields.len
		return read_raw(ram, base + u32(i * r.size + r.offsets[f]), r.fields[f].typ)
	}
	return read_raw(ram, base + u32(slot * v.typ.size()), v.typ)
}

// value is the raw value of a global variable, read from the machine's
// memory.
pub fn (img &Image) value(ram []u8, name string) !i64 {
	return img.element(ram, name, 0)
}

// element is the raw value of an element of a global array or table.
pub fn (img &Image) element(ram []u8, name string, index int) !i64 {
	var := img.low.var_named(name)
	if var < 0 || img.low.vars[var].kind == .records {
		return error('there is no global variable, array or table `${name}`')
	}
	if index < 0 || index >= img.low.vars[var].len {
		return error('`${name}` has no element ${index}')
	}
	return img.slot_value(ram, var, index)
}

// field is the raw value of a field of an element of an array of records.
pub fn (img &Image) field(ram []u8, name string, index int, field string) !i64 {
	var := img.low.var_named(name)
	if var < 0 || img.low.vars[var].kind != .records {
		return error('there is no array of records `${name}`')
	}
	r := img.low.records[img.low.vars[var].record]
	f := r.field_index(field)
	if f < 0 || index < 0 || index >= img.low.vars[var].len {
		return error('`${name}` has no element ${index} with a field `${field}`')
	}
	return img.slot_value(ram, var, index * r.fields.len + f)
}
