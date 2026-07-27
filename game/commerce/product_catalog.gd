class_name ProductCatalog
extends RefCounted

const Validator := preload("res://game/commerce/commerce_catalog_validator.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const DEFAULT_PATH := "res://game/commerce/data/product_catalog_v1.json"


static func load_default() -> Dictionary:
	return load_from_path(DEFAULT_PATH)


static func load_from_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("cannot open product catalog: %s" % path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("product catalog contains invalid JSON: %s" % parser.get_error_message())
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var validation := Validator.validate_products(catalog, known_item_ids())
	if not bool(validation.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": validation.get("errors", []).duplicate()}
	return {"ok": true, "catalog": catalog.duplicate(true), "errors": []}


static func find(catalog: Dictionary, product_id: String) -> Dictionary:
	for raw_product: Variant in Array(catalog.get("products", [])):
		if raw_product is Dictionary and String(raw_product.get("product_id", "")) == product_id:
			return Dictionary(raw_product).duplicate(true)
	return {}


static func find_by_item(catalog: Dictionary, item_id: String) -> Array:
	var result: Array = []
	for raw_product: Variant in Array(catalog.get("products", [])):
		if raw_product is Dictionary and String(raw_product.get("item_id", "")) == item_id:
			result.append(Dictionary(raw_product).duplicate(true))
	return result


static func known_item_ids() -> Dictionary:
	var result: Dictionary = {}
	for definition: Variant in ItemCatalogScript.all_definitions():
		result[String(definition.id())] = true
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": {}, "errors": [message]}
