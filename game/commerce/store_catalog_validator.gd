class_name StoreCatalogValidator
extends RefCounted

const Rules := preload("res://game/commerce/commerce_validation_rules.gd")
const SCHEMA_VERSION := 1
const USED_POLICIES := ["sealed_only", "new_and_serviceable", "second_hand"]


static func validate(catalog: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not catalog is Dictionary:
		return Rules.result(["store catalog must be a dictionary"])
	var root: Dictionary = catalog
	Rules.expect_int(root, "schema_version", 1, SCHEMA_VERSION, "stores", errors)
	Rules.expect_positive_int(root, "catalog_version", "stores", errors)
	Rules.expect_id(root.get("catalog_id", null), "stores.catalog_id", errors)
	var schedules: Variant = root.get("schedules", null)
	var archetypes: Variant = root.get("archetypes", null)
	var stores: Variant = root.get("stores", null)
	if not schedules is Array:
		errors.append("stores.schedules must be an array")
	else:
		_validate_schedules(schedules, errors)
	if not archetypes is Array:
		errors.append("stores.archetypes must be an array")
	else:
		_validate_archetypes(archetypes, errors)
	if not stores is Array:
		errors.append("stores.stores must be an array")
	else:
		_validate_store_instances(stores, errors)
	return Rules.result(errors)


static func _validate_schedules(values: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for index in range(values.size()):
		var path := "stores.schedules[%d]" % index
		if not values[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var schedule: Dictionary = values[index]
		var schedule_id := Rules.expect_id(schedule.get("schedule_id", null), "%s.schedule_id" % path, errors)
		if seen.has(schedule_id) and not schedule_id.is_empty():
			errors.append("duplicate schedule_id: %s" % schedule_id)
		seen[schedule_id] = true
		var entries: Variant = schedule.get("entries", null)
		if not entries is Array or entries.is_empty():
			errors.append("%s.entries must be a non-empty array" % path)
			continue
		for entry_index in range(entries.size()):
			_validate_schedule_entry(entries[entry_index], "%s.entries[%d]" % [path, entry_index], errors)


static func _validate_schedule_entry(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s must be a dictionary" % path)
		return
	var entry: Dictionary = value
	var days: Variant = entry.get("days", null)
	if not days is Array or days.is_empty():
		errors.append("%s.days must be a non-empty array" % path)
	else:
		for day: Variant in days:
			if not Rules.is_int_in_range(day, 1, 7):
				errors.append("%s.days must contain integers from 1 to 7" % path)
	if not Rules.is_int_in_range(entry.get("opens_minute", null), 0, 1439) or not Rules.is_int_in_range(entry.get("closes_minute", null), 1, 1440):
		errors.append("%s opening hours are invalid" % path)
	elif int(entry["opens_minute"]) >= int(entry["closes_minute"]):
		errors.append("%s must close after it opens" % path)


static func _validate_archetypes(values: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for index in range(values.size()):
		var path := "stores.archetypes[%d]" % index
		if not values[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var value: Dictionary = values[index]
		var archetype_id := Rules.expect_id(value.get("archetype_id", null), "%s.archetype_id" % path, errors)
		if seen.has(archetype_id) and not archetype_id.is_empty():
			errors.append("duplicate archetype_id: %s" % archetype_id)
		seen[archetype_id] = true
		Rules.expect_text(value.get("title", null), "%s.title" % path, errors)
		_validate_category_weights(value.get("category_weights", null), path, errors)
		Rules.expect_range(value.get("offer_count_range", null), 1, 100, "%s.offer_count_range" % path, errors)
		Rules.expect_range(value.get("price_band", null), 1, 100000, "%s.price_band" % path, errors)
		Rules.expect_range(value.get("quality_band", null), 0, 100, "%s.quality_band" % path, errors)
		Rules.expect_range(value.get("condition_range", null), 0, 100, "%s.condition_range" % path, errors)
		Rules.expect_range(value.get("quantity_range", null), 1, 999, "%s.quantity_range" % path, errors)
		Rules.expect_positive_int(value, "restock_interval", path, errors)
		if String(value.get("used_goods_policy", "")) not in USED_POLICIES:
			errors.append("%s.used_goods_policy is unknown" % path)
		_validate_payment_methods(value.get("payment_methods_by_era", null), "%s.payment_methods_by_era" % path, errors)
		Rules.expect_id_array(value.get("guaranteed_product_ids", null), "%s.guaranteed_product_ids" % path, errors)
		_validate_buyback(value.get("buyback_policy", null), "%s.buyback_policy" % path, errors)


static func _validate_category_weights(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary or value.is_empty():
		errors.append("%s.category_weights must be a non-empty dictionary" % path)
		return
	for key: Variant in value:
		Rules.expect_id(key, "%s.category_weights key" % path, errors)
		if not Rules.is_positive_int(value[key]):
			errors.append("%s.category_weights.%s must be a positive integer" % [path, key])


static func _validate_store_instances(values: Array, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for index in range(values.size()):
		var path := "stores.stores[%d]" % index
		if not values[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var value: Dictionary = values[index]
		var store_id := Rules.expect_id(value.get("store_id", null), "%s.store_id" % path, errors)
		if seen.has(store_id) and not store_id.is_empty():
			errors.append("duplicate store_id: %s" % store_id)
		seen[store_id] = true
		for field in ["archetype_id", "location_id", "schedule_id"]:
			Rules.expect_id(value.get(field, null), "%s.%s" % [path, field], errors)
		for field in ["owner_npc_id", "organization_id"]:
			if value.has(field):
				Rules.expect_id(value.get(field, null), "%s.%s" % [path, field], errors)
		Rules.expect_text(value.get("title", null), "%s.title" % path, errors)
		if not Rules.is_positive_int(value.get("markup_basis_points", null)):
			errors.append("%s.markup_basis_points must be a positive integer" % path)
		if not value.get("assortment_rules", null) is Array:
			errors.append("%s.assortment_rules must be an array" % path)
		_validate_world_requirements(value.get("world_fact_requirements", null), "%s.world_fact_requirements" % path, errors)


static func _validate_payment_methods(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or value.is_empty():
		errors.append("%s must be a non-empty array" % path)
		return
	for index in range(value.size()):
		if not value[index] is Dictionary:
			errors.append("%s[%d] must be a dictionary" % [path, index])
			continue
		var era: Dictionary = value[index]
		Rules.expect_positive_int(era, "available_from", "%s[%d]" % [path, index], errors)
		Rules.expect_id_array(era.get("method_ids", null), "%s[%d].method_ids" % [path, index], errors)


static func _validate_world_requirements(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("%s must be an array" % path)
		return
	for index in range(value.size()):
		if not value[index] is Dictionary:
			errors.append("%s[%d] must be a dictionary" % [path, index])
			continue
		var requirement: Dictionary = value[index]
		Rules.expect_id(requirement.get("fact_id", null), "%s[%d].fact_id" % [path, index], errors)
		if typeof(requirement.get("expected", null)) != TYPE_BOOL:
			errors.append("%s[%d].expected must be boolean" % [path, index])


static func _validate_buyback(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s must be a dictionary" % path)
		return
	if typeof(value.get("enabled", null)) != TYPE_BOOL:
		errors.append("%s.enabled must be boolean" % path)
	Rules.expect_id_array(value.get("accepted_category_ids", null), "%s.accepted_category_ids" % path, errors)
	if not Rules.is_int_in_range(value.get("payout_basis_points", null), 0, 10000):
		errors.append("%s.payout_basis_points must be an integer from 0 to 10000" % path)
	if bool(value.get("enabled", false)) and Array(value.get("accepted_category_ids", [])).is_empty():
		errors.append("%s must list accepted categories when enabled" % path)
