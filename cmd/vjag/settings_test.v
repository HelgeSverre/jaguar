module main

import os

fn test_missing_settings_give_the_defaults() {
	settings := load_settings(os.join_path(os.temp_dir(), 'vjag-no-such-config.toml'))
	assert settings.shell
	assert settings.shell_scale == 0.75
}

fn test_settings_survive_a_round_trip() {
	path := os.join_path(os.temp_dir(), 'vjag-settings-test-${os.getpid()}', 'config.toml')
	defer {
		os.rmdir_all(os.dir(path)) or {}
	}

	Settings{
		shell:       false
		shell_scale: 0.5
	}.save(path)!
	settings := load_settings(path)
	assert !settings.shell
	assert settings.shell_scale == 0.5
}

fn test_an_absurd_scale_is_clamped() {
	path := os.join_path(os.temp_dir(), 'vjag-settings-clamp-${os.getpid()}.toml')
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'shell_scale = 40.0\n')!
	assert load_settings(path).shell_scale == shell_scale_max
}
