module main

import os
import toml

const shell_scale_min = f32(0.375)
const shell_scale_max = f32(1.25)
const shell_scale_step = f32(0.125)

// Settings are the frontend preferences kept between runs.
struct Settings {
mut:
	shell       bool = true // dress the window as a console
	shell_scale f32  = 0.75 // window points per pixel of the shell artwork
}

// settings_path is where the preferences live: `vjag/config.toml` in the
// user's configuration directory.
fn settings_path() string {
	return os.join_path(os.config_dir() or { os.home_dir() }, 'vjag', 'config.toml')
}

// load_settings reads the preferences. A missing or unreadable file gives
// the defaults; a bad value falls back to its default.
fn load_settings(path string) Settings {
	defaults := Settings{}
	doc := toml.parse_file(path) or { return defaults }
	return Settings{
		shell:       doc.value('shell').default_to(defaults.shell).bool()
		shell_scale: clamp_scale(f32(doc.value('shell_scale').default_to(f64(defaults.shell_scale)).f64()))
	}
}

// save writes the preferences, replacing the file atomically.
fn (s Settings) save(path string) ! {
	os.mkdir_all(os.dir(path))!
	temporary := '${path}.tmp'
	os.write_file(temporary,
		'# vjag settings\n\n# Draw the console shell around the picture (F2 toggles it).\nshell = ${s.shell}\n\n# Size of the shell; [ and ] change it.\nshell_scale = ${s.shell_scale}\n')!
	os.mv(temporary, path)!
}

fn clamp_scale(scale f32) f32 {
	if scale < shell_scale_min {
		return shell_scale_min
	}
	if scale > shell_scale_max {
		return shell_scale_max
	}
	return scale
}
