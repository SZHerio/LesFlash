class_name StockGenerator
extends RefCounted

## Deterministic restock generator. It consumes immutable request/catalog values only.

const CatalogValidator := preload("res://game/commerce/commerce_catalog_validator.gd")
const ProductCatalogScript := preload("res://game/commerce/product_catalog.gd")
const StoreCatalogScript := preload("res://game/commerce/store_catalog.gd")
const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")
const OfferGenerator := preload("res://game/commerce/stock_offer_generator.gd")
const StockSnapshotScript := preload("res://game/commerce/stock_snapshot.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")

const GENERATOR_VERSION := 1
const DEFAULT_CHRONOLOGY_VERSION := 1
const HASH_MODULUS := 2_147_483_647


static func generate(product_catalog: Dictionary, store_catalog: Dictionary, request: Dictionary) -> Dictionary:
	var references := CatalogValidator.validate_references(
		product_catalog,
		store_catalog,
		ProductCatalogScript.known_item_ids()
	)
	if not bool(references.get("ok", false)):
		return _failure("invalid_catalog", references.get("errors", []))
	var request_validation := _validate_request(request)
	if not bool(request_validation.get("ok", false)):
		return _failure("invalid_request", request_validation.get("errors", []))
	var store_id := String(request["store_id"])
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return _failure("unknown_store", ["unknown store_id %s" % store_id])
	var store: Dictionary = profile["store"]
	var archetype: Dictionary = profile["archetype"]
	var facts := _fact_set(request.get("world_facts", {}))
	if not _requirements_met(store, facts):
		return _failure("store_unavailable", ["world facts make %s unavailable" % store_id])
	var seed_material := _seed_material(product_catalog, request)
	var derived_seed := _stable_seed(seed_material)
	var rng = RngScript.new(derived_seed)
	var analysis := _analyze_products(product_catalog, archetype, request, facts)
	var eligible: Array = analysis["eligible"]
	if eligible.is_empty():
		return _failure("empty_stock_pool", ["no products are eligible for %s" % store_id], analysis["trace"])
	var offers_result := OfferGenerator.build(eligible, store, archetype, request, rng)
	if not bool(offers_result.get("ok", false)):
		return offers_result
	var elapsed := int(Dictionary(request["generated_at"])["elapsed_minutes"])
	var interval := int(archetype["restock_interval"])
	if elapsed > 9_007_199_254_740_991 - interval:
		return _failure("time_overflow", ["next restock exceeds the persisted time domain"])
	var snapshot := {
		"schema_version": StockSnapshotScript.SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"product_catalog_version": int(product_catalog["catalog_version"]),
		"store_catalog_version": int(store_catalog["catalog_version"]),
		"chronology_version": int(request.get("chronology_version", DEFAULT_CHRONOLOGY_VERSION)),
		"store_id": store_id,
		"restock_sequence": int(request["restock_sequence"]),
		"generated_at": Dictionary(request["generated_at"]).duplicate(true),
		"next_restock_at": elapsed + interval,
		"seed": str(derived_seed),
		"revision": 0,
		"applied_command_ids": [],
		"offers": offers_result["offers"],
	}
	var validation := StockSnapshotScript.validate(snapshot)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_generated_snapshot", validation.get("errors", []), analysis["trace"])
	var catalog_validation := StockSnapshotScript.validate_catalog_references(snapshot, product_catalog, store_catalog)
	if not bool(catalog_validation.get("ok", false)):
		return _failure("invalid_generated_references", catalog_validation.get("errors", []), analysis["trace"])
	return {
		"ok": true,
		"code": "ok",
		"snapshot": snapshot,
		"trace": analysis["trace"],
		"seed_material": seed_material,
	}


static func _analyze_products(
	product_catalog: Dictionary,
	archetype: Dictionary,
	request: Dictionary,
	facts: Dictionary
) -> Dictionary:
	var eligible: Array = []
	var trace: Array = []
	var categories: Dictionary = archetype["category_weights"]
	var year := int(Dictionary(request["generated_at"])["year"])
	for raw_product: Variant in Array(product_catalog["products"]):
		var product: Dictionary = raw_product
		var reason := ""
		if not categories.has(String(product["category_id"])):
			reason = "category_not_sold"
		elif year < int(product["available_from"]):
			reason = "not_introduced"
		elif product.has("legacy_until") and year > int(product["legacy_until"]):
			reason = "obsolete"
		elif product.has("ordinary_until") and year > int(product["ordinary_until"]) and String(archetype["used_goods_policy"]) != "second_hand":
			reason = "ordinary_period_ended"
		elif not _requirements_met(product, facts):
			reason = "world_facts"
		var included := reason.is_empty()
		trace.append({"product_id": String(product["product_id"]), "included": included, "reason": reason})
		if included:
			eligible.append(product)
	return {"eligible": eligible, "trace": trace}


static func _validate_request(request: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var run_seed: Variant = request.get("run_seed", null)
	if not (
		typeof(run_seed) == TYPE_INT
		or (typeof(run_seed) == TYPE_STRING and String(run_seed).is_valid_int())
	):
		errors.append("run_seed must be an integer or decimal integer string")
	if typeof(request.get("store_id", null)) != TYPE_STRING or String(request.get("store_id", "")).is_empty():
		errors.append("store_id must be non-empty")
	if typeof(request.get("restock_sequence", null)) != TYPE_INT or int(request.get("restock_sequence", -1)) < 0:
		errors.append("restock_sequence must be a non-negative integer")
	var stamp: Variant = request.get("generated_at", null)
	if not stamp is Dictionary:
		errors.append("generated_at must be a dictionary")
	else:
		for field in ["year", "month", "day", "minute_of_day", "elapsed_minutes"]:
			if typeof(stamp.get(field, null)) != TYPE_INT or int(stamp.get(field, -1)) < 0:
				errors.append("generated_at.%s must be a non-negative integer" % field)
		if int(stamp.get("year", 0)) < 1 or int(stamp.get("month", 0)) not in range(1, 13) or int(stamp.get("day", 0)) not in range(1, 32) or int(stamp.get("minute_of_day", -1)) > 1439:
			errors.append("generated_at calendar fields are out of range")
	if typeof(request.get("chronology_version", DEFAULT_CHRONOLOGY_VERSION)) != TYPE_INT or int(request.get("chronology_version", 0)) < 1:
		errors.append("chronology_version must be a positive integer")
	if typeof(request.get("luck", 5)) != TYPE_INT or int(request.get("luck", 0)) not in range(1, 11):
		errors.append("luck must be an integer from 1 to 10")
	for field in ["consumer_price_index_basis_points", "district_basis_points", "relationship_basis_points"]:
		if not _valid_factor(request.get(field, 10_000)):
			errors.append("%s is not a valid basis-point factor" % field)
	var supply: Variant = request.get("category_supply_basis_points", {})
	if not supply is Dictionary:
		errors.append("category_supply_basis_points must be a dictionary")
	else:
		for value: Variant in supply.values():
			if not _valid_factor(value):
				errors.append("category_supply_basis_points contains an invalid factor")
	var world_facts: Variant = request.get("world_facts", {})
	if not world_facts is Dictionary and not world_facts is Array:
		errors.append("world_facts must be a dictionary or array")
	elif world_facts is Dictionary:
		for fact_id: Variant in world_facts:
			var fact_value: Variant = world_facts[fact_id]
			var typed_record := fact_value is Dictionary and typeof(fact_value.get("value", null)) == TYPE_BOOL
			if typeof(fact_id) != TYPE_STRING or String(fact_id).is_empty() or (typeof(fact_value) != TYPE_BOOL and not typed_record):
				errors.append("world_facts dictionary must map non-empty string IDs to booleans or typed fact records")
	elif world_facts is Array:
		for fact_id: Variant in world_facts:
			if typeof(fact_id) != TYPE_STRING or String(fact_id).is_empty():
				errors.append("world_facts array must contain non-empty string IDs")
	return {"ok": errors.is_empty(), "errors": errors}


static func _requirements_met(value: Dictionary, facts: Dictionary) -> bool:
	for raw_requirement: Variant in Array(value.get("world_fact_requirements", [])):
		if not raw_requirement is Dictionary:
			return false
		var requirement: Dictionary = raw_requirement
		if facts.has(String(requirement.get("fact_id", ""))) != bool(requirement.get("expected", false)):
			return false
	for fact_id: Variant in Array(value.get("required_world_facts", [])):
		if not facts.has(String(fact_id)):
			return false
	for fact_id: Variant in Array(value.get("excluded_world_facts", [])):
		if facts.has(String(fact_id)):
			return false
	return true


static func _fact_set(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		for fact_id: Variant in value:
			var raw_value: Variant = value[fact_id]
			var enabled := false
			if typeof(raw_value) == TYPE_BOOL:
				enabled = raw_value
			elif raw_value is Dictionary:
				enabled = bool(raw_value.get("value", false))
			if enabled:
				result[String(fact_id)] = true
	elif value is Array:
		for fact_id: Variant in value:
			result[String(fact_id)] = true
	return result


static func _seed_material(product_catalog: Dictionary, request: Dictionary) -> String:
	return "%s|%s|%d|%d|%d|%d" % [
		str(request["run_seed"]),
		String(request["store_id"]),
		int(request["restock_sequence"]),
		GENERATOR_VERSION,
		int(product_catalog["catalog_version"]),
		int(request.get("chronology_version", DEFAULT_CHRONOLOGY_VERSION)),
	]


static func _stable_seed(material: String) -> int:
	var value := 17_171
	for byte: int in material.to_utf8_buffer():
		value = (value * 131 + byte) % HASH_MODULUS
	return value if value > 0 else 1


static func _valid_factor(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= PriceResolverScript.MAX_FACTOR_BASIS_POINTS


static func _failure(code: String, errors: Array, trace: Array = []) -> Dictionary:
	return {"ok": false, "code": code, "errors": errors.duplicate(), "trace": trace.duplicate(true)}
