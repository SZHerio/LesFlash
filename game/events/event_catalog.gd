class_name ContextualEventCatalog
extends RefCounted

const Validator := preload("res://game/events/event_content_validator.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")
const DEFAULT_PATH := "res://game/events/data/contextual_events_v1.json"


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("missing_catalog", ["Каталог событий не найден: %s" % path])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("catalog_open_failed", ["Каталог событий не удалось открыть"])
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("catalog_parse_failed", ["Каталог событий содержит некорректный JSON"])
	var catalog: Dictionary = JsonValidator.normalize_numbers(parsed)
	var validation := Validator.validate(catalog)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_catalog", Array(validation.get("errors", [])))
	return {
		"ok": true,
		"code": "ok",
		"catalog": catalog.duplicate(true),
		"errors": [],
	}


static func cards(catalog: Dictionary) -> Array:
	return Array(catalog.get("cards", [])).duplicate(true)


static func card(catalog: Dictionary, card_id: String) -> Dictionary:
	for raw_card: Variant in Array(catalog.get("cards", [])):
		if raw_card is Dictionary and String(raw_card.get("id", "")) == card_id:
			return Dictionary(raw_card).duplicate(true)
	return {}


static func _failure(code: String, raw_errors: Array) -> Dictionary:
	var errors: Array[String] = []
	for raw_error: Variant in raw_errors:
		errors.append(String(raw_error))
	return {"ok": false, "code": code, "catalog": {}, "errors": errors}
