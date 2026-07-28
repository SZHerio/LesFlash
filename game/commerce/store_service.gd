class_name StoreService
extends RefCounted

## Pure shop read-model builder. A generated preview is deterministic and is
## persisted only together with the player's first confirmed purchase.

const ProductCatalogScript := preload("res://game/commerce/product_catalog.gd")
const StoreCatalogScript := preload("res://game/commerce/store_catalog.gd")
const StockGeneratorScript := preload("res://game/commerce/stock_generator.gd")
const WorldFactorsScript := preload("res://game/commerce/commerce_world_factors.gd")
const CommerceSellTransactionScript := preload("res://game/commerce/commerce_sell_transaction.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")


static func preview(session: Object, store_id: String) -> Dictionary:
	var contract := _contract(session)
	if not bool(contract.get("ok", false)):
		return contract
	var catalogs := load_catalogs()
	if not bool(catalogs.get("ok", false)):
		return catalogs
	var store_catalog: Dictionary = catalogs["stores"]
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return _failure("unknown_store", "Магазин не найден")
	var store: Dictionary = profile["store"]
	var current_location := _location_id(session)
	if current_location != String(store.get("location_id", "")):
		return _failure("wrong_location", "Этот магазин находится в другом месте")
	var stamp: Dictionary = session.get("run_state").calendar.current_stamp()
	var availability := availability_model(store_catalog, store, stamp)
	var factors := pricing_context(session, store)
	var snapshot_result := _snapshot_for(session, catalogs, store_id, stamp, factors)
	if not bool(snapshot_result.get("ok", false)):
		return snapshot_result
	var snapshot: Dictionary = snapshot_result["snapshot"]
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"store_id": store_id,
		"title": String(store.get("title", store_id)),
		"location_id": String(store.get("location_id", "")),
		"open": bool(availability.get("open", false)),
		"availability": availability,
		"snapshot": snapshot.duplicate(true),
		"snapshot_persisted": bool(snapshot_result.get("persisted", false)),
		"revision": int(snapshot.get("revision", 0)),
		"offers": Array(snapshot.get("offers", [])).duplicate(true),
		"money": int(session.get("run_state").money),
		"buyback": buyback_policy(store_catalog, store_id),
		"world_causes": Array(factors.get("causes", [])).duplicate(true),
	}


## One shared derivation for the shelf and for what the shop pays back, so a
## week that made bread dear cannot leave the buy-back price untouched.
static func pricing_context(session: Object, store: Dictionary) -> Dictionary:
	return WorldFactorsScript.build(
		session.get("world_state"),
		session.get("social_state") if _has_property(session, "social_state") else null,
		store
	)


static func buyback_policy(store_catalog: Dictionary, store_id: String) -> Dictionary:
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return {"enabled": false, "accepted_category_ids": [], "payout_basis_points": 0}
	var policy: Variant = Dictionary(profile["archetype"]).get("buyback_policy", {})
	return Dictionary(policy).duplicate(true) if policy is Dictionary else {}


## What this particular shop would take off the hero's hands, and for how much.
## Three shops with three profiles is the whole point: the same jar is money at
## the market, nothing at the pharmacy and scrap at the collection point.
static func sell_offers(session: Object, store_id: String) -> Dictionary:
	var contract := _contract(session)
	if not bool(contract.get("ok", false)):
		return contract
	var catalogs := load_catalogs()
	if not bool(catalogs.get("ok", false)):
		return catalogs
	var store_catalog: Dictionary = catalogs["stores"]
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return _failure("unknown_store", "Магазин не найден")
	var store: Dictionary = profile["store"]
	if _location_id(session) != String(store.get("location_id", "")):
		return _failure("wrong_location", "Этот магазин находится в другом месте")
	var policy := buyback_policy(store_catalog, store_id)
	if not bool(policy.get("enabled", false)):
		return {
			"ok": true,
			"code": "buyback_disabled",
			"error": "",
			"store_id": store_id,
			"buyback": policy,
			"offers": [],
			"message": "Здесь ничего не выкупают",
		}
	var run_state: RunState = session.get("run_state")
	var context := pricing_context(session, store)
	context["year"] = int(run_state.calendar.current_stamp().get("year", 1980))
	var offers: Array[Dictionary] = []
	for raw_stack: Variant in InventoryStateScript.all_stacks(run_state.inventory):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = raw_stack
		if bool(stack.get("external", false)):
			continue
		if EquipmentRulesScript.is_equipped(run_state.inventory, String(stack.get("stack_id", ""))):
			continue
		var quality := int(stack.get("condition", 100))
		var payout := CommerceSellTransactionScript.unit_payout(
			catalogs["products"],
			store_catalog,
			store_id,
			stack,
			quality,
			context
		)
		if not bool(payout.get("ok", false)):
			continue
		var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
		var quantity := int(stack.get("quantity", 0))
		offers.append({
			"stack_id": String(stack.get("stack_id", "")),
			"item_id": String(stack.get("item_id", "")),
			"title": String(definition.title()),
			"quantity": quantity,
			"condition": quality,
			"unit_payout": int(payout["unit_payout"]),
			"total_payout": int(payout["unit_payout"]) * quantity,
			"category_id": String(Dictionary(payout["product"]).get("category_id", "")),
		})
	offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("stack_id", "")) < String(right.get("stack_id", ""))
	)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"store_id": store_id,
		"buyback": policy,
		"offers": offers,
		"world_causes": Array(context.get("causes", [])).duplicate(true),
		"message": "" if not offers.is_empty() else "Сейчас у вас нет ничего для этой лавки",
	}


static func load_catalogs() -> Dictionary:
	var products := ProductCatalogScript.load_default()
	if not bool(products.get("ok", false)):
		return _failure("product_catalog_failed", "Каталог товаров недоступен", {
			"errors": Array(products.get("errors", [])).duplicate(true),
		})
	var stores := StoreCatalogScript.load_default()
	if not bool(stores.get("ok", false)):
		return _failure("store_catalog_failed", "Каталог магазинов недоступен", {
			"errors": Array(stores.get("errors", [])).duplicate(true),
		})
	return {
		"ok": true,
		"products": Dictionary(products["catalog"]).duplicate(true),
		"stores": Dictionary(stores["catalog"]).duplicate(true),
	}


static func availability_model(
	store_catalog: Dictionary,
	store: Dictionary,
	stamp: Dictionary
) -> Dictionary:
	var schedule_id := String(store.get("schedule_id", ""))
	var schedule: Dictionary = {}
	for raw_schedule: Variant in Array(store_catalog.get("schedules", [])):
		if raw_schedule is Dictionary and String(raw_schedule.get("schedule_id", "")) == schedule_id:
			schedule = Dictionary(raw_schedule)
			break
	if schedule.is_empty():
		return {"open": false, "reason": "Расписание не найдено", "day_of_week": 0}
	@warning_ignore("integer_division")
	var day_of_week := posmod(int(stamp.get("elapsed_minutes", 0)) / 1440, 7) + 1
	var minute := int(stamp.get("minute_of_day", 0))
	for raw_entry: Variant in Array(schedule.get("entries", [])):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if day_of_week not in Array(entry.get("days", [])):
			continue
		var opens := int(entry.get("opens_minute", 0))
		var closes := int(entry.get("closes_minute", 0))
		var is_open := minute >= opens and minute < closes
		return {
			"open": is_open,
			"reason": "Открыто" if is_open else "Сегодня магазин работает с %s до %s" % [_clock(opens), _clock(closes)],
			"day_of_week": day_of_week,
			"opens_minute": opens,
			"closes_minute": closes,
		}
	return {"open": false, "reason": "Сегодня магазин закрыт", "day_of_week": day_of_week}


static func _snapshot_for(
	session: Object,
	catalogs: Dictionary,
	store_id: String,
	stamp: Dictionary,
	factors: Dictionary
) -> Dictionary:
	var world_state: WorldState = session.get("world_state")
	var existing: Variant = world_state.stock_snapshots.get(store_id, {})
	if existing is Dictionary and not Dictionary(existing).is_empty():
		var snapshot: Dictionary = Dictionary(existing)
		if int(stamp.get("elapsed_minutes", 0)) < int(snapshot.get("next_restock_at", 0)):
			return {"ok": true, "snapshot": snapshot.duplicate(true), "persisted": true}
	var sequence := 0
	if existing is Dictionary and not Dictionary(existing).is_empty():
		sequence = int(Dictionary(existing).get("restock_sequence", -1)) + 1
	var run_state: RunState = session.get("run_state")
	var generated := StockGeneratorScript.generate(catalogs["products"], catalogs["stores"], {
		"run_seed": str(run_state.rng.seed),
		"store_id": store_id,
		"restock_sequence": sequence,
		"generated_at": stamp.duplicate(true),
		"chronology_version": 1,
		"luck": run_state.get_characteristic("luck"),
		"world_facts": world_state.facts.duplicate(true),
		"consumer_price_index_basis_points": int(factors.get(
			"consumer_price_index_basis_points",
			WorldFactorsScript.NEUTRAL
		)),
		"district_basis_points": int(factors.get(
			"district_basis_points",
			WorldFactorsScript.NEUTRAL
		)),
		"category_supply_basis_points": Dictionary(
			factors.get("category_supply_basis_points", {})
		).duplicate(true),
		"relationship_basis_points": int(factors.get(
			"relationship_basis_points",
			WorldFactorsScript.NEUTRAL
		)),
		"supply_offer_delta": int(factors.get("supply_offer_delta", 0)),
	})
	if not bool(generated.get("ok", false)):
		return _failure("stock_generation_failed", "Не удалось подготовить ассортимент", {
			"errors": Array(generated.get("errors", [])).duplicate(true),
		})
	return {"ok": true, "snapshot": Dictionary(generated["snapshot"]).duplicate(true), "persisted": false}


static func _contract(session: Object) -> Dictionary:
	if session == null:
		return _failure("missing_session", "Игровая сессия отсутствует")
	for field: String in ["run_state", "world_state"]:
		if not _has_property(session, field) or session.get(field) == null:
			return _failure("invalid_session", "В сессии отсутствует %s" % field)
	return {"ok": true}


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		if _has_property(session, field):
			return String(session.get(field))
	return ""


static func _has_property(value: Object, name: String) -> bool:
	for raw_property: Variant in value.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == name:
			return true
	return false


static func _clock(minute: int) -> String:
	return "%02d:%02d" % [minute / 60, minute % 60]


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(extra, true)
	return result
