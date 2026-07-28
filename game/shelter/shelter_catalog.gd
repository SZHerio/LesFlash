class_name ShelterCatalog
extends RefCounted

## Read-only access to the versioned M3F shelter catalog.

const Validator := preload("res://game/shelter/shelter_catalog_validator.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")
const DEFAULT_PATH := "res://game/shelter/data/shelter_catalog_v1.json"


static var _default_cache: Dictionary = {}


## Content files are immutable at run time, so the parse and the full
## validation happen once. Callers still receive their own deep copy, which
## keeps the previous contract exactly: nobody can mutate a shared catalog.
static func load_default() -> Dictionary:
	if _default_cache.is_empty():
		_default_cache = load_from_path(DEFAULT_PATH)
	return _cached_copy(_default_cache)


static func reset_cache_for_tests() -> void:
	_default_cache = {}


static func _cached_copy(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	return result


static func load_from_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось открыть каталог ночлега: %s" % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("Каталог ночлега содержит неверный JSON: %s" % parser.get_error_message())
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var validation := Validator.validate(catalog)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_catalog",
			"catalog": {},
			"errors": Array(validation.get("errors", [])).duplicate(),
		}
	return {
		"ok": true,
		"code": "ok",
		"catalog": catalog.duplicate(true),
		"errors": [],
	}


static func find_option(catalog: Dictionary, shelter_id: String) -> Dictionary:
	for raw_option: Variant in Array(catalog.get("options", [])):
		if raw_option is Dictionary and String(raw_option.get("shelter_id", "")) == shelter_id:
			return Dictionary(raw_option).duplicate(true)
	return {}


static func options_for_location(catalog: Dictionary, location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_option: Variant in Array(catalog.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		if location_id in Array(option.get("location_ids", [])):
			result.append(option.duplicate(true))
	return result


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"code": "catalog_load_failed",
		"catalog": {},
		"errors": [message],
	}
