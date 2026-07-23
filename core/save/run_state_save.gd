class_name RunStateSave
extends RefCounted

## Versioned JSON persistence for [RunState].
##
## The service deliberately returns data-rich result dictionaries instead of
## logging errors. This keeps it deterministic and convenient for headless tests.

const PREVIOUS_SCHEMA_VERSION: int = 1
const SCHEMA_VERSION: int = 2
const DEFAULT_SAVE_PATH: String = "user://run_state.json"


static func save_state(run_state: RunState, path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	var resolved := _resolve_path(path)
	if not resolved.ok:
		return resolved

	var absolute_path: String = resolved.path
	if run_state == null:
		return _failure(
			"state_is_null",
			"RunState cannot be null.",
			absolute_path,
			{"requested_path": path}
		)

	var state_validation: Dictionary = run_state.validate()
	if not state_validation.get("ok", false):
		return _failure(
			"state_validation_failed",
			"RunState is invalid and was not saved.",
			absolute_path,
			{"validation": state_validation}
		)

	var state_data: Dictionary = run_state.to_dict()
	var envelope := {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"run_state": state_data,
	}
	var payload := JSON.stringify(envelope, "\t", true, true) + "\n"

	var directory_path := absolute_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory_path):
		var make_directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
		if make_directory_error != OK:
			return _failure(
				"directory_creation_failed",
				"Could not create the save directory.",
				absolute_path,
				{"engine_error": make_directory_error, "directory": directory_path}
			)

	var temporary_path := absolute_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		var pending_temporary := _read_and_validate(temporary_path)
		if pending_temporary.ok:
			return _failure(
				"pending_temporary_recovery",
				"A valid interrupted save is waiting for recovery. Load it before saving again.",
				absolute_path,
				{"temporary_path": temporary_path}
			)
		var stale_temporary_remove_error := DirAccess.remove_absolute(temporary_path)
		if stale_temporary_remove_error != OK:
			return _failure(
				"stale_temporary_remove_failed",
				"Could not remove a stale temporary save.",
				absolute_path,
				{
					"engine_error": stale_temporary_remove_error,
					"temporary_path": temporary_path,
				}
			)

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure(
			"temporary_open_failed",
			"Could not open the temporary save for writing.",
			absolute_path,
			{
				"engine_error": FileAccess.get_open_error(),
				"temporary_path": temporary_path,
			}
		)

	file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		_remove_file_if_present(temporary_path)
		return _failure(
			"temporary_write_failed",
			"Could not finish writing the temporary save.",
			absolute_path,
			{"engine_error": write_error, "temporary_path": temporary_path}
		)

	var temporary_validation := _read_and_validate(temporary_path)
	if not temporary_validation.ok:
		var invalid_temporary_remove_error := _remove_file_if_present(temporary_path)
		return _failure(
			"temporary_validation_failed",
			"The temporary save failed read-back validation.",
			absolute_path,
			{
				"cause": temporary_validation,
				"cleanup_error": invalid_temporary_remove_error,
				"temporary_path": temporary_path,
			}
		)

	var replacement := _replace_with_backup(temporary_path, absolute_path)
	if not replacement.ok:
		_remove_file_if_present(temporary_path)
		return replacement

	return _success({
		"path": absolute_path,
		"requested_path": path,
		"temporary_path": temporary_path,
		"backup_path": absolute_path + ".bak",
		"backup_created": replacement.backup_created,
		"schema_version": SCHEMA_VERSION,
		"bytes_written": payload.to_utf8_buffer().size(),
	})


static func load_state(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	var resolved := _resolve_path(path)
	if not resolved.ok:
		return resolved

	var absolute_path: String = resolved.path
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var has_primary := FileAccess.file_exists(absolute_path)
	var has_temporary := FileAccess.file_exists(temporary_path)
	var has_backup := FileAccess.file_exists(backup_path)
	var candidate_errors := {}
	var primary_result: Dictionary = {}
	var primary_is_valid := false

	if has_primary:
		primary_result = _read_and_validate(absolute_path)
		primary_is_valid = primary_result.ok
		if not primary_is_valid:
			candidate_errors["primary"] = primary_result

	if has_temporary:
		var temporary_result := _read_and_validate(temporary_path)
		if temporary_result.ok:
			var temporary_recovery := _promote_temporary(
				temporary_path,
				absolute_path,
				primary_is_valid
			)
			if not temporary_recovery.ok:
				return _failure(
					"temporary_recovery_failed",
					"A valid temporary save was found but could not be restored.",
					absolute_path,
					{"cause": temporary_recovery, "temporary_path": temporary_path}
				)
			temporary_result["path"] = absolute_path
			temporary_result["source_path"] = temporary_path
			temporary_result["requested_path"] = path
			temporary_result["recovered_from_backup"] = false
			temporary_result["recovered_from_temporary"] = true
			temporary_result["recovery"] = temporary_recovery
			return temporary_result
		candidate_errors["temporary"] = temporary_result

	if primary_is_valid:
		primary_result["requested_path"] = path
		primary_result["recovered_from_backup"] = false
		primary_result["recovered_from_temporary"] = false
		if has_temporary:
			primary_result["temporary_cleanup_error"] = _remove_file_if_present(temporary_path)
		return primary_result

	if has_backup:
		var backup_result := _read_and_validate(backup_path)
		if backup_result.ok:
			var backup_recovery := _restore_backup(absolute_path)
			if not backup_recovery.ok:
				return _failure(
					"backup_recovery_failed",
					"A valid backup was found but could not be restored.",
					absolute_path,
					{"cause": backup_recovery, "backup_path": backup_path}
				)
			backup_result["path"] = absolute_path
			backup_result["source_path"] = backup_path
			backup_result["requested_path"] = path
			backup_result["recovered_from_backup"] = true
			backup_result["recovered_from_temporary"] = false
			backup_result["recovery"] = backup_recovery
			return backup_result
		candidate_errors["backup"] = backup_result

	if has_primary or has_temporary or has_backup:
		return _failure(
			"no_valid_save",
			"No valid primary, temporary, or backup save could be loaded.",
			absolute_path,
			{
				"requested_path": path,
				"temporary_path": temporary_path,
				"backup_path": backup_path,
				"candidate_errors": candidate_errors,
			}
		)

	return _failure(
		"save_not_found",
		"No primary, temporary, or backup save exists at the requested path.",
		absolute_path,
		{
			"requested_path": path,
			"temporary_path": temporary_path,
			"backup_path": backup_path,
		}
	)


static func _replace_with_backup(temporary_path: String, absolute_path: String) -> Dictionary:
	var backup_path := absolute_path + ".bak"
	var had_previous_save := FileAccess.file_exists(absolute_path)

	if had_previous_save:
		if FileAccess.file_exists(backup_path):
			var old_backup_remove_error := DirAccess.remove_absolute(backup_path)
			if old_backup_remove_error != OK:
				return _failure(
					"old_backup_remove_failed",
					"Could not replace the previous backup.",
					absolute_path,
					{"engine_error": old_backup_remove_error, "backup_path": backup_path}
				)

		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			return _failure(
				"backup_creation_failed",
				"Could not move the previous save to its backup path.",
				absolute_path,
				{"engine_error": backup_error, "backup_path": backup_path}
			)

	var install_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if install_error != OK:
		var restoration := _success({"attempted": false})
		if had_previous_save:
			restoration = _restore_backup(absolute_path)
		return _failure(
			"save_install_failed",
			"Could not install the validated temporary save.",
			absolute_path,
			{
				"engine_error": install_error,
				"temporary_path": temporary_path,
				"backup_path": backup_path,
				"restoration": restoration,
			}
		)

	return _success({
		"path": absolute_path,
		"backup_path": backup_path,
		"backup_created": had_previous_save,
		"had_previous_save": had_previous_save,
	})


static func _promote_temporary(
	temporary_path: String,
	absolute_path: String,
	preserve_primary_as_backup: bool
) -> Dictionary:
	var replacement: Dictionary = {}
	if preserve_primary_as_backup:
		replacement = _replace_with_backup(temporary_path, absolute_path)
		if not replacement.ok:
			return replacement
	else:
		replacement = _promote_without_primary_backup(temporary_path, absolute_path)
		if not replacement.ok:
			return replacement

	var restored_validation := _read_and_validate(absolute_path)
	if not restored_validation.ok:
		var rollback := _success({"attempted": false})
		if preserve_primary_as_backup:
			rollback = _restore_backup(absolute_path)
		return _failure(
			"promoted_save_validation_failed",
			"The promoted temporary save did not pass validation.",
			absolute_path,
			{
				"attempted": true,
				"temporary_path": temporary_path,
				"cause": restored_validation,
				"rollback": rollback,
			}
		)

	return _success({
		"attempted": true,
		"path": absolute_path,
		"temporary_path": temporary_path,
		"backup_created": bool(replacement.get("backup_created", false)),
		"validated": true,
	})


static func _promote_without_primary_backup(
	temporary_path: String,
	absolute_path: String
) -> Dictionary:
	if FileAccess.file_exists(absolute_path):
		var primary_remove_error := DirAccess.remove_absolute(absolute_path)
		if primary_remove_error != OK:
			return _failure(
				"primary_remove_failed",
				"Could not remove the invalid primary save during temporary recovery.",
				absolute_path,
				{
					"attempted": true,
					"engine_error": primary_remove_error,
					"temporary_path": temporary_path,
				}
			)

	var promote_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if promote_error != OK:
		return _failure(
			"temporary_promote_failed",
			"Could not promote the temporary save to the primary path.",
			absolute_path,
			{
				"attempted": true,
				"engine_error": promote_error,
				"temporary_path": temporary_path,
			}
		)

	return _success({
		"attempted": true,
		"path": absolute_path,
		"temporary_path": temporary_path,
		"backup_created": false,
	})


static func _restore_backup(absolute_path: String) -> Dictionary:
	var backup_path := absolute_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		return _failure(
			"backup_not_found",
			"The backup required for restoration does not exist.",
			absolute_path,
			{"attempted": true, "backup_path": backup_path}
		)

	if FileAccess.file_exists(absolute_path):
		var primary_remove_error := DirAccess.remove_absolute(absolute_path)
		if primary_remove_error != OK:
			return _failure(
				"primary_remove_failed",
				"Could not remove the invalid primary save during restoration.",
				absolute_path,
				{
					"attempted": true,
					"engine_error": primary_remove_error,
					"backup_path": backup_path,
				}
			)

	var restore_error := DirAccess.rename_absolute(backup_path, absolute_path)
	if restore_error != OK:
		return _failure(
			"backup_restore_failed",
			"Could not restore the backup to the primary save path.",
			absolute_path,
			{
				"attempted": true,
				"engine_error": restore_error,
				"backup_path": backup_path,
			}
		)

	var restored_validation := _read_and_validate(absolute_path)
	if not restored_validation.ok:
		return _failure(
			"restored_save_validation_failed",
			"The restored save did not pass validation.",
			absolute_path,
			{
				"attempted": true,
				"backup_path": backup_path,
				"cause": restored_validation,
			}
		)

	return _success({
		"attempted": true,
		"path": absolute_path,
		"backup_path": backup_path,
		"validated": true,
	})


static func _read_and_validate(absolute_path: String) -> Dictionary:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return _failure(
			"save_open_failed",
			"Could not open the save for reading.",
			absolute_path,
			{"engine_error": FileAccess.get_open_error()}
		)

	var payload := file.get_as_text()
	file = null
	return _parse_and_validate(payload, absolute_path)


static func _parse_and_validate(payload: String, source_path: String) -> Dictionary:
	if payload.strip_edges().is_empty():
		return _failure("empty_save", "The save file is empty.", source_path)

	var parser := JSON.new()
	var parse_error := parser.parse(payload)
	if parse_error != OK:
		return _failure(
			"invalid_json",
			"The save file is not valid JSON.",
			source_path,
			{
				"engine_error": parse_error,
				"line": parser.get_error_line(),
				"parser_message": parser.get_error_message(),
			}
		)

	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure(
			"invalid_envelope",
			"The save root must be a JSON object.",
			source_path,
			{"actual_type": type_string(typeof(parsed))}
		)

	var envelope: Dictionary = parsed
	if not envelope.has("schema_version"):
		return _failure(
			"missing_schema_version",
			"The save does not declare a schema version.",
			source_path
		)

	var schema_value: Variant = envelope.schema_version
	if typeof(schema_value) != TYPE_INT and typeof(schema_value) != TYPE_FLOAT:
		return _failure(
			"invalid_schema_version",
			"The schema version must be an integer.",
			source_path,
			{"actual_type": type_string(typeof(schema_value))}
		)

	var schema_version := int(schema_value)
	if float(schema_value) != float(schema_version):
		return _failure(
			"invalid_schema_version",
			"The schema version must be a whole number.",
			source_path,
			{"actual_value": schema_value}
		)
	if schema_version not in [PREVIOUS_SCHEMA_VERSION, SCHEMA_VERSION]:
		return _failure(
			"unsupported_schema_version",
			"This save schema version is not supported.",
			source_path,
			{"actual_version": schema_version, "supported_version": SCHEMA_VERSION}
		)

	if not envelope.has("run_state") or typeof(envelope.run_state) != TYPE_DICTIONARY:
		return _failure(
			"invalid_run_state_payload",
			"The save envelope must contain a run_state object.",
			source_path
		)

	var state_migration := RunState.migrate_serialized(envelope.run_state)
	if not bool(state_migration.get("ok", false)):
		return _failure(
			"run_state_migration_failed",
			"RunState migration failed.",
			source_path,
			{"migration": state_migration}
		)
	var run_state := RunState.from_dict(state_migration["data"])
	if run_state == null:
		return _failure(
			"run_state_deserialization_failed",
			"RunState could not be reconstructed from the save data.",
			source_path
		)

	var validation: Dictionary = run_state.validate()
	if not validation.get("ok", false):
		return _failure(
			"loaded_state_validation_failed",
			"The reconstructed RunState is invalid.",
			source_path,
			{"validation": validation}
		)

	return _success({
		"path": source_path,
		"schema_version": SCHEMA_VERSION,
		"source_schema_version": schema_version,
		"source_run_state_version": int(state_migration.get("source_version", GameRules.SAVE_VERSION)),
		"migrated": schema_version != SCHEMA_VERSION or bool(state_migration.get("migrated", false)),
		"saved_at_unix": envelope.get("saved_at_unix", null),
		"state": run_state,
	})


static func _resolve_path(requested_path: String) -> Dictionary:
	var trimmed_path := requested_path.strip_edges()
	if trimmed_path.is_empty():
		return _failure(
			"invalid_path",
			"The save path cannot be empty.",
			"",
			{"requested_path": requested_path}
		)

	var normalized_path := trimmed_path.replace("\\", "/")
	var absolute_path := ""
	if normalized_path.begins_with("user://"):
		absolute_path = ProjectSettings.globalize_path(normalized_path)
	elif normalized_path.is_absolute_path():
		absolute_path = normalized_path
	else:
		return _failure(
			"invalid_path",
			"The save path must use user:// or be absolute.",
			"",
			{"requested_path": requested_path}
		)

	absolute_path = absolute_path.simplify_path()
	if absolute_path.get_file().is_empty():
		return _failure(
			"invalid_path",
			"The save path must identify a file.",
			absolute_path,
			{"requested_path": requested_path}
		)

	return _success({"path": absolute_path, "requested_path": requested_path})


static func _remove_file_if_present(path: String) -> int:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


static func _success(fields: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(fields, true)
	return result


static func _failure(
	code: String,
	message: String,
	path: String = "",
	details: Dictionary = {}
) -> Dictionary:
	var result := {
		"ok": false,
		"code": code,
		"error": message,
	}
	if not path.is_empty():
		result["path"] = path
	if not details.is_empty():
		result["details"] = details
	return result
