class_name FirstDaySave
extends RefCounted

## Atomic, recoverable persistence for FirstDaySession.
## A valid .tmp file is treated as an interrupted newer save and is promoted on
## load before the primary or .bak candidates are considered.

const SCHEMA_VERSION := 2
const DEFAULT_SAVE_PATH := "user://first_day_session.json"

const M2SessionMigrationScript := preload("res://game/first_day/first_day_session_migration.gd")


static func save_session(session: FirstDaySession, path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	var resolved := _resolve_path(path)
	if not bool(resolved.get("ok", false)):
		return resolved
	var absolute_path := String(resolved["path"])
	if session == null:
		return _failure("session_is_null", "FirstDaySession cannot be null.", absolute_path)
	var validation := session.validate()
	if not bool(validation.get("ok", false)):
		return _failure("session_validation_failed", "FirstDaySession is invalid and was not saved.", absolute_path, {"validation": validation})
	var envelope := {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"flow_revision": session.flow_revision,
		"session": session.to_dict(),
	}
	var payload := JSON.stringify(envelope, "\t", true, true) + "\n"
	var payload_validation := _parse_and_validate(payload, absolute_path + ":memory")
	if not bool(payload_validation.get("ok", false)):
		return _failure("serialization_validation_failed", "Serialized session did not survive a JSON round trip.", absolute_path, {"cause": payload_validation})

	var directory_path := absolute_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory_path):
		var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if directory_error != OK:
			return _failure("directory_creation_failed", "Could not create the save directory.", absolute_path, {"engine_error": directory_error})
	var temporary_path := absolute_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		var pending := _read_and_validate(temporary_path)
		if bool(pending.get("ok", false)):
			return _failure(
				"pending_temporary_recovery",
				"A valid interrupted session save is waiting for recovery. Load before saving again.",
				absolute_path,
				{"temporary_path": temporary_path}
			)
		var stale_remove := DirAccess.remove_absolute(temporary_path)
		if stale_remove != OK:
			return _failure("stale_temporary_remove_failed", "Could not remove an invalid temporary save.", absolute_path, {"engine_error": stale_remove})

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("temporary_open_failed", "Could not open the temporary session save.", absolute_path, {"engine_error": FileAccess.get_open_error()})
	file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		_remove_if_present(temporary_path)
		return _failure("temporary_write_failed", "Could not finish writing the temporary session save.", absolute_path, {"engine_error": write_error})
	var temporary_validation := _read_and_validate(temporary_path)
	if not bool(temporary_validation.get("ok", false)):
		_remove_if_present(temporary_path)
		return _failure("temporary_validation_failed", "Temporary session save failed read-back validation.", absolute_path, {"cause": temporary_validation})
	var replacement := _replace_with_backup(temporary_path, absolute_path)
	if not bool(replacement.get("ok", false)):
		return replacement
	var installed := _read_and_validate(absolute_path)
	if not bool(installed.get("ok", false)):
		var rollback := _restore_backup(absolute_path)
		return _failure("installed_save_invalid", "Installed session save failed validation.", absolute_path, {"cause": installed, "rollback": rollback})
	return _success({
		"path": absolute_path,
		"requested_path": path,
		"schema_version": SCHEMA_VERSION,
		"flow_revision": session.flow_revision,
		"bytes_written": payload.to_utf8_buffer().size(),
		"backup_created": bool(replacement.get("backup_created", false)),
	})


static func load_session(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	var resolved := _resolve_path(path)
	if not bool(resolved.get("ok", false)):
		return resolved
	var absolute_path := String(resolved["path"])
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var has_primary := FileAccess.file_exists(absolute_path)
	var has_temporary := FileAccess.file_exists(temporary_path)
	var has_backup := FileAccess.file_exists(backup_path)
	var errors: Dictionary = {}
	var primary: Dictionary = {}
	var primary_valid := false
	if has_primary:
		primary = _read_and_validate(absolute_path)
		primary_valid = bool(primary.get("ok", false))
		if not primary_valid:
			errors["primary"] = primary

	if has_temporary:
		var temporary := _read_and_validate(temporary_path)
		if bool(temporary.get("ok", false)):
			var promotion := _promote_temporary(temporary_path, absolute_path, primary_valid)
			if not bool(promotion.get("ok", false)):
				return _failure("temporary_recovery_failed", "A valid temporary session could not be promoted.", absolute_path, {"cause": promotion})
			temporary["path"] = absolute_path
			temporary["source_path"] = temporary_path
			temporary["requested_path"] = path
			temporary["recovered_from_temporary"] = true
			temporary["recovered_from_backup"] = false
			return temporary
		errors["temporary"] = temporary

	if primary_valid:
		primary["requested_path"] = path
		primary["recovered_from_temporary"] = false
		primary["recovered_from_backup"] = false
		if has_temporary:
			primary["temporary_cleanup_error"] = _remove_if_present(temporary_path)
		return primary

	if has_backup:
		var backup := _read_and_validate(backup_path)
		if bool(backup.get("ok", false)):
			var recovery := _restore_backup(absolute_path)
			if not bool(recovery.get("ok", false)):
				return _failure("backup_recovery_failed", "A valid backup session could not be restored.", absolute_path, {"cause": recovery})
			backup["path"] = absolute_path
			backup["source_path"] = backup_path
			backup["requested_path"] = path
			backup["recovered_from_temporary"] = false
			backup["recovered_from_backup"] = true
			return backup
		errors["backup"] = backup

	if has_primary or has_temporary or has_backup:
		return _failure("no_valid_save", "No valid primary, temporary, or backup session save exists.", absolute_path, {"candidate_errors": errors})
	return _failure("save_not_found", "No session save exists at the requested path.", absolute_path)


static func _replace_with_backup(temporary_path: String, absolute_path: String) -> Dictionary:
	var backup_path := absolute_path + ".bak"
	var had_primary := FileAccess.file_exists(absolute_path)
	if had_primary:
		if FileAccess.file_exists(backup_path):
			var remove_backup := DirAccess.remove_absolute(backup_path)
			if remove_backup != OK:
				return _failure("old_backup_remove_failed", "Could not replace the previous backup.", absolute_path, {"engine_error": remove_backup})
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			return _failure("backup_creation_failed", "Could not create the session backup.", absolute_path, {"engine_error": backup_error})
	var install_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if install_error != OK:
		if had_primary:
			_restore_backup(absolute_path)
		return _failure("save_install_failed", "Could not install the validated session save.", absolute_path, {"engine_error": install_error})
	return _success({"backup_created": had_primary})


static func _promote_temporary(temporary_path: String, absolute_path: String, preserve_primary: bool) -> Dictionary:
	if preserve_primary:
		return _replace_with_backup(temporary_path, absolute_path)
	if FileAccess.file_exists(absolute_path):
		var remove_primary := DirAccess.remove_absolute(absolute_path)
		if remove_primary != OK:
			return _failure("primary_remove_failed", "Could not remove an invalid primary session save.", absolute_path, {"engine_error": remove_primary})
	var promote_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if promote_error != OK:
		return _failure("temporary_promote_failed", "Could not promote the temporary session save.", absolute_path, {"engine_error": promote_error})
	return _read_and_validate(absolute_path)


static func _restore_backup(absolute_path: String) -> Dictionary:
	var backup_path := absolute_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		return _failure("backup_not_found", "No backup is available for restoration.", absolute_path)
	if FileAccess.file_exists(absolute_path):
		var remove_primary := DirAccess.remove_absolute(absolute_path)
		if remove_primary != OK:
			return _failure("primary_remove_failed", "Could not remove the invalid primary session save.", absolute_path, {"engine_error": remove_primary})
	var restore_error := DirAccess.rename_absolute(backup_path, absolute_path)
	if restore_error != OK:
		return _failure("backup_restore_failed", "Could not restore the session backup.", absolute_path, {"engine_error": restore_error})
	return _read_and_validate(absolute_path)


static func _read_and_validate(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save_open_failed", "Could not open the session save.", path, {"engine_error": FileAccess.get_open_error()})
	var payload := file.get_as_text()
	file = null
	return _parse_and_validate(payload, path)


static func _parse_and_validate(payload: String, source_path: String) -> Dictionary:
	if payload.strip_edges().is_empty():
		return _failure("empty_save", "The session save is empty.", source_path)
	var parser := JSON.new()
	var parse_error := parser.parse(payload)
	if parse_error != OK:
		return _failure("invalid_json", "The session save is not valid JSON.", source_path, {
			"engine_error": parse_error,
			"line": parser.get_error_line(),
			"parser_message": parser.get_error_message(),
		})
	if typeof(parser.data) != TYPE_DICTIONARY:
		return _failure("invalid_envelope", "The session save root must be an object.", source_path)
	var envelope: Dictionary = parser.data
	var schema: Variant = envelope.get("schema_version", null)
	if (typeof(schema) != TYPE_INT and typeof(schema) != TYPE_FLOAT) or float(schema) != floor(float(schema)):
		return _failure("invalid_schema_version", "The session schema version must be an integer.", source_path)
	var migration := M2SessionMigrationScript.migrate_envelope(envelope)
	if not bool(migration.get("ok", false)):
		return _failure(
			String(migration.get("code", "save_migration_failed")),
			String(migration.get("error", "The session save could not be migrated.")),
			source_path,
			{"migration": migration, "actual": int(schema)}
		)
	var current_envelope: Dictionary = migration["data"]
	var session := FirstDaySession.from_dict(current_envelope["session"])
	if session == null:
		return _failure("session_deserialization_failed", "FirstDaySession could not be reconstructed.", source_path)
	var validation := session.validate()
	if not bool(validation.get("ok", false)):
		return _failure("loaded_session_validation_failed", "The reconstructed session is invalid.", source_path, {"validation": validation})
	return _success({
		"path": source_path,
		"schema_version": SCHEMA_VERSION,
		"source_schema_version": int(migration.get("source_schema_version", schema)),
		"source_session_version": int(migration.get("source_session_version", FirstDaySession.SESSION_VERSION)),
		"source_run_state_version": int(migration.get("source_run_state_version", GameRules.SAVE_VERSION)),
		"migrated": bool(migration.get("migrated", false)),
		"saved_at_unix": current_envelope.get("saved_at_unix", null),
		"flow_revision": session.flow_revision,
		"session": session,
	})


static func _resolve_path(requested_path: String) -> Dictionary:
	var normalized := requested_path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return _failure("invalid_path", "The save path cannot be empty.", "")
	var absolute := ""
	if normalized.begins_with("user://"):
		absolute = ProjectSettings.globalize_path(normalized)
	elif normalized.is_absolute_path():
		absolute = normalized
	else:
		return _failure("invalid_path", "The save path must use user:// or be absolute.", "", {"requested_path": requested_path})
	absolute = absolute.simplify_path()
	if absolute.get_file().is_empty():
		return _failure("invalid_path", "The save path must identify a file.", absolute)
	return _success({"path": absolute, "requested_path": requested_path})


static func _remove_if_present(path: String) -> int:
	return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK


static func _success(fields: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(fields, true)
	return result


static func _failure(code: String, message: String, path: String = "", details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message, "path": path}
	result.merge(details, true)
	return result
