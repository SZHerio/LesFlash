class_name RecyclingService
extends RefCounted

## Pure recyclable appraisal plus one atomic sale boundary.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const WorldProcessProjectionScript := preload("res://game/world/world_process_projection.gd")
const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")


## What the yard pays today. The inspection process owns both the rate and
## whether the scales are running at all, so a week that pushed the inspection
## along is felt at the counter rather than described on a panel.
static func intake(session: Object) -> Dictionary:
	if session == null or not session.get("world_state") is WorldState:
		return {"accepting": true, "price_basis_points": PriceResolverScript.BASIS_POINTS, "stage_id": ""}
	var projection := WorldProcessProjectionScript.recycling_inspection(
		session.get("world_state")
	)
	if not bool(projection.get("ok", false)):
		return {"accepting": true, "price_basis_points": PriceResolverScript.BASIS_POINTS, "stage_id": ""}
	return {
		"accepting": bool(projection.get("recycling_accepting_materials", true)),
		"price_basis_points": int(projection.get("recycling_price_basis_points", PriceResolverScript.BASIS_POINTS)),
		"stage_id": String(projection.get("stage_id", "")),
		"stage_title": String(projection.get("stage_title", "")),
	}


static func offers(session: Object) -> Array[Dictionary]:
	if not _valid_target(session):
		return []
	var rate := intake(session)
	var result: Array[Dictionary] = []
	for raw_stack: Variant in InventoryStateScript.all_stacks(session.get("run_state").inventory):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = raw_stack
		if bool(stack.get("external", false)):
			continue
		if EquipmentRulesScript.is_equipped(
			session.get("run_state").inventory,
			String(stack.get("stack_id", ""))
		):
			continue
		var definition = ItemCatalogScript.definition(String(stack.get("item_id", "")))
		if "recyclable" not in definition.tags():
			continue
		var quantity := int(stack.get("quantity", 0))
		var unit_payout := _unit_payout(definition.base_value(), rate)
		result.append({
			"stack_id": String(stack.get("stack_id", "")),
			"item_id": definition.id(),
			"title": definition.title(),
			"quantity": quantity,
			"unit_payout": unit_payout,
			"total_payout": unit_payout * quantity,
			"condition": int(stack.get("condition", 100)),
			"accepting": bool(rate.get("accepting", true)),
			"price_basis_points": int(rate.get("price_basis_points", PriceResolverScript.BASIS_POINTS)),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("stack_id", "")) < String(right.get("stack_id", ""))
	)
	return result


static func sell(
	target: Object,
	stack_id: String,
	quantity: int,
	command_id: String,
	extra_time_effects: Array = []
) -> Dictionary:
	if not _valid_target(target):
		return _failure("invalid_session", "Игровая сессия не поддерживает сдачу вторсырья")
	if _location_id(target) != "recycling_point":
		return _failure("wrong_location", "Вторсырьё принимают только в пункте приёма")
	var rate := intake(target)
	if not bool(rate.get("accepting", true)):
		return _failure("intake_closed", "Сегодня пункт не принимает материалы")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Сдача должна иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить сдачу")
	var candidate_state: RunState = candidate.get("run_state")
	var stack := InventoryStateScript.find_stack(candidate_state.inventory, stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return _failure("missing_stack", "Предмет больше не находится у героя")
	if EquipmentRulesScript.is_equipped(candidate_state.inventory, stack_id):
		return _failure("item_equipped", "Сначала снимите эту вещь")
	var definition = ItemCatalogScript.definition(String(stack.get("item_id", "")))
	if "recyclable" not in definition.tags():
		return _failure("item_not_recyclable", "Пункт не принимает этот предмет")
	var available := int(stack.get("quantity", 0))
	var sold_quantity := available if quantity <= 0 else quantity
	if sold_quantity <= 0 or sold_quantity > available:
		return _failure("invalid_quantity", "Указано неверное количество")
	var payout := _unit_payout(definition.base_value(), rate) * sold_quantity
	var removal := InventoryStateScript.remove_stack(
		candidate_state.inventory,
		stack_id,
		sold_quantity
	)
	if not bool(removal.get("ok", false)):
		return removal
	candidate_state.inventory = Dictionary(removal["inventory"]).duplicate(true)
	if not candidate_state.change_money(payout):
		return _failure("money_failed", "Не удалось начислить ардены")
	var minutes := mini(6 + sold_quantity * 2, 30)
	var effects: Array = [{"type": "advance_time", "minutes": minutes, "reason": "Сдача вторсырья"}]
	effects.append_array(extra_time_effects.duplicate(true))
	var timed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "recycling_sale",
		"title": "Сдать вторсырьё",
		"journal_message": "Вторсырьё сдано в пункте приёма",
		"journal_payload": {
			"stack_id": stack_id,
			"item_id": definition.id(),
			"quantity": sold_quantity,
			"payout": payout,
		},
		"conditions": [],
		"effects": effects,
	})
	if not bool(timed.get("ok", false)):
		return timed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила сдачу вторсырья")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"receipt": {
			"item_id": definition.id(),
			"quantity": sold_quantity,
			"payout": payout,
			"duration_minutes": minutes,
		},
		"transaction": timed,
	}


static func _unit_payout(base_value: int, rate: Dictionary) -> int:
	var applied := PriceResolverScript.apply_basis_points(
		maxi(base_value, 1),
		int(rate.get("price_basis_points", PriceResolverScript.BASIS_POINTS))
	)
	return maxi(int(applied.get("value", base_value)), 1) if bool(applied.get("ok", false)) else maxi(base_value, 1)


static func _valid_target(value: Object) -> bool:
	if value == null:
		return false
	for method: String in ["clone", "replace_from", "validate"]:
		if not value.has_method(method):
			return false
	for field: String in ["run_state", "applied_command_ids"]:
		var found := false
		for raw_property: Variant in value.get_property_list():
			if raw_property is Dictionary and String(raw_property.get("name", "")) == field:
				found = true
				break
		if not found:
			return false
	return true


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		for raw_property: Variant in session.get_property_list():
			if raw_property is Dictionary and String(raw_property.get("name", "")) == field:
				return String(session.get(field))
	return ""


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
