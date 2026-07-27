class_name ProductCatalogValidator
extends RefCounted

const Rules := preload("res://game/commerce/commerce_validation_rules.gd")
const SCHEMA_VERSION := 1
const RARITIES := ["common", "uncommon", "rare"]


static func validate(catalog: Variant, known_item_ids: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	if not catalog is Dictionary:
		return Rules.result(["product catalog must be a dictionary"])
	var root: Dictionary = catalog
	Rules.expect_int(root, "schema_version", 1, SCHEMA_VERSION, "products", errors)
	Rules.expect_positive_int(root, "catalog_version", "products", errors)
	Rules.expect_id(root.get("catalog_id", null), "products.catalog_id", errors)
	var values: Variant = root.get("products", null)
	if not values is Array:
		errors.append("products.products must be an array")
		return Rules.result(errors)
	var seen: Dictionary = {}
	for index in range(values.size()):
		var path := "products.products[%d]" % index
		if not values[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var product: Dictionary = values[index]
		var product_id := Rules.expect_id(product.get("product_id", null), "%s.product_id" % path, errors)
		if not product_id.is_empty():
			if seen.has(product_id):
				errors.append("duplicate product_id: %s" % product_id)
			seen[product_id] = true
		var item_id := Rules.expect_id(product.get("item_id", null), "%s.item_id" % path, errors)
		if not known_item_ids.is_empty() and not item_id.is_empty() and not known_item_ids.has(item_id):
			errors.append("%s references unknown item_id %s" % [path, item_id])
		Rules.expect_text(product.get("title", null), "%s.title" % path, errors)
		Rules.expect_id(product.get("category_id", null), "%s.category_id" % path, errors)
		Rules.expect_positive_int(product, "base_value_1980", path, errors)
		Rules.expect_positive_int(product, "available_from", path, errors)
		Rules.expect_range(product.get("quality_range", null), 0, 100, "%s.quality_range" % path, errors)
		Rules.expect_range(product.get("condition_range", null), 0, 100, "%s.condition_range" % path, errors)
		Rules.expect_range(product.get("stock_quantity_range", null), 1, 999, "%s.stock_quantity_range" % path, errors)
		Rules.expect_positive_int(product, "selection_weight", path, errors)
		if String(product.get("rarity", "")) not in RARITIES:
			errors.append("%s.rarity is unknown" % path)
		Rules.expect_id_array(product.get("required_world_facts", null), "%s.required_world_facts" % path, errors)
		Rules.expect_id_array(product.get("excluded_world_facts", null), "%s.excluded_world_facts" % path, errors)
		Rules.expect_id_array(product.get("replacement_product_ids", null), "%s.replacement_product_ids" % path, errors)
		if product.has("perishable_days"):
			Rules.expect_positive_int(product, "perishable_days", path, errors)
		_validate_chronology(product, path, errors)
	return Rules.result(errors)


static func _validate_chronology(product: Dictionary, path: String, errors: Array[String]) -> void:
	var available := int(product.get("available_from", 0))
	if product.has("ordinary_until"):
		if not Rules.is_positive_int(product["ordinary_until"]):
			errors.append("%s.ordinary_until must be a positive integer" % path)
		elif int(product["ordinary_until"]) < available:
			errors.append("%s.ordinary_until precedes available_from" % path)
	if product.has("legacy_until"):
		if not Rules.is_positive_int(product["legacy_until"]):
			errors.append("%s.legacy_until must be a positive integer" % path)
		elif product.has("ordinary_until") and int(product["legacy_until"]) < int(product["ordinary_until"]):
			errors.append("%s.legacy_until precedes ordinary_until" % path)
