module cli

import os

// save_path returns where the cartridge EEPROM of an image is persisted:
// keyed by the normalized content hash, so renaming an image keeps its save.
pub fn save_path(normalized_hash string) string {
	return os.join_path(os.data_dir(), 'vjag', 'saves', '${normalized_hash}.eeprom')
}

// load_save loads a persisted EEPROM image into the session, if one exists.
pub fn load_save(mut session Session) ! {
	path := save_path(session.plan.normalized_hash)
	if !os.exists(path) {
		return
	}
	bytes := os.read_bytes(path)!
	session.machine.eeprom.load_bytes(bytes)!
}

// flush_save persists the EEPROM when it has unsaved changes. The file is
// replaced atomically; on failure the data stays dirty in memory so a later
// flush can retry, and the previous file is left untouched.
pub fn flush_save(mut session Session) ! {
	if !session.machine.eeprom.dirty {
		return
	}
	path := save_path(session.plan.normalized_hash)
	os.mkdir_all(os.dir(path))!
	temporary := '${path}.tmp'
	os.write_file_array(temporary, session.machine.eeprom.to_bytes())!
	os.mv(temporary, path)!
	session.machine.eeprom.dirty = false
}
