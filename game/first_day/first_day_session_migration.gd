class_name FirstDaySessionMigration
extends RefCounted

## Explicit, non-destructive migration for the legacy first-day save chain.
## Every step works on a deep copy; failed migration never mutates the parsed
## JSON dictionary that may still be needed for recovery or diagnostics.

const GameSessionScript := preload("res://app/session/game_session.gd")
const SearchSessionStateScript := preload("res://game/search/search_session_state.gd")

const LEGACY_VERSION := 1
const INVENTORY_VERSION := 3
const PREVIOUS_VERSION := INVENTORY_VERSION
const CURRENT_VERSION := 4


static func migrate_envelope(raw: Dictionary) -> Dictionary:
	var source_version: Variant = _integral(raw.get("schema_version", null))
	if source_version == null:
		return _failure("invalid_schema_version", "Envelope schema_version must be an integer.")
	if int(source_version) not in [LEGACY_VERSION, 2, INVENTORY_VERSION, CURRENT_VERSION]:
		return _failure(
			"unsupported_schema_version",
			"Envelope schema version is unsupported.",
			{"actual": int(source_version)}
		)
	if typeof(raw.get("session", null)) != TYPE_DICTIONARY:
		return _failure("invalid_session_payload", "Envelope does not contain a session object.")
	var session_result := migrate_session(raw["session"])
	if not bool(session_result.get("ok", false)):
		return _failure(
			"session_migration_failed",
			"FirstDaySession migration failed.",
			{"cause": session_result}
		)
	var migrated := raw.duplicate(true)
	migrated["schema_version"] = CURRENT_VERSION
	migrated["session"] = session_result["data"]
	return _success({
		"data": migrated,
		"migrated": int(source_version) != CURRENT_VERSION or bool(session_result.get("migrated", false)),
		"source_schema_version": int(source_version),
		"source_session_version": int(session_result.get("source_session_version", CURRENT_VERSION)),
		"source_run_state_version": int(
			session_result.get("source_run_state_version", GameRules.SAVE_VERSION)
		),
	})


static func migrate_session(raw: Dictionary) -> Dictionary:
	var source_version: Variant = _integral(raw.get("session_version", null))
	if source_version == null:
		return _failure("invalid_session_version", "session_version must be an integer.")
	if int(source_version) not in [LEGACY_VERSION, 2, INVENTORY_VERSION, CURRENT_VERSION]:
		return _failure(
			"unsupported_session_version",
			"FirstDaySession version is unsupported.",
			{"actual": int(source_version)}
		)
	if typeof(raw.get("run_state", null)) != TYPE_DICTIONARY:
		return _failure("invalid_run_state_payload", "Session does not contain a RunState object.")
	var state_result := RunState.migrate_serialized(raw["run_state"])
	if not bool(state_result.get("ok", false)):
		return _failure(
			"run_state_migration_failed",
			"RunState migration failed.",
			{"cause": state_result}
		)
	var migrated := raw.duplicate(true)
	var current_version := int(source_version)
	if current_version == LEGACY_VERSION:
		if typeof(raw.get("location", null)) != TYPE_STRING:
			return _failure("invalid_legacy_location", "Legacy session location must be a string.")
		migrated["base_location"] = String(raw["location"])
		migrated["active_activity"] = legacy_activity(raw)
		migrated["session_version"] = 2
		current_version = 2
	if current_version == 2:
		migrated["session_version"] = INVENTORY_VERSION
		current_version = INVENTORY_VERSION
	if current_version == INVENTORY_VERSION:
		var legacy_validation := _validate_v3_contract_fields(migrated)
		if not bool(legacy_validation.get("ok", false)):
			return legacy_validation
		migrated["active_activity"] = GameSessionScript.empty_activity()
		migrated["search_zone_states"] = {}
		migrated["session_version"] = CURRENT_VERSION
		current_version = CURRENT_VERSION
	if current_version != CURRENT_VERSION:
		return _failure(
			"session_migration_incomplete",
			"FirstDaySession migration did not reach the current version."
		)
	migrated["session_version"] = CURRENT_VERSION
	migrated["run_state"] = state_result["data"]
	var contract_validation := validate_contract_fields(migrated)
	if not bool(contract_validation.get("ok", false)):
		return contract_validation
	return _success({
		"data": migrated,
		"migrated": int(source_version) != CURRENT_VERSION or bool(state_result.get("migrated", false)),
		"source_session_version": int(source_version),
		"source_run_state_version": int(
			state_result.get("source_version", GameRules.SAVE_VERSION)
		),
	})


static func validate_contract_fields(data: Dictionary) -> Dictionary:
	if typeof(data.get("location", null)) != TYPE_STRING:
		return _failure("invalid_location", "Legacy compatibility location must be a string.")
	if typeof(data.get("base_location", null)) != TYPE_STRING:
		return _failure("invalid_base_location", "base_location must be a string.")
	if String(data["base_location"]) != String(data["location"]):
		return _failure(
			"location_contract_mismatch",
			"base_location and legacy location disagree."
		)
	var normalized := SearchSessionStateScript.normalize_activity(
		data.get("active_activity", null)
	)
	if normalized.is_empty():
		return _failure("invalid_active_activity", "active_activity has an invalid shape.")
	if typeof(data.get("search_zone_states", null)) != TYPE_DICTIONARY:
		return _failure(
			"invalid_search_zone_states",
			"search_zone_states must be a dictionary."
		)
	var search_validation := SearchSessionStateScript.validate(
		normalized,
		data["search_zone_states"]
	)
	if not bool(search_validation.get("ok", false)):
		return _failure(
			"invalid_search_session_state",
			"Search session state is invalid.",
			{"validation": search_validation}
		)
	if (
		String(normalized.get("kind", "")) == SearchSessionStateScript.SEARCH_KIND
		and String(data.get("phase", "")) != "map"
	):
		return _failure(
			"search_phase_mismatch",
			"An active search requires the legacy phase to remain map."
		)
	return _success()


static func _validate_v3_contract_fields(data: Dictionary) -> Dictionary:
	if typeof(data.get("location", null)) != TYPE_STRING:
		return _failure("invalid_location", "Legacy compatibility location must be a string.")
	if typeof(data.get("base_location", null)) != TYPE_STRING:
		return _failure("invalid_base_location", "base_location must be a string.")
	if String(data["base_location"]) != String(data["location"]):
		return _failure(
			"location_contract_mismatch",
			"base_location and legacy location disagree."
		)
	var normalized := GameSessionScript.normalize_activity(data.get("active_activity", null))
	if normalized.is_empty():
		return _failure("invalid_active_activity", "active_activity has an invalid shape.")
	var expected := legacy_activity(data)
	if not _values_equal(normalized, expected):
		return _failure(
			"activity_contract_mismatch",
			"active_activity disagrees with the legacy M2 phase snapshot."
		)
	return _success()


static func legacy_activity(data: Dictionary) -> Dictionary:
	var phase := String(data.get("phase", ""))
	match phase:
		"start":
			return {
				"kind": "event",
				"id": String(data.get("start", "")),
				"snapshot": {"legacy_phase": "start"},
			}
		"event":
			return {
				"kind": "event",
				"id": String(data.get("current_event", "")),
				"snapshot": {"legacy_phase": "event"},
			}
		"job":
			var job_state: Dictionary = Dictionary(data.get("job_state", {})).duplicate(true)
			return {
				"kind": "job",
				"id": String(job_state.get("job_id", "")),
				"snapshot": job_state,
			}
		"shelter":
			return {
				"kind": "shelter",
				"id": "%s:shelter" % String(data.get("location", "")),
				"snapshot": {"legacy_phase": "shelter"},
			}
		_:
			return GameSessionScript.empty_activity()


static func _values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _values_equal(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _values_equal(left[index], right[index]):
				return false
		return true
	return left == right


static func _integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floor(numeric):
		return null
	return int(numeric)


static func _success(fields: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(fields, true)
	return result


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
