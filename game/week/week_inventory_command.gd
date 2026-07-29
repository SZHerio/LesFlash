class_name WeekInventoryCommand
extends RefCounted

## Timed inventory decisions at the full-session atomic boundary.
##
## Inventory mutations are prepared on an outer session clone. Time, survival
## needs and authored actor effects then pass through SessionCommandTransaction;
## only the completely validated aggregate is published to the live session.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const CheckResolverScript := preload("res://core/rules/check_resolver.gd")
const SessionTransaction := preload("res://game/session/session_command_transaction.gd")
const RecyclingServiceScript := preload("res://game/recycling/recycling_service.gd")

const TIMED_ACTIONS := ["use", "disassemble", "craft"]


static func execute(
	target: Object,
	stack_id: String,
	action_id: String,
	command_id: String,
	quantity: int = 0
) -> Dictionary:
	var target_error := _validate_target(target)
	if not target_error.is_empty():
		return _failure("invalid_session", target_error)
	var normalized_command_id := command_id.strip_edges()
	if normalized_command_id.is_empty() or normalized_command_id.length() > 160:
		return _failure("invalid_command_id", "Действие с предметом должно иметь стабильный command_id")
	if Dictionary(target.get("applied_command_ids")).has(normalized_command_id):
		return {
			"ok": true,
			"code": "already_applied",
			"error": "",
			"idempotent": true,
			"command_id": normalized_command_id,
		}
	if action_id == "sell":
		return RecyclingServiceScript.sell(
			target,
			stack_id,
			quantity,
			normalized_command_id
		)
	if action_id not in TIMED_ACTIONS:
		return _failure("unsupported_inventory_action", "Это действие не относится к временным решениям инвентаря")

	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("session_clone_failed", "Не удалось подготовить действие с предметом")
	var run_state: RunState = candidate.get("run_state")
	var stack := InventoryStateScript.find_stack(run_state.inventory, stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return _failure("missing_stack", "Предмет больше не находится у героя")
	var item_id := String(stack.get("item_id", ""))
	var definition = ItemCatalogScript.definition(item_id)
	var action: Dictionary = definition.action(action_id)
	if action.is_empty():
		return _failure("action_not_allowed", "С этим предметом нельзя выполнить выбранное действие")
	var duration := int(action.get("duration_minutes", 0))
	if duration <= 0:
		return _failure("untimed_item_action", "Это действие не должно продвигать игровое время")
	if _contains_time_effect(Array(action.get("effects", []))):
		return _failure("invalid_item_action", "Время предметного действия задано дважды")
	var requirements := CheckResolverScript.evaluate_all(
		run_state,
		Array(action.get("conditions", [])).duplicate(true),
		{"source": "inventory", "stack_id": stack_id, "item_id": item_id}
	)
	if not bool(requirements.get("allowed", false)):
		return _failure("item_action_blocked", "Сейчас это действие недоступно", {
			"reasons": Array(requirements.get("reasons", [])).duplicate(true),
		})

	var inventory_result := _prepare_inventory(run_state, stack, action, action_id)
	if not bool(inventory_result.get("ok", false)):
		return inventory_result
	var effects: Array = [{
		"type": "advance_time",
		"minutes": duration,
		"reason": "%s: %s" % [definition.title(), String(action.get("title", action_id))],
	}]
	effects.append_array(Array(action.get("effects", [])).duplicate(true))
	var transaction := SessionTransaction.execute(candidate, {
		"command_id": normalized_command_id,
		"source_id": "item:%s:%s" % [item_id, action_id],
		"title": String(action.get("title", action_id)),
		"journal_message": "%s — %s" % [definition.title(), String(action.get("title", action_id))],
		"journal_payload": {
			"stack_id": stack_id,
			"item_id": item_id,
			"item_action": action_id,
			"consumed": bool(inventory_result.get("consumed", false)),
			"outputs": Array(inventory_result.get("outputs", [])).duplicate(true),
		},
		"conditions": [],
		"effects": effects,
	}, {"source": "inventory", "stack_id": stack_id, "item_id": item_id})
	if not bool(transaction.get("ok", false)):
		return transaction
	var validation: Dictionary = candidate.call("validate")
	if not bool(validation.get("ok", false)):
		return _failure("session_validation_failed", "Действие создало некорректную игровую сессию", {
			"validation": validation,
		})
	var committed: Variant = target.call("replace_from", candidate)
	if committed is bool and not bool(committed):
		return _failure("session_commit_failed", "Игровая сессия отклонила действие с предметом")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"command_id": normalized_command_id,
		"stack_id": stack_id,
		"item_id": item_id,
		"action_id": action_id,
		"consumed": bool(inventory_result.get("consumed", false)),
		"outputs": Array(inventory_result.get("outputs", [])).duplicate(true),
		"transaction": transaction,
		"inventory": target.get("run_state").inventory.duplicate(true),
	}


static func _prepare_inventory(
	run_state: RunState,
	stack: Dictionary,
	action: Dictionary,
	action_id: String
) -> Dictionary:
	var inventory := run_state.inventory.duplicate(true)
	var consumes := bool(action.get("consumes", action_id in TIMED_ACTIONS))
	if consumes:
		var removal := InventoryStateScript.remove_stack(
			inventory,
			String(stack.get("stack_id", "")),
			1
		)
		if not bool(removal.get("ok", false)):
			return removal
		inventory = Dictionary(removal["inventory"]).duplicate(true)
	var outputs: Array[Dictionary] = []
	for raw_output: Variant in Array(action.get("outputs", [])):
		if not raw_output is Dictionary:
			return _failure("invalid_item_action", "Результат разбора предмета повреждён")
		var output: Dictionary = raw_output
		var addition := InventoryStateScript.add_item(
			inventory,
			String(output.get("item_id", "")),
			int(output.get("quantity", 1)),
			int(output.get("condition", 100)),
			String(stack.get("container_id", "pockets")),
			run_state.get_characteristic("strength")
		)
		if not bool(addition.get("ok", false)):
			return addition
		inventory = Dictionary(addition["inventory"]).duplicate(true)
		outputs.append({
			"item_id": String(output.get("item_id", "")),
			"quantity": int(output.get("quantity", 1)),
			"condition": int(output.get("condition", 100)),
			"stack_ids": Array(addition.get("stack_ids", [])).duplicate(),
		})
	run_state.inventory = inventory
	return {"ok": true, "consumed": consumes, "outputs": outputs}


static func _contains_time_effect(effects: Array) -> bool:
	for raw_effect: Variant in effects:
		if raw_effect is Dictionary and String(raw_effect.get("type", raw_effect.get("kind", ""))) == "advance_time":
			return true
	return false


static func _validate_target(target: Object) -> String:
	if target == null:
		return "Игровая сессия отсутствует"
	for method: String in ["clone", "replace_from", "validate"]:
		if not target.has_method(method):
			return "Игровая сессия не реализует %s()" % method
	var properties: Dictionary = {}
	for raw_property: Variant in target.get_property_list():
		if raw_property is Dictionary:
			properties[String(raw_property.get("name", ""))] = true
	for field: String in ["run_state", "applied_command_ids"]:
		if not properties.has(field):
			return "Игровая сессия не содержит %s" % field
	if not target.get("run_state") is RunState or not target.get("applied_command_ids") is Dictionary:
		return "Игровая сессия содержит неверные доменные данные"
	return ""


static func _failure(code: String, error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(details, true)
	return result
