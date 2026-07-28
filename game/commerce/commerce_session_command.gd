class_name CommerceSessionCommand
extends RefCounted

## Atomic bridge between deterministic commerce candidates and the owning
## session. Stock, money, inventory, time and needs commit together.

const StoreServiceScript := preload("res://game/commerce/store_service.gd")
const CommerceTransactionScript := preload("res://game/commerce/commerce_transaction.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const StoreCatalogScript := preload("res://game/commerce/store_catalog.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")

## Handing goods over the counter and haggling takes longer than paying for one
## thing off the shelf.
const SELL_MINUTES := 8


static func buy(
	target: Object,
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	command_id: String,
	expected_revision: int = -1,
	extra_time_effects: Array = []
) -> Dictionary:
	var target_error := _target_error(target)
	if not target_error.is_empty():
		return _failure("invalid_session", target_error)
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Покупка должна иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить покупку")
	var model := StoreServiceScript.preview(candidate, store_id)
	if not bool(model.get("ok", false)):
		return model
	if not bool(model.get("open", false)):
		return _failure("store_closed", String(Dictionary(model.get("availability", {})).get("reason", "Магазин закрыт")))
	var initial_snapshot: Dictionary = Dictionary(model["snapshot"]).duplicate(true)
	if expected_revision >= 0 and int(initial_snapshot.get("revision", -1)) != expected_revision:
		return _failure(
			"stock_conflict",
			"Ассортимент изменился. Проверьте товар ещё раз.",
			{"expected_revision": expected_revision, "actual_revision": int(initial_snapshot.get("revision", -1))}
		)
	if not bool(model.get("snapshot_persisted", false)):
		var seeded := _replace_stock(candidate, store_id, initial_snapshot, "stock_open_%s" % store_id)
		if not bool(seeded.get("ok", false)):
			return seeded
	var prepared := CommerceTransactionScript.prepare_buy(
		candidate.get("run_state"),
		candidate.get("world_state"),
		store_id,
		offer_id,
		quantity,
		target_container_id,
		command_id,
		int(initial_snapshot.get("revision", 0))
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	if not candidate.get("run_state").replace_from(prepared["run_state_candidate"]):
		return _failure("actor_candidate_failed", "Не удалось подготовить оплату и предмет")
	var stock_result := _replace_stock(
		candidate,
		store_id,
		Dictionary(prepared["stock_snapshot_candidate"]),
		"commerce_buy_%s" % store_id
	)
	if not bool(stock_result.get("ok", false)):
		return stock_result
	var effects: Array = [{"type": "advance_time", "minutes": 5, "reason": "Покупка"}]
	effects.append_array(extra_time_effects.duplicate(true))
	var receipt: Dictionary = Dictionary(prepared.get("receipt", {})).duplicate(true)
	var timed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "commerce_buy_%s" % store_id,
		"title": "Покупка",
		"journal_message": "Покупка в магазине",
		"journal_payload": {"store_id": store_id, "receipt": receipt},
		"conditions": [],
		"effects": effects,
	})
	if not bool(timed.get("ok", false)):
		return timed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила покупку")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"receipt": receipt,
		"transaction": timed,
		"store": StoreServiceScript.preview(target, store_id),
	}


static func sell(
	target: Object,
	store_id: String,
	stack_id: String,
	quantity: int,
	command_id: String,
	expected_revision: int = -1,
	extra_time_effects: Array = []
) -> Dictionary:
	var target_error := _target_error(target)
	if not target_error.is_empty():
		return _failure("invalid_session", target_error)
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Продажа должна иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить продажу")
	var model := StoreServiceScript.preview(candidate, store_id)
	if not bool(model.get("ok", false)):
		return model
	if not bool(model.get("open", false)):
		return _failure("store_closed", String(Dictionary(model.get("availability", {})).get("reason", "Магазин закрыт")))
	var initial_snapshot: Dictionary = Dictionary(model["snapshot"]).duplicate(true)
	if expected_revision >= 0 and int(initial_snapshot.get("revision", -1)) != expected_revision:
		return _failure(
			"stock_conflict",
			"Ассортимент изменился. Проверьте товар ещё раз.",
			{"expected_revision": expected_revision, "actual_revision": int(initial_snapshot.get("revision", -1))}
		)
	if not bool(model.get("snapshot_persisted", false)):
		var seeded := _replace_stock(candidate, store_id, initial_snapshot, "stock_open_%s" % store_id)
		if not bool(seeded.get("ok", false)):
			return seeded
	var catalogs := StoreServiceScript.load_catalogs()
	if not bool(catalogs.get("ok", false)):
		return catalogs
	var stack := InventoryStateScript.find_stack(candidate.get("run_state").inventory, stack_id)
	if stack.is_empty():
		return _failure("missing_stack", "Предмет больше не находится у героя")
	# Selling the coat off your own back is a separate decision from selling
	# what you carry, so worn gear is taken off first or not sold at all.
	if EquipmentRulesScript.is_equipped(candidate.get("run_state").inventory, stack_id):
		return _failure("item_equipped", "Сначала снимите эту вещь")
	var store_profile := StoreCatalogScript.profile_for_store(catalogs["stores"], store_id)
	var pricing_context := StoreServiceScript.pricing_context(
		candidate,
		Dictionary(store_profile.get("store", {}))
	)
	pricing_context["year"] = int(
		candidate.get("run_state").calendar.current_stamp().get("year", 1980)
	)
	pricing_context["quality"] = int(stack.get("condition", 100))
	var prepared := CommerceTransactionScript.prepare_sell(
		candidate.get("run_state"),
		candidate.get("world_state"),
		catalogs["products"],
		catalogs["stores"],
		store_id,
		stack_id,
		quantity,
		pricing_context,
		command_id,
		int(initial_snapshot.get("revision", 0))
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	if not candidate.get("run_state").replace_from(prepared["run_state_candidate"]):
		return _failure("actor_candidate_failed", "Не удалось подготовить выручку")
	var stock_result := _replace_stock(
		candidate,
		store_id,
		Dictionary(prepared["stock_snapshot_candidate"]),
		"commerce_sell_%s" % store_id
	)
	if not bool(stock_result.get("ok", false)):
		return stock_result
	var effects: Array = [{"type": "advance_time", "minutes": SELL_MINUTES, "reason": "Продажа"}]
	effects.append_array(extra_time_effects.duplicate(true))
	var receipt: Dictionary = Dictionary(prepared.get("receipt", {})).duplicate(true)
	var timed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "commerce_sell_%s" % store_id,
		"title": "Продажа",
		"journal_message": "Продажа в магазине",
		"journal_payload": {"store_id": store_id, "receipt": receipt},
		"conditions": [],
		"effects": effects,
	})
	if not bool(timed.get("ok", false)):
		return timed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила продажу")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"receipt": receipt,
		"transaction": timed,
		"store": StoreServiceScript.preview(target, store_id),
	}


static func _replace_stock(
	session: Object,
	store_id: String,
	snapshot: Dictionary,
	source_id: String
) -> Dictionary:
	var result := WorldMutationScript.apply(session.get("world_state"), {
		"schema_version": WorldMutationScript.SCHEMA_VERSION,
		"source_id": source_id,
		"at": session.get("run_state").calendar.current_stamp(),
		"operations": [{"type": "replace_stock", "store_id": store_id, "snapshot": snapshot}],
	})
	if not bool(result.get("ok", false)):
		return _failure("stock_commit_failed", String(result.get("error", "Не удалось обновить ассортимент")), {"cause": result})
	return {"ok": true}


static func _target_error(target: Object) -> String:
	if target == null:
		return "Игровая сессия отсутствует"
	for method: String in ["clone", "replace_from", "validate"]:
		if not target.has_method(method):
			return "Сессия не реализует %s()" % method
	for field: String in ["run_state", "world_state", "applied_command_ids"]:
		var found := false
		for raw_property: Variant in target.get_property_list():
			if raw_property is Dictionary and String(raw_property.get("name", "")) == field:
				found = true
				break
		if not found:
			return "В сессии отсутствует %s" % field
	return ""


static func _failure(code: String, error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(details, true)
	return result
