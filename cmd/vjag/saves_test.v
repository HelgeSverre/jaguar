module main

import os
import cli

fn test_failed_save_keeps_the_session_for_reset_switch_and_quit_then_retries() {
	dir := os.join_path(os.temp_dir(), 'vjag_save_failure_${os.getpid()}')
	os.mkdir_all(dir)!
	previous := os.getenv('XDG_DATA_HOME')
	os.setenv('XDG_DATA_HOME', dir, true)
	defer {
		if previous == '' {
			os.unsetenv('XDG_DATA_HOME')
		} else {
			os.setenv('XDG_DATA_HOME', previous, true)
		}
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'test.bin')
	other := os.join_path(dir, 'other.bin')
	os.write_file_array(path, [u8(0x60), 0xfe])!
	os.write_file_array(other, [u8(0x4e), 0x71, 0x60, 0xfc])!
	mut app := App{
		session: cli.open_session(path, cli.ImageOptions{})!
	}
	app.session.machine.eeprom.words[0] = 0x1234
	app.session.machine.eeprom.dirty = true
	cli.flush_save(mut app.session)!
	app.session.machine.eeprom.words[0] = 0x5678
	app.session.machine.eeprom.dirty = true
	original := app.session.machine
	blocked := cli.save_path(app.session.plan.normalized_hash) + '.tmp'
	os.mkdir(blocked)!
	app.command(.reset, true)
	assert voidptr(app.session.machine) == voidptr(original)
	assert app.session.machine.eeprom.words[0] == 0x5678
	assert app.session.machine.eeprom.dirty
	app.load(other)
	assert voidptr(app.session.machine) == voidptr(original)
	app.command(.quit, true)
	assert app.running
	assert app.notice != ''
	assert app.overlay_lines().len > 0, 'a save error must be visible without the debug overlay'
	os.rmdir(blocked)!
	app.command(.reset, true)
	assert voidptr(app.session.machine) != voidptr(original)
	assert app.session.machine.eeprom.words[0] == 0x5678
	assert !app.session.machine.eeprom.dirty
	app.command(.quit, true)
	assert !app.running
}
