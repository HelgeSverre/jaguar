// Headless command-line front end shared by the desktop app and the test
// runner. Nothing in this module needs a window, audio device or SDL.
module cli

import os
import hwtypes
import loader
import machine

// Session is one image loaded into a powered-on machine.
pub struct Session {
pub:
	path string
	plan loader.LoadPlan
pub mut:
	machine &machine.Machine = unsafe { nil }
}

// ImageOptions are the user's overrides for image detection and the machine.
pub struct ImageOptions {
pub:
	region    hwtypes.Region = .ntsc
	format    ?loader.ImageKind
	load_addr ?u32
	entry     ?u32
}

// open_session reads an image, validates its load plan and direct-boots it.
// The file is never modified.
pub fn open_session(path string, opts ImageOptions) !Session {
	image := os.read_bytes(path) or { return error('cannot read ${path}: ${err.msg()}') }
	plan := loader.plan(image, loader.Options{
		format:    opts.format
		load_addr: opts.load_addr
		entry:     opts.entry
	})!
	mut m := machine.new(machine.Config{ region: opts.region })
	m.load_direct(plan)
	return Session{
		path:    path
		plan:    plan
		machine: m
	}
}

// parse_region maps a command-line value to a television standard.
fn parse_region(name string) !hwtypes.Region {
	return match name.to_lower() {
		'ntsc' { hwtypes.Region.ntsc }
		'pal' { hwtypes.Region.pal }
		else { error('unknown region "${name}": expected ntsc or pal') }
	}
}

// parse_format maps a command-line value to an image kind.
fn parse_format(name string) !loader.ImageKind {
	return match name.to_lower() {
		'cart', 'cartridge', 'j64' { loader.ImageKind.cartridge }
		'jagserver', 'jagr' { loader.ImageKind.jaguar_server }
		'abs' { loader.ImageKind.dri_abs }
		'coff', 'cof' { loader.ImageKind.coff }
		'rom', 'alpine' { loader.ImageKind.alpine_rom }
		'raw', 'bin' { loader.ImageKind.raw_binary }
		else { error('unknown format "${name}"') }
	}
}

// parse_address accepts decimal or 0x-prefixed hexadecimal.
fn parse_address(text string) !u32 {
	value := text.parse_uint(0, 32) or { return error('invalid address "${text}"') }
	return u32(value)
}
