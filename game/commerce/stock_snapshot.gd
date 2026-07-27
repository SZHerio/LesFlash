class_name StockSnapshot
extends RefCounted

## Versioned, JSON-safe persisted stock. It is the source of truth between restocks.

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const SCHEMA_VERSION := 1
const PREVIOUS_SCHEMA_VERSION := 0
const REQUIRED_VERSION_FIELDS := [
	"generator_version",
	"product_catalog_version",
	"store_catalog_version",
	"chronology_version",
]


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return _result(["stock snapshot must be a dictionary"])
	var json_validation := JsonValidator.validate(value, "stock_snapshot")
	errors.append_array(json_validation.get("errors", []))
	var snapshot: Dictionary = value
	_expect_int(snapshot, "schema_version", SCHEMA_VERSION, SCHEMA_VERSION, errors)
	for field: String in REQUIRED_VERSION_FIELDS:
		_expect_int(snapshot, field, 1, 1_000_000, errors)
	_expect_token(snapshot.get("store_id", null), "store_id", errors)
	_expect_int(snapshot, "restock_sequence", 0, 1_000_000_000, errors)
	_validate_stamp(snapshot.get("generated_at", null), errors)
	_expect_int(snapshot, "next_restock_at", 0, 9_007_199_254_740_991, errors)
	if snapshot.get("generated_at", null) is Dictionary:
		var elapsed := int(Dictionary(snapshot["generated_at"]).get("elapsed_minutes", 0))
		if typeof(snapshot.get("next_restock_at", null)) == TYPE_INT and int(snapshot["next_restock_at"]) <= elapsed:
			errors.append("next_restock_at must be later than generated_at.elapsed_minutes")
	_validate_seed(snapshot.get("seed", null), errors)
	_expect_int(snapshot, "revision", 0, 1_000_000_000, errors)
	_validate_command_ids(snapshot.get("applied_command_ids", null), errors)
	var offers: Variant = snapshot.get("offers", null)
	if not offers is Array:
		errors.append("offers must be an array")
	else:
		_validate_offers(offers, errors)
	return _result(errors)


static func migrate_serialized(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_snapshot", "stock snapshot must be a dictionary")
	var source: Dictionary = JsonValidator.normalize_numbers(Dictionary(value).duplicate(true))
	var version_value: Variant = source.get("schema_version", null)
	if typeof(version_value) != TYPE_INT:
		return _failure("invalid_schema_version", "stock schema version must be an integer")
	var version := int(version_value)
	if version == SCHEMA_VERSION:
		var current_validation := validate(source)
		return (
			{"ok": true, "snapshot": source.duplicate(true), "migrated_from": SCHEMA_VERSION, "errors": []}
			if bool(current_validation.get("ok", false))
			else {"ok": false, "snapshot": {}, "code": "invalid_snapshot", "errors": current_validation.get("errors", [])}
		)
	if version != PREVIOUS_SCHEMA_VERSION:
		return _failure("unsupported_schema_version", "unsupported stock schema version %d" % version)
	if typeof(source.get("catalog_version", null)) != TYPE_INT:
		return _failure("invalid_previous_snapshot", "v0 stock requires catalog_version")
	var migrated := source.duplicate(true)
	migrated["schema_version"] = SCHEMA_VERSION
	migrated["product_catalog_version"] = int(migrated["catalog_version"])
	migrated.erase("catalog_version")
	migrated["store_catalog_version"] = 1
	migrated["revision"] = 0
	migrated["applied_command_ids"] = []
	var validation := validate(migrated)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "snapshot": {}, "code": "invalid_migration", "errors": validation.get("errors", [])}
	return {"ok": true, "snapshot": migrated, "migrated_from": PREVIOUS_SCHEMA_VERSION, "errors": []}


static func validate_catalog_references(
	snapshot: Variant,
	product_catalog: Dictionary,
	store_catalog: Dictionary = {}
) -> Dictionary:
	var validation := validate(snapshot)
	if not bool(validation.get("ok", false)):
		return validation
	var errors: Array = []
	if int(snapshot["product_catalog_version"]) != int(product_catalog.get("catalog_version", -1)):
		errors.append("stock product_catalog_version does not match supplied catalog")
	var products: Dictionary = {}
	for raw_product: Variant in Array(product_catalog.get("products", [])):
		if raw_product is Dictionary:
			products[String(raw_product.get("product_id", ""))] = raw_product
	for raw_offer: Variant in Array(snapshot["offers"]):
		var offer: Dictionary = raw_offer
		var product_id := String(offer["product_id"])
		if not products.has(product_id):
			errors.append("offer %s references unknown product %s" % [offer["offer_id"], product_id])
			continue
		var product: Dictionary = products[product_id]
		if String(offer["item_id"]) != String(product.get("item_id", "")):
			errors.append("offer %s item_id disagrees with product" % offer["offer_id"])
		if String(offer["category_id"]) != String(product.get("category_id", "")):
			errors.append("offer %s category_id disagrees with product" % offer["offer_id"])
	if not store_catalog.is_empty():
		if int(snapshot["store_catalog_version"]) != int(store_catalog.get("catalog_version", -1)):
			errors.append("stock store_catalog_version does not match supplied catalog")
		var store_found := false
		for raw_store: Variant in Array(store_catalog.get("stores", [])):
			if raw_store is Dictionary and String(raw_store.get("store_id", "")) == String(snapshot["store_id"]):
				store_found = true
		if not store_found:
			errors.append("stock references unknown store %s" % snapshot["store_id"])
	return _result(errors)


static func with_committed_command(snapshot: Dictionary, command_id: String, offers: Array) -> Dictionary:
	var candidate := snapshot.duplicate(true)
	candidate["offers"] = offers.duplicate(true)
	candidate["revision"] = int(candidate.get("revision", 0)) + 1
	var command_ids: Array = Array(candidate.get("applied_command_ids", [])).duplicate()
	command_ids.append(command_id)
	candidate["applied_command_ids"] = command_ids
	return candidate


static func has_command(snapshot: Dictionary, command_id: String) -> bool:
	return command_id in Array(snapshot.get("applied_command_ids", []))


static func find_offer_index(snapshot: Dictionary, offer_id: String) -> int:
	var offers: Array = snapshot.get("offers", [])
	for index in range(offers.size()):
		if offers[index] is Dictionary and String(offers[index].get("offer_id", "")) == offer_id:
			return index
	return -1


static func _validate_stamp(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("generated_at must be a dictionary")
		return
	var stamp: Dictionary = value
	var ranges := {
		"year": [1, 9999],
		"month": [1, 12],
		"day": [1, 31],
		"minute_of_day": [0, 1439],
		"elapsed_minutes": [0, 9_007_199_254_740_991],
	}
	for field: String in ranges:
		var limits: Array = ranges[field]
		if not _is_int_in_range(stamp.get(field, null), int(limits[0]), int(limits[1])):
			errors.append("generated_at.%s is invalid" % field)


static func _validate_seed(value: Variant, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or not String(value).is_valid_int() or int(String(value)) <= 0:
		errors.append("seed must be a positive integer encoded as a decimal string")


static func _validate_command_ids(value: Variant, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("applied_command_ids must be an array")
		return
	var seen: Dictionary = {}
	for index in range(value.size()):
		var command_id := _expect_token(value[index], "applied_command_ids[%d]" % index, errors)
		if not command_id.is_empty() and seen.has(command_id):
			errors.append("applied_command_ids repeats %s" % command_id)
		seen[command_id] = true


static func _validate_offers(offers: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for index in range(offers.size()):
		var path := "offers[%d]" % index
		if not offers[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var offer: Dictionary = offers[index]
		var offer_id := _expect_token(offer.get("offer_id", null), "%s.offer_id" % path, errors)
		if seen.has(offer_id) and not offer_id.is_empty():
			errors.append("duplicate offer_id %s" % offer_id)
		seen[offer_id] = true
		for field in ["product_id", "item_id", "category_id"]:
			_expect_token(offer.get(field, null), "%s.%s" % [path, field], errors)
		_expect_int(offer, "quantity", 1, 999_999, errors, path)
		_expect_int(offer, "unit_price", 0, 1_000_000_000_000, errors, path)
		_expect_int(offer, "condition", 0, 100, errors, path)
		_expect_int(offer, "quality", 0, 100, errors, path)
		_expect_int(offer, "expires_at", -1, 9_007_199_254_740_991, errors, path)
		_expect_token(offer.get("batch_id", null), "%s.batch_id" % path, errors)


static func _expect_token(value: Variant, path: String, errors: Array[String]) -> String:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty() or String(value).length() > 160:
		errors.append("%s must be a non-empty bounded string" % path)
		return ""
	return String(value)


static func _expect_int(
	value: Dictionary,
	field: String,
	minimum: int,
	maximum: int,
	errors: Array[String],
	path: String = "stock_snapshot"
) -> void:
	if not _is_int_in_range(value.get(field, null), minimum, maximum):
		errors.append("%s.%s must be an integer from %d to %d" % [path, field, minimum, maximum])


static func _is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _result(errors: Array) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "snapshot": {}, "code": code, "errors": [message]}
