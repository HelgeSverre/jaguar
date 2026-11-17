module sdl

import os
import toml

// Names are positional, independent of the labels printed on a controller.
const control_names = ['south', 'east', 'west', 'north', 'back', 'guide', 'start', 'leftstick',
	'rightstick', 'leftshoulder', 'rightshoulder', 'dpup', 'dpdown', 'dpleft', 'dpright', 'misc1',
	'rightpaddle1', 'leftpaddle1', 'rightpaddle2', 'leftpaddle2', 'touchpad', 'misc2', 'misc3',
	'misc4', 'misc5', 'misc6']!
const axis_names = ['leftx', 'lefty', 'rightx', 'righty', 'lefttrigger', 'righttrigger']!
// First 21 entries deliberately follow jerry.Button's matrix order.
const target_names = ['up', 'down', 'left', 'right', 'star', 'seven', 'four', 'one', 'zero', 'eight',
	'five', 'two', 'hash', 'nine', 'six', 'three', 'a', 'b', 'c', 'option', 'pause', 'keypad']!

struct Binding {
	target int
	chord  u64
}

struct ControllerProfile {
mut:
	expressions []string
	bindings    []Binding
	press       int = 9830
	release     int = 6553
}

fn default_profile() ControllerProfile {
	mut p := ControllerProfile{
		expressions: ['dpup|lefty_neg', 'dpdown|lefty_pos', 'dpleft|leftx_neg', 'dpright|leftx_pos',
			'leftshoulder', '', '', '', '', '', '', '', 'rightshoulder', '', '', '', 'east', 'south',
			'west', 'north|back', 'start', 'lefttrigger']
	}
	p.compile() or { panic(err) }
	return p
}

fn control_bit(name string) !u64 {
	for i, label in control_names {
		if name == label { return u64(1) << i }
	}
	for axis, label in axis_names {
		if axis >= 4 && name == label { return u64(1) << (33 + axis * 2) }
		if axis < 4 {
			if name == '${label}_neg' { return u64(1) << (32 + axis * 2) }
			if name == '${label}_pos' { return u64(1) << (33 + axis * 2) }
		}
	}
	return error('Unknown control: ${name}')
}

fn chord_mask(expression string) !u64 {
	mut mask := u64(0)
	for part in expression.split('+') {
		mask |= control_bit(part.trim_space())!
	}
	return mask
}

fn (mut p ControllerProfile) compile() ! {
	mut bindings := []Binding{}
	for target, expression in p.expressions {
		if expression.trim_space() == '' {
			continue
		}
		for chord in expression.split('|') {
			mask := chord_mask(chord)!
			if target == 21 && mask & ((u64(15) << 11) | (u64(15) << 36) | 1) != 0 {
				return error('Keypad shortcut must leave South, d-pad and right stick axes free')
			}
			bindings << Binding{
				target: target
				chord:  mask
			}
		}
	}
	p.bindings = bindings
}

fn (p &ControllerProfile) consumed(controls u64) u64 {
	mut consumed := u64(0)
	for binding in p.bindings {
		if binding.chord & (binding.chord - 1) != 0 && controls & binding.chord == binding.chord {
			consumed |= binding.chord
		}
	}
	return consumed
}

fn (p &ControllerProfile) targets(controls u64) u32 {
	mut result := u32(0)
	consumed := p.consumed(controls)
	for binding in p.bindings {
		// A modifier chord takes precedence over its individual buttons. Two
		// targets bound to the same chord can still hold a keypad combination.
		if binding.chord & (binding.chord - 1) == 0 && binding.chord & consumed != 0 {
			continue
		}
		if controls & binding.chord == binding.chord { result |= u32(1) << binding.target }
	}
	return result
}

fn controls_text(mask u64) string {
	mut names := []string{}
	for i, name in control_names {
		if mask & (u64(1) << i) != 0 { names << name }
	}
	for axis, name in axis_names {
		if axis < 4 && mask & (u64(1) << (32 + axis * 2)) != 0 { names << '${name}_neg' }
		if mask & (u64(1) << (33 + axis * 2)) != 0 {
			names << if axis < 4 { '${name}_pos' } else { name }
		}
	}
	return names.join('+')
}

// Separate from shell preferences so changing window settings cannot erase bindings.
struct ControllerConfig {
mut:
	path      string
	profiles  map[string]ControllerProfile
	preferred [2]string
	notice    string
	read_only bool
}

fn load_controller_config(path string) ControllerConfig {
	mut config := ControllerConfig{
		path: path
	}
	if !os.exists(path) { return config }
	doc := toml.parse_file(path) or {
		config.notice = 'Cannot read controls config: ${err.msg()}'
		config.read_only = true
		return config
	}
	for port in 0 .. 2 {
		config.preferred[port] = doc.value('player${port + 1}').default_to('').string()
	}
	for key, value in doc.value('profiles').as_map() {
		// Profile keys are global_1/2 or a normalized image hash plus port.
		if key.len > 80 || !key.bytes().all(it.is_alnum() || it == `_`) {
			continue
		}
		mut p := default_profile()
		press := value.value('press').default_to(30).int()
		release := value.value('release').default_to(20).int()
		if release >= 0 && release < press && press <= 100 {
			p.press = press * 32767 / 100
			p.release = release * 32767 / 100
		} else {
			config.notice = 'Invalid dead zone in ${key}; using 30/20 percent'
		}
		for i, name in target_names {
			expression := value.value(name).default_to(p.expressions[i]).string()
			previous := p.expressions[i]
			p.expressions[i] = expression
			p.compile() or {
				p.expressions[i] = previous
				config.notice = 'Invalid binding ${key}.${name}; using default'
			}
		}
		p.compile() or { panic(err) }
		config.profiles[key] = p
	}
	return config
}

fn (c &ControllerConfig) profile(game string, port int) ControllerProfile {
	if game != '' {
		if p := c.profiles['${game}_${port + 1}'] { return p.copy() }
	}
	p := c.profiles['global_${port + 1}'] or { return default_profile() }
	return p.copy()
}

fn (p &ControllerProfile) copy() ControllerProfile {
	return ControllerProfile{
		expressions: p.expressions.clone()
		bindings:    p.bindings.clone()
		press:       p.press
		release:     p.release
	}
}

fn quoted(value string) string {
	return '"' +
		value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') +
		'"'
}

fn (c &ControllerConfig) save() ! {
	if c.path == '' { return }
	if c.read_only { return error('Fix the unreadable controllers.toml before saving') }
	mut lines := [
		'# vjag controller bindings: + joins a chord; | adds an alternative.',
		'player1 = ${quoted(c.preferred[0])}',
		'player2 = ${quoted(c.preferred[1])}',
	]
	mut keys := c.profiles.keys()
	keys.sort()
	for key in keys {
		p := c.profiles[key]
		lines << ['', '[profiles.${key}]', 'press = ${(p.press * 100 + 16383) / 32767}',
			'release = ${(p.release * 100 + 16383) / 32767}']
		for i, name in target_names {
			lines << '${name} = ${quoted(p.expressions[i])}'
		}
	}
	os.mkdir_all(os.dir(c.path))!
	os.write_file(c.path + '.tmp', lines.join('\n') + '\n')!
	os.mv(c.path + '.tmp', c.path)!
}
