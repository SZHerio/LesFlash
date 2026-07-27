extends SceneTree

const CatalogValidator := preload("res://game/commerce/commerce_catalog_validator.gd")
const ProductCatalogScript := preload("res://game/commerce/product_catalog.gd")
const StoreCatalogScript := preload("res://game/commerce/store_catalog.gd")
const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")
const StockGeneratorScript := preload("res://game/commerce/stock_generator.gd")
const StockSnapshotScript := preload("res://game/commerce/stock_snapshot.gd")
const Transaction := preload("res://game/commerce/commerce_transaction.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const RunStateScript := preload("res://core/state/run_state.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""
var _products: Dictionary = {}
var _stores: Dictionary = {}


class FakeWorldState:
	extends RefCounted
	var stock_snapshots: Dictionary = {}

	func _init(values: Dictionary = {}) -> void:
		stock_snapshots = values.duplicate(true)

	func clone() -> FakeWorldState:
		return FakeWorldState.new(stock_snapshots)

	func get_stock_snapshot(store_id: String) -> Dictionary:
		return Dictionary(stock_snapshots.get(store_id, {})).duplicate(true)

	func set_stock_snapshot(store_id: String, snapshot: Dictionary) -> bool:
		stock_snapshots[store_id] = snapshot.duplicate(true)
		return true

	func validate() -> Dictionary:
		return {"ok": true, "errors": []}


func _init() -> void:
	_load_catalogs()
	_run("versioned product and three store profiles validate", _test_catalogs)
	_run("catalog validators are pure and reject broken references", _test_catalog_validation_purity)
	_run("price pipeline has fixed integer order and half-up rounding", _test_price_pipeline)
	_run("stock generation is deterministic and does not consume run RNG", _test_stock_determinism)
	_run("Luck changes unknown uncommon supply without rerolling shown stock", _test_luck_supply)
	_run("era and world facts filter the authored product pool", _test_era_and_world_facts)
	_run("stock snapshot round-trips and v0 migrates without mutation", _test_snapshot_and_migration)
	_run("buy prepares atomic candidates with conflicts and idempotency", _test_buy_transaction)
	_run("commission buyback prepares sale candidates", _test_sell_transaction)
	if _failures.is_empty():
		print("M3F.1 COMMERCE TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.1 COMMERCE TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _load_catalogs() -> void:
	var products_result := ProductCatalogScript.load_default()
	var stores_result := StoreCatalogScript.load_default()
	if bool(products_result.get("ok", false)):
		_products = products_result["catalog"]
	else:
		_failures.append("catalog bootstrap — %s" % str(products_result.get("errors", [])))
	if bool(stores_result.get("ok", false)):
		_stores = stores_result["catalog"]
	else:
		_failures.append("store bootstrap — %s" % str(stores_result.get("errors", [])))


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_catalogs() -> void:
	_expect(not _products.is_empty() and not _stores.is_empty(), "default catalogs must load")
	if _products.is_empty() or _stores.is_empty():
		return
	var references := CatalogValidator.validate_references(_products, _stores)
	_expect(bool(references.get("ok", false)), "cross references must validate: %s" % str(references.get("errors", [])))
	_expect_equal(_products.get("schema_version"), 1, "product schema must be explicit")
	_expect_equal(_stores.get("schema_version"), 1, "store schema must be explicit")
	var store_ids: Array[String] = []
	var archetype_ids: Dictionary = {}
	for raw_store: Variant in Array(_stores.get("stores", [])):
		var store: Dictionary = raw_store
		store_ids.append(String(store["store_id"]))
		archetype_ids[String(store["archetype_id"])] = true
	store_ids.sort()
	_expect_equal(store_ids, [
		"store_clinic_pharmacy_window",
		"store_market_food_row",
		"store_station_commission",
	], "M3F.1 must author exactly the three canonical stores")
	_expect_equal(archetype_ids.size(), 3, "the stores must have distinct profiles")
	var commission := StoreCatalogScript.profile_for_store(_stores, "store_station_commission")
	_expect(bool(Dictionary(commission.get("archetype", {})).get("buyback_policy", {}).get("enabled", false)), "commission store must buy accepted goods")


func _test_catalog_validation_purity() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var products_before := _products.duplicate(true)
	var stores_before := _stores.duplicate(true)
	var duplicate := _products.duplicate(true)
	duplicate["products"].append(Dictionary(duplicate["products"][0]).duplicate(true))
	var duplicate_validation := CatalogValidator.validate_products(duplicate)
	_expect(not bool(duplicate_validation.get("ok", true)), "duplicate product IDs must be rejected")
	var broken := _stores.duplicate(true)
	broken["stores"][0]["archetype_id"] = "archetype_missing"
	var reference_validation := CatalogValidator.validate_references(_products, broken)
	_expect(not bool(reference_validation.get("ok", true)), "unknown archetype reference must be rejected")
	var unknown_item := _products.duplicate(true)
	unknown_item["products"][0]["item_id"] = "missing_item"
	var item_validation := CatalogValidator.validate_references(unknown_item, _stores, ProductCatalogScript.known_item_ids())
	_expect(not bool(item_validation.get("ok", true)), "unknown item reference must be rejected when the item registry is supplied")
	_expect_equal(_products, products_before, "product validation must not mutate its source")
	_expect_equal(_stores, stores_before, "store validation must not mutate its source")


func _test_price_pipeline() -> void:
	var factors := PriceResolverScript.neutral_factors({
		"consumer_price_index_basis_points": 11_000,
		"category_supply_basis_points": 9_000,
		"district_basis_points": 10_500,
		"store_markup_basis_points": 9_500,
		"condition_quality_basis_points": 8_750,
		"relationship_basis_points": 12_000,
	})
	var resolved := PriceResolverScript.resolve(101, factors)
	_expect(bool(resolved.get("ok", false)), "valid factors must resolve")
	_expect_equal(resolved.get("unit_price"), 106, "each stage must round before the next factor")
	var stages: Array[String] = []
	for raw_stage: Variant in Array(resolved.get("trace", [])).slice(1):
		stages.append(String(raw_stage.get("stage", "")))
	_expect_equal(stages, PriceResolverScript.FACTOR_ORDER, "factor order is a saved gameplay contract")
	var half_up := PriceResolverScript.apply_basis_points(1, 5_000)
	_expect_equal(half_up.get("value"), 1, "exact half must round up")
	_expect(not bool(PriceResolverScript.resolve(10, PriceResolverScript.neutral_factors({"district_basis_points": 10_000.0})).get("ok", true)), "float factor must be rejected")
	_expect(not bool(PriceResolverScript.apply_basis_points(PriceResolverScript.MAX_PRICE, 100_000).get("ok", true)), "overflow must be rejected")


func _test_stock_determinism() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var request := _request("store_market_food_row", 0, {"fact_market_print_delivery": true})
	var request_before := request.duplicate(true)
	var products_before := _products.duplicate(true)
	var stores_before := _stores.duplicate(true)
	var run = RunStateScript.new(_build(), 910_111)
	var rng_before: Dictionary = run.rng.to_dict()
	var first := StockGeneratorScript.generate(_products, _stores, request)
	var second := StockGeneratorScript.generate(_products, _stores, request)
	_expect(bool(first.get("ok", false)) and bool(second.get("ok", false)), "same stock request must generate")
	if bool(first.get("ok", false)) and bool(second.get("ok", false)):
		_expect_equal(first["snapshot"], second["snapshot"], "same inputs must generate byte-equivalent values")
		_expect(bool(StockSnapshotScript.validate(first["snapshot"]).get("ok", false)), "generated snapshot must validate")
	var next_request := request.duplicate(true)
	next_request["restock_sequence"] = 1
	var next := StockGeneratorScript.generate(_products, _stores, next_request)
	_expect(bool(next.get("ok", false)), "next restock must generate")
	if bool(first.get("ok", false)) and bool(next.get("ok", false)):
		_expect(String(first["snapshot"]["seed"]) != String(next["snapshot"]["seed"]), "restock sequence must own a distinct seed")
	_expect_equal(request, request_before, "generation must not mutate request")
	_expect_equal(_products, products_before, "generation must not mutate product catalog")
	_expect_equal(_stores, stores_before, "generation must not mutate store catalog")
	_expect_equal(run.rng.to_dict(), rng_before, "stock generation must not consume run RNG")


func _test_era_and_world_facts() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var gated_products := _products.duplicate(true)
	for raw_product: Variant in Array(gated_products["products"]):
		if String(raw_product.get("product_id", "")) == "product_market_newspaper_bundle":
			raw_product["required_world_facts"] = ["fact_test_print_delivery"]
	var without_delivery := StockGeneratorScript.generate(gated_products, _stores, _request("store_market_food_row"))
	var with_delivery := StockGeneratorScript.generate(gated_products, _stores, _request("store_market_food_row", 0, {
		"fact_test_print_delivery": {"value": true, "source_id": "test", "changed_at": {}},
	}))
	_expect_equal(_trace_reason(without_delivery, "product_market_newspaper_bundle"), "world_facts", "missing delivery fact must exclude newspaper")
	_expect_equal(_trace_reason(with_delivery, "product_market_newspaper_bundle"), "", "delivery fact must unlock newspaper in the pool")
	var commission := StockGeneratorScript.generate(_products, _stores, _request("store_station_commission"))
	_expect_equal(_trace_reason(commission, "product_commission_modular_radio_parts"), "not_introduced", "1985 product must not exist in 1980 stock")
	var gated_stores := _stores.duplicate(true)
	for raw_store: Variant in Array(gated_stores["stores"]):
		if String(raw_store.get("store_id", "")) == "store_market_food_row":
			raw_store["world_fact_requirements"] = [{"fact_id": "fact_test_market_closed", "expected": false}]
	var closed := StockGeneratorScript.generate(_products, gated_stores, _request("store_market_food_row", 0, {"fact_test_market_closed": true}))
	_expect_equal(closed.get("code"), "store_unavailable", "world fact can persistently close a store")


func _test_luck_supply() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var low_count := 0
	var high_count := 0
	for sequence in range(300):
		var low_request := _request("store_station_commission", sequence)
		low_request["luck"] = 1
		var high_request := _request("store_station_commission", sequence)
		high_request["luck"] = 10
		var low := StockGeneratorScript.generate(_products, _stores, low_request)
		var high := StockGeneratorScript.generate(_products, _stores, high_request)
		if _snapshot_has_product(low, "product_commission_broken_radio"):
			low_count += 1
		if _snapshot_has_product(high, "product_commission_broken_radio"):
			high_count += 1
	_expect(high_count > low_count, "high Luck must produce more uncommon radio offers (%d <= %d)" % [high_count, low_count])


func _test_snapshot_and_migration() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var generated := StockGeneratorScript.generate(_products, _stores, _request("store_clinic_pharmacy_window"))
	_expect(bool(generated.get("ok", false)), "fixture stock must generate")
	if bool(generated.get("ok", false)):
		var encoded := JSON.stringify(generated["snapshot"])
		var parser := JSON.new()
		_expect_equal(parser.parse(encoded), OK, "snapshot JSON must parse")
		var decoded: Dictionary = JsonValidator.normalize_numbers(parser.data)
		_expect_equal(decoded, generated["snapshot"], "JSON round-trip must preserve snapshot meaning")
		_expect(bool(StockSnapshotScript.validate(decoded).get("ok", false)), "round-tripped snapshot must validate")
		var corrupted := decoded.duplicate(true)
		corrupted["offers"][0]["item_id"] = "missing_item"
		_expect(not bool(StockSnapshotScript.validate_catalog_references(corrupted, _products, _stores).get("ok", true)), "snapshot catalog references must reject a mismatched item")
	var file := FileAccess.open("res://game/commerce/data/fixtures/stock_snapshot_v0.json", FileAccess.READ)
	_expect(file != null, "previous stock fixture must exist")
	if file == null:
		return
	var fixture_parser := JSON.new()
	_expect_equal(fixture_parser.parse(file.get_as_text()), OK, "previous fixture must parse")
	var previous: Dictionary = JsonValidator.normalize_numbers(fixture_parser.data)
	var previous_before := previous.duplicate(true)
	var migration := StockSnapshotScript.migrate_serialized(previous)
	_expect(bool(migration.get("ok", false)), "v0 fixture must migrate: %s" % str(migration.get("errors", [])))
	if bool(migration.get("ok", false)):
		var migrated: Dictionary = migration["snapshot"]
		_expect_equal(migrated.get("schema_version"), 1, "migration must advance schema")
		_expect_equal(migrated.get("product_catalog_version"), 1, "migration must retain product catalog version")
		_expect_equal(migrated.get("store_catalog_version"), 1, "migration must add store catalog version")
		_expect_equal(migrated.get("revision"), 0, "migration must initialize optimistic revision")
		_expect(bool(StockSnapshotScript.validate(migrated).get("ok", false)), "migrated stock must validate")
	_expect_equal(previous, previous_before, "migration must not mutate previous fixture")


func _test_buy_transaction() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var generated := StockGeneratorScript.generate(_products, _stores, _request("store_market_food_row"))
	_expect(bool(generated.get("ok", false)), "market stock fixture must generate")
	if not bool(generated.get("ok", false)):
		return
	var snapshot: Dictionary = generated["snapshot"]
	var offer: Dictionary = snapshot["offers"][0]
	var run = RunStateScript.new(_build(), 920_001)
	run.set_money(10_000)
	var run_before := run.to_dict()
	var snapshot_before := snapshot.duplicate(true)
	var world := FakeWorldState.new({"store_market_food_row": snapshot})
	var prepared := Transaction.prepare_buy(run, world, "store_market_food_row", String(offer["offer_id"]), 1, "pockets", "buy:test:1", 0)
	_expect(bool(prepared.get("ok", false)), "purchase candidate must prepare: %s" % prepared.get("error", ""))
	if bool(prepared.get("ok", false)):
		var run_candidate: Variant = prepared["run_state_candidate"]
		var stock_candidate: Dictionary = prepared["stock_snapshot_candidate"]
		_expect_equal(run_candidate.money, 10_000 - int(offer["unit_price"]), "candidate must contain payment")
		_expect_equal(run_candidate.get_item_count(String(offer["item_id"])), 1, "candidate must contain purchased item")
		_expect_equal(stock_candidate.get("revision"), 1, "stock revision must advance once")
		_expect("buy:test:1" in Array(stock_candidate["applied_command_ids"]), "command must become idempotency key")
		_expect_equal(world.get_stock_snapshot("store_market_food_row"), snapshot_before, "world source must remain untouched")
		var world_candidate: Variant = prepared["world_state_candidate"]
		_expect_equal(world_candidate.get_stock_snapshot("store_market_food_row"), stock_candidate, "world candidate must own updated stock")
		var retry := Transaction.prepare_buy_snapshot(run_candidate, stock_candidate, String(offer["offer_id"]), 1, "pockets", "buy:test:1", 0)
		_expect(bool(retry.get("ok", false)) and bool(retry.get("already_applied", false)), "same command must be idempotent even with stale expected revision")
	var poor = RunStateScript.new(_build(), 920_002)
	var failed := Transaction.prepare_buy_snapshot(poor, snapshot, String(offer["offer_id"]), 1, "pockets", "buy:test:poor", 0)
	_expect_equal(failed.get("code"), "insufficient_funds", "insufficient funds must fail before mutation")
	var conflict := Transaction.prepare_buy_snapshot(run, snapshot, String(offer["offer_id"]), 1, "pockets", "buy:test:conflict", 7)
	_expect_equal(conflict.get("code"), "revision_conflict", "stale stock view must fail")
	var capacity := Transaction.prepare_buy_snapshot(run, snapshot, String(offer["offer_id"]), 1, "missing_container", "buy:test:capacity", 0)
	_expect(not bool(capacity.get("ok", true)), "missing target container must fail")
	_expect_equal(run.to_dict(), run_before, "all purchase preparation must leave live RunState untouched")
	_expect_equal(snapshot, snapshot_before, "all purchase preparation must leave live stock untouched")


func _test_sell_transaction() -> void:
	if _products.is_empty() or _stores.is_empty():
		return
	var generated := StockGeneratorScript.generate(_products, _stores, _request("store_station_commission"))
	_expect(bool(generated.get("ok", false)), "commission stock fixture must generate")
	if not bool(generated.get("ok", false)):
		return
	var snapshot: Dictionary = generated["snapshot"]
	var run = RunStateScript.new(_build(), 930_001)
	run.set_money(100)
	_expect(run.add_item("rusty_tool", 1, "hands"), "sale fixture item must fit inventory")
	var stack_id := ""
	for raw_stack: Variant in InventoryStateScript.all_stacks(run.inventory):
		if String(raw_stack.get("item_id", "")) == "rusty_tool" and not bool(raw_stack.get("external", false)):
			stack_id = String(raw_stack["stack_id"])
	var run_before := run.to_dict()
	var snapshot_before := snapshot.duplicate(true)
	var prepared := Transaction.prepare_sell_snapshot(run, snapshot, _products, _stores, "store_station_commission", stack_id, 1, {"year": 1980}, "sell:test:1", 0)
	_expect(bool(prepared.get("ok", false)), "sale candidate must prepare: %s" % prepared.get("error", ""))
	if bool(prepared.get("ok", false)):
		var candidate: Variant = prepared["run_state_candidate"]
		_expect(candidate.money > run.money, "sale candidate must receive payout")
		_expect_equal(candidate.get_item_count("rusty_tool"), 0, "sold item must leave candidate inventory")
		_expect_equal(Array(prepared["stock_snapshot_candidate"]["offers"]).size(), Array(snapshot["offers"]).size() + 1, "buyback must become concrete persisted stock")
		_expect_equal(prepared["stock_snapshot_candidate"].get("revision"), 1, "sale must advance stock revision")
	var market := StockGeneratorScript.generate(_products, _stores, _request("store_market_food_row"))
	if bool(market.get("ok", false)):
		var rejected := Transaction.prepare_sell_snapshot(run, market["snapshot"], _products, _stores, "store_market_food_row", stack_id, 1, {"year": 1980}, "sell:test:market", 0)
		_expect_equal(rejected.get("code"), "buyback_disabled", "ordinary market must not silently buy used tools")
	_expect_equal(run.to_dict(), run_before, "sale preparation must leave live RunState untouched")
	_expect_equal(snapshot, snapshot_before, "sale preparation must leave live stock untouched")


func _request(store_id: String, sequence: int = 0, facts: Dictionary = {}) -> Dictionary:
	return {
		"run_seed": "1980180001",
		"store_id": store_id,
		"restock_sequence": sequence,
		"generated_at": {"year": 1980, "month": 9, "day": 1, "minute_of_day": 480, "elapsed_minutes": 0},
		"chronology_version": 1,
		"world_facts": facts.duplicate(true),
		"luck": 5,
		"consumer_price_index_basis_points": 10_000,
		"category_supply_basis_points": {},
		"district_basis_points": 10_000,
		"relationship_basis_points": 10_000,
	}


func _trace_reason(result: Dictionary, product_id: String) -> String:
	for raw_trace: Variant in Array(result.get("trace", [])):
		if raw_trace is Dictionary and String(raw_trace.get("product_id", "")) == product_id:
			return String(raw_trace.get("reason", ""))
	return "missing_trace"


func _snapshot_has_product(result: Dictionary, product_id: String) -> bool:
	if not bool(result.get("ok", false)):
		return false
	for raw_offer: Variant in Array(Dictionary(result["snapshot"]).get("offers", [])):
		if raw_offer is Dictionary and String(raw_offer.get("product_id", "")) == product_id:
			return true
	return false


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current, message, str(expected), str(actual)])
