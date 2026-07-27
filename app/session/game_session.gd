class_name GameSession
extends RefCounted

## UI-independent session contract introduced for M3A.
##
## The current location is the stable base state. A job, event or future
## mini-game is an interruptible activity layered on top of that location; UI
## routes are deliberately not represented here.

const LEGACY_CONTRACT_VERSION := 2
const PREVIOUS_CONTRACT_VERSION := 3
const CONTRACT_VERSION := 4
const NO_ACTIVITY_KIND := "none"

const WorldStateScript := preload("res://core/world/world_state.gd")
const SocialStateScript := preload("res://core/social/social_state.gd")
const WorldReadModelScript := preload("res://core/world/world_read_model.gd")

var run_state: RunState = RunState.new()
var world_state: WorldState = WorldStateScript.new()
var social_state: SocialState = SocialStateScript.new()
var applied_command_ids: Dictionary = {}
var base_location: String = ""
var active_activity: Dictionary = empty_activity()

var _location_view_model: Dictionary = {}


func _init(
	initial_state: RunState = null,
	initial_location: String = "",
	initial_activity: Dictionary = {},
	initial_world_state: WorldState = null,
	initial_social_state: SocialState = null,
	initial_command_ids: Dictionary = {}
) -> void:
	if initial_state != null:
		run_state = initial_state
	base_location = initial_location
	if not initial_activity.is_empty():
		var normalized := normalize_activity(initial_activity)
		if not normalized.is_empty():
			active_activity = normalized
	if initial_world_state != null:
		world_state = initial_world_state
	if initial_social_state != null:
		social_state = initial_social_state
	applied_command_ids = initial_command_ids.duplicate(true)


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
		"world": Dictionary(WorldReadModelScript.build(world_state).get("observed", {})).duplicate(true),
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
		"world_state": world_state.to_dict() if world_state != null else {},
		"social_state": social_state.to_dict() if social_state != null else {},
		"applied_command_ids": applied_command_ids.duplicate(true),
		"base_location": base_location,
		"active_activity": active_activity.duplicate(true),
	}


static func from_dict(data: Dictionary) -> GameSession:
	var version: Variant = _parse_integral(data.get("session_version", null))
	if version == null or int(version) not in [LEGACY_CONTRACT_VERSION, PREVIOUS_CONTRACT_VERSION, CONTRACT_VERSION]:
		return null
	if typeof(data.get("run_state", null)) != TYPE_DICTIONARY:
		return null
	if typeof(data.get("base_location", null)) != TYPE_STRING:
		return null
	var parsed_state := RunState.from_dict(data["run_state"])
	var parsed_activity := normalize_activity(data.get("active_activity", null))
	if parsed_state == null or parsed_activity.is_empty():
		return null
	var parsed_world := WorldStateScript.new()
	var parsed_social := SocialStateScript.new()
	var parsed_commands: Dictionary = {}
	if int(version) == CONTRACT_VERSION:
		if typeof(data.get("world_state", null)) != TYPE_DICTIONARY or typeof(data.get("social_state", null)) != TYPE_DICTIONARY or typeof(data.get("applied_command_ids", null)) != TYPE_DICTIONARY:
			return null
		parsed_world = WorldStateScript.from_dict(data["world_state"])
		parsed_social = SocialStateScript.from_dict(data["social_state"])
		parsed_commands = Dictionary(data["applied_command_ids"]).duplicate(true)
		if parsed_world == null or parsed_social == null:
			return null
	var result := GameSession.new(
		parsed_state,
		String(data["base_location"]),
		parsed_activity,
		parsed_world,
		parsed_social,
		parsed_commands
	)
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
	if world_state == null:
		errors.append("world_state is null")
	else:
		var world_validation := world_state.validate()
		for error in Array(world_validation.get("errors", [])):
			errors.append("world_state: %s" % String(error))
	if social_state == null:
		errors.append("social_state is null")
	else:
		var social_validation := social_state.validate()
		for error in Array(social_validation.get("errors", [])):
			errors.append("social_state: %s" % String(error))
	_validate_command_ids(applied_command_ids, errors)
	if base_location.is_empty():
		errors.append("base_location is empty")
	if normalize_activity(active_activity).is_empty():
		errors.append("active_activity is invalid")
	return {"ok": errors.is_empty(), "errors": errors}


func clone() -> GameSession:
	var result := GameSession.from_dict(to_dict())
	if result != null:
		result._location_view_model = _location_view_model.duplicate(true)
	return result


func replace_from(other: GameSession) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	if not run_state.replace_from(other.run_state):
		return false
	if not world_state.replace_from(other.world_state):
		return false
	if not social_state.replace_from(other.social_state):
		return false
	applied_command_ids = other.applied_command_ids.duplicate(true)
	base_location = other.base_location
	active_activity = other.active_activity.duplicate(true)
	_location_view_model = other._location_view_model.duplicate(true)
	return true


static func _validate_command_ids(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("applied_command_ids must be a dictionary")
		return
	for raw_id: Variant in Dictionary(value):
		if typeof(raw_id) != TYPE_STRING or String(raw_id).strip_edges().is_empty() or not Dictionary(value)[raw_id] is Dictionary:
			errors.append("applied_command_ids contains an invalid entry")


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
