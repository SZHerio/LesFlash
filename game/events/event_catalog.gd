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
	var migration := migrate_serialized(JsonValidator.normalize_numbers(parsed))
	if not bool(migration.get("ok", false)):
		return _failure("catalog_migration_failed", [String(migration.get("error", "Каталог событий не удалось мигрировать"))])
	var catalog: Dictionary = migration["data"]
	var validation := Validator.validate(catalog)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_catalog", Array(validation.get("errors", [])))
	return {
		"ok": true,
		"code": "ok",
		"catalog": catalog.duplicate(true),
		"errors": [],
	}


static func migrate_serialized(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": "invalid_catalog", "error": "Event catalog must be a dictionary."}
	var catalog: Dictionary = value
	var version: Variant = catalog.get("schema_version", null)
	if typeof(version) != TYPE_INT:
		return {"ok": false, "code": "invalid_catalog_version", "error": "Event catalog schema_version must be an integer."}
	if int(version) not in [1, Validator.SCHEMA_VERSION]:
		return {"ok": false, "code": "unsupported_catalog_version", "error": "Event catalog version is unsupported."}
	var migrated := catalog.duplicate(true)
	if int(version) == 1:
		var cards: Variant = migrated.get("cards", null)
		if not cards is Array:
			return {"ok": false, "code": "invalid_legacy_cards", "error": "Legacy event cards must be an array."}
		var migrated_cards: Array = []
		for raw_card: Variant in cards:
			if not raw_card is Dictionary:
				return {"ok": false, "code": "invalid_legacy_card", "error": "Legacy event card must be a dictionary."}
			var card: Dictionary = _migrate_legacy_meter_references(raw_card)
			var card_id := String(card.get("id", ""))
			card["family_id"] = "family_%s" % card_id
			card["max_occurrences"] = 3
			card["npc_ids"] = []
			var source_kinds: Array = Array(card.get("source_kinds", []))
			card["causal_category"] = String(source_kinds.front()) if not source_kinds.is_empty() else "ambient"
			migrated_cards.append(card)
		migrated["cards"] = migrated_cards
		migrated["schema_version"] = Validator.SCHEMA_VERSION
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"data": migrated,
		"source_version": int(version),
		"migrated": int(version) != Validator.SCHEMA_VERSION,
	}


static func _migrate_legacy_meter_references(value: Variant) -> Variant:
	if value is Array:
		var array: Array = []
		for item: Variant in value:
			array.append(_migrate_legacy_meter_references(item))
		return array
	if value is Dictionary:
		var result: Dictionary = {}
		for raw_key: Variant in value:
			var key: Variant = "mental_state" if String(raw_key) == "morale" else raw_key
			result[key] = _migrate_legacy_meter_references(value[raw_key])
		if String(result.get("id", "")) == "morale" and (
			String(result.get("type", "")) == "change_state"
			or String(result.get("kind", "")) == "state"
		):
			result["id"] = "mental_state"
		return result
	return value


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
