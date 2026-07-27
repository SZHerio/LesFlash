class_name CommerceCatalogValidator
extends RefCounted

## Pure facade plus cross-catalog reference validation.

const ProductValidator := preload("res://game/commerce/product_catalog_validator.gd")
const StoreValidator := preload("res://game/commerce/store_catalog_validator.gd")
const PRODUCT_SCHEMA_VERSION := 1
const STORE_SCHEMA_VERSION := 1


static func validate_products(catalog: Variant, known_item_ids: Dictionary = {}) -> Dictionary:
	return ProductValidator.validate(catalog, known_item_ids)


static func validate_stores(catalog: Variant) -> Dictionary:
	return StoreValidator.validate(catalog)


static func validate_references(
	product_catalog: Variant,
	store_catalog: Variant,
	known_item_ids: Dictionary = {}
) -> Dictionary:
	var errors: Array = []
	errors.append_array(validate_products(product_catalog, known_item_ids).get("errors", []))
	errors.append_array(validate_stores(store_catalog).get("errors", []))
	if not errors.is_empty():
		return _result(errors)
	var products: Dictionary = {}
	var categories: Dictionary = {}
	for raw_product: Variant in Array(product_catalog.get("products", [])):
		var product: Dictionary = raw_product
		products[String(product["product_id"])] = product
		categories[String(product["category_id"])] = true
	for product_id: Variant in products:
		var product: Dictionary = products[product_id]
		for replacement_id: Variant in Array(product.get("replacement_product_ids", [])):
			if not products.has(String(replacement_id)):
				errors.append("%s replaces unknown product %s" % [product_id, replacement_id])
	var schedules: Dictionary = {}
	for raw_schedule: Variant in Array(store_catalog.get("schedules", [])):
		schedules[String(raw_schedule["schedule_id"])] = true
	var archetypes: Dictionary = {}
	for raw_archetype: Variant in Array(store_catalog.get("archetypes", [])):
		var archetype: Dictionary = raw_archetype
		var archetype_id := String(archetype["archetype_id"])
		archetypes[archetype_id] = archetype
		for category_id: Variant in Dictionary(archetype["category_weights"]):
			if not categories.has(String(category_id)):
				errors.append("%s references empty category %s" % [archetype_id, category_id])
		for guaranteed_id: Variant in Array(archetype["guaranteed_product_ids"]):
			if not products.has(String(guaranteed_id)):
				errors.append("%s guarantees unknown product %s" % [archetype_id, guaranteed_id])
				continue
			var guaranteed: Dictionary = products[String(guaranteed_id)]
			if not Dictionary(archetype["category_weights"]).has(String(guaranteed["category_id"])):
				errors.append("%s guarantees product outside its categories: %s" % [archetype_id, guaranteed_id])
	for raw_store: Variant in Array(store_catalog.get("stores", [])):
		var store: Dictionary = raw_store
		if not archetypes.has(String(store["archetype_id"])):
			errors.append("%s references unknown archetype %s" % [store["store_id"], store["archetype_id"]])
		if not schedules.has(String(store["schedule_id"])):
			errors.append("%s references unknown schedule %s" % [store["store_id"], store["schedule_id"]])
	return _result(errors)


static func _result(errors: Array) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}
