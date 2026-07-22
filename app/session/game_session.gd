class_name GameSession
extends RefCounted

## UI-independent session contract introduced for M3A.
##
## The current location is the stable base state. A job, event or future
## mini-game is an interruptible activity layered on top of that location; UI
## routes are deliberately not represented here.

const CONTRACT_VERSION := 2
const NO_ACTIVITY_KIND := "none"

var run_state: RunState = RunState.new()
var base_location: String = ""
var active_activity: Dictionary = empty_activity()

var _location_view_model: Dictionary = {}


func _init(
	initial_state: RunState = null,
	initial_location: String = "",
	initial_activity: Dictionary = {}
) -> void:
	if initial_state != null:
		run_state = initial_state
	base_location = initial_location
	if not initial_activity.is_empty():
		var normalized := normalize_activity(initial_activity)
		if not normalized.is_empty():
			active_activity = normalized


static func empty_activity() -> Dictionary:
	return {
		"kind": NO_ACTIVITY_KIND,
		"id": "",
		"snapshot": {},
	}


static func normalize_activity(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = value
	if source.size() != 3:
		return {}
	if typeof(source.get("kind", null)) != TYPE_STRING:
		return {}
	if typeof(source.get("id", null)) != TYPE_STRING:
		return {}
	if typeof(source.get("snapshot", null)) != TYPE_DICTIONARY:
		return {}
	var kind := String(source["kind"])
	var identifier := String(source["id"])
	var snapshot: Dictionary = Dictionary(source["snapshot"]).duplicate(true)
	if kind.is_empty():
		return {}
	if kind == NO_ACTIVITY_KIND:
		if not identifier.is_empty() or not snapshot.is_empty():
			return {}
	elif identifier.is_empty():
		return {}
	var errors: Array[String] = []
	_validate_json_value(snapshot, "active_activity.snapshot", errors)
	if not errors.is_empty():
		return {}
	return {
		"kind": kind,
		"id": identifier,
		"snapshot": snapshot,
	}


func set_base_location(location_id: String) -> bool:
	if location_id.is_empty():
		return false
	base_location = location_id
	_location_view_model.clear()
	return true


func begin_activity(kind: String, identifier: String, snapshot: Dictionary = {}) -> bool:
	var candidate := normalize_activity({
		"kind": kind,
		"id": identifier,
		"snapshot": snapshot,
	})
	if candidate.is_empty():
		return false
	active_activity = candidate
	return true


func clear_activity() -> void:
	active_activity = empty_activity()


func set_location_view_model(model: Dictionary) -> bool:
	var identifier := String(model.get("id", base_location))
	if base_location.is_empty() or identifier != base_location:
		return false
	var actions: Variant = model.get("actions", [])
	var tags: Variant = model.get("tags", [])
	if typeof(actions) != TYPE_ARRAY or typeof(tags) != TYPE_ARRAY:
		return false
	_location_view_model = model.duplicate(true)
	_location_view_model["id"] = base_location
	return true


func get_shell_model() -> Dictionary:
	var calendar_model: Dictionary = {}
	var meters: Dictionary = {}
	var money := 0
	var age := 0
	if run_state != null:
		meters = run_state.meters.duplicate(true)
		money = run_state.money
		age = run_state.get_age_years()
		if run_state.calendar != null:
			calendar_model = run_state.calendar.current_stamp()
	return {
		"contract_version": CONTRACT_VERSION,
		"base_location_id": base_location,
		"location": get_location_model(),
		"active_activity": active_activity.duplicate(true),
		"status": {
			"meters": meters,
			"money": money,
			"age_years": age,
			"calendar": calendar_model,
		},
	}


func get_location_model() -> Dictionary:
	var result := {
		"id": base_location,
		"title": base_location,
		"description": "",
		"background_key": "",
		"tags": [],
		"actions": [],
	}
	if not _location_view_model.is_empty():
		for key in _location_view_model:
			result[key] = _location_view_model[key]
	result["id"] = base_location
	return result.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"session_version": CONTRACT_VERSION,
		"run_state": run_state.to_dict() if run_state != null else {},
		"base_location": base_location,
		"active_activity": active_activity.duplicate(true),
	}


static func from_dict(data: Dictionary) -> GameSession:
	var version: Variant = _parse_integral(data.get("session_version", null))
	if version == null or int(version) != CONTRACT_VERSION:
		return null
	if typeof(data.get("run_state", null)) != TYPE_DICTIONARY:
		return null
	if typeof(data.get("base_location", null)) != TYPE_STRING:
		return null
	var parsed_state := RunState.from_dict(data["run_state"])
	var parsed_activity := normalize_activity(data.get("active_activity", null))
	if parsed_state == null or parsed_activity.is_empty():
		return null
	var result := GameSession.new(parsed_state, String(data["base_location"]), parsed_activity)
	return result if bool(result.validate().get("ok", false)) else null


func validate() -> Dictionary:
	var errors: Array[String] = []
	if run_state == null:
		errors.append("run_state is null")
	else:
		var state_validation := run_state.validate()
		if not bool(state_validation.get("ok", false)):
			for error in Array(state_validation.get("errors", [])):
				errors.append("run_state: %s" % String(error))
	if base_location.is_empty():
		errors.append("base_location is empty")
	if normalize_activity(active_activity).is_empty():
		errors.append("active_activity is invalid")
	return {"ok": errors.is_empty(), "errors": errors}


static func _parse_integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floor(numeric):
		return null
	return int(numeric)


static func _validate_json_value(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int = 0
) -> void:
	if depth > 32:
		errors.append("%s exceeds maximum nesting depth" % path)
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return
		TYPE_INT:
			if abs(float(value)) > float(GameRules.JSON_SAFE_INTEGER_MAX):
				errors.append("%s contains an inexact integer" % path)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("%s contains a non-finite number" % path)
		TYPE_ARRAY:
			for index in range(value.size()):
				_validate_json_value(value[index], "%s[%d]" % [path, index], errors, depth + 1)
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string key" % path)
					continue
				_validate_json_value(value[key], "%s.%s" % [path, key], errors, depth + 1)
		_:
			errors.append("%s contains unsupported type %s" % [path, type_string(typeof(value))])
