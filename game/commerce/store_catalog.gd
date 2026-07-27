class_name StoreCatalog
extends RefCounted

const Validator := preload("res://game/commerce/commerce_catalog_validator.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")
const DEFAULT_PATH := "res://game/commerce/data/store_catalog_v1.json"


static func load_default() -> Dictionary:
	return load_from_path(DEFAULT_PATH)


static func load_from_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("cannot open store catalog: %s" % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("store catalog contains invalid JSON: %s" % parser.get_error_message())
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var validation := Validator.validate_stores(catalog)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": validation.get("errors", []).duplicate()}
	return {"ok": true, "catalog": catalog.duplicate(true), "errors": []}


static func find_store(catalog: Dictionary, store_id: String) -> Dictionary:
	for raw_store: Variant in Array(catalog.get("stores", [])):
		if raw_store is Dictionary and String(raw_store.get("store_id", "")) == store_id:
			return Dictionary(raw_store).duplicate(true)
	return {}


static func find_archetype(catalog: Dictionary, archetype_id: String) -> Dictionary:
	for raw_value: Variant in Array(catalog.get("archetypes", [])):
		if raw_value is Dictionary and String(raw_value.get("archetype_id", "")) == archetype_id:
			return Dictionary(raw_value).duplicate(true)
	return {}


static func profile_for_store(catalog: Dictionary, store_id: String) -> Dictionary:
	var store := find_store(catalog, store_id)
	if store.is_empty():
		return {}
	var archetype := find_archetype(catalog, String(store.get("archetype_id", "")))
	return {"store": store, "archetype": archetype} if not archetype.is_empty() else {}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": {}, "errors": [message]}
