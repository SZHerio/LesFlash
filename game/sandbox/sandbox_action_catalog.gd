class_name SandboxActionCatalog
extends RefCounted

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const Validator := preload("res://game/sandbox/sandbox_action_validator.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "riverside_sandbox_actions"
const CATALOG_VERSION := 1
const DEFAULT_PATH := "res://game/sandbox/data/sandbox_action_catalog_v1.json"


static var _default_cache: Dictionary = {}


## Content files are immutable at run time, so the parse and the full
## validation happen once. Callers still receive their own deep copy, which
## keeps the previous contract exactly: nobody can mutate a shared catalog.
static func load_default(reference_ids: Dictionary = {}) -> Dictionary:
	if _default_cache.is_empty() or not reference_ids.is_empty():
		var loaded := load_from_path(DEFAULT_PATH, reference_ids)
		if not reference_ids.is_empty():
			return loaded
		_default_cache = loaded
	return _cached_copy(_default_cache)


static func reset_cache_for_tests() -> void:
	_default_cache = {}


static func _cached_copy(source: Dictionary) -> Dictionary:
	return {
		"ok": bool(source.get("ok", false)),
		"catalog": Dictionary(source.get("catalog", {})).duplicate(true),
		"errors": Array(source.get("errors", [])).duplicate(true),
	}


static func load_from_path(path: String, reference_ids: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("cannot open sandbox action catalog: %s" % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("sandbox action catalog contains invalid JSON: %s" % parser.get_error_message())
	var json_validation := JsonValidator.validate(parser.data, "sandbox_action_catalog")
	if not bool(json_validation.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": json_validation.get("errors", []).duplicate()}
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var validation := Validator.validate(catalog, reference_ids)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": validation.get("errors", []).duplicate()}
	return {"ok": true, "catalog": catalog.duplicate(true), "errors": []}


static func find_action(catalog: Dictionary, action_id: String) -> Dictionary:
	for raw_action: Variant in catalog.get("actions", []):
		if raw_action is Dictionary and String(raw_action.get("action_id", "")) == action_id:
			return Dictionary(raw_action).duplicate(true)
	return {}


static func actions_for_location(catalog: Dictionary, location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_action: Variant in catalog.get("actions", []):
		if raw_action is Dictionary and String(raw_action.get("location_id", "")) == location_id:
			result.append(Dictionary(raw_action).duplicate(true))
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": {}, "errors": [message]}
