class_name InventoryTransaction
extends RefCounted

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")


static func move(
	run_state: RunState,
	stack_id: String,
	target_container_id: String,
	quantity: int = 0
) -> Dictionary:
	return _commit_inventory_result(
		run_state,
		InventoryStateScript.move_stack(
			run_state.inventory,
			stack_id,
			target_container_id,
			quantity,
			run_state.get_characteristic("strength")
		),
		"inventory_move",
		{"stack_id": stack_id, "target_container_id": target_container_id, "quantity": quantity}
	)


static func pick_up(
	run_state: RunState,
	external_stack_id: String,
	target_container_id: String = "pockets",
	quantity: int = 0
) -> Dictionary:
	var stack := InventoryStateScript.find_stack(run_state.inventory, external_stack_id)
	if stack.is_empty() or not bool(stack.get("external", false)):
		return _failure("missing_ground_item", "Находка больше не лежит здесь.")
	return move(run_state, external_stack_id, target_container_id, quantity)


static func replace(
	run_state: RunState,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	return _commit_inventory_result(
		run_state,
		InventoryStateScript.replace_stack(
			run_state.inventory,
			incoming_stack_id,
			displaced_stack_id,
			target_container_id,
			run_state.get_characteristic("strength")
		),
		"inventory_replace",
		{
			"stack_id": incoming_stack_id,
			"displaced_stack_id": displaced_stack_id,
			"target_container_id": target_container_id,
		}
	)


static func drop(
	run_state: RunState,
	stack_id: String,
location_id: String,
	quantity: int = 0
) -> Dictionary:
	var ground_id := "ground:%s" % location_id
	var candidate := run_state.clone()
	if candidate == null:
		return _failure("invalid_run_state", "Состояние попытки повреждено.")
	candidate.inventory = InventoryStateScript.ensure_external_container(
		candidate.inventory,
		ground_id,
		"Оставлено здесь",
		"ground"
	)
	var move_result := InventoryStateScript.move_stack(
		candidate.inventory,
		stack_id,
		ground_id,
		quantity,
		candidate.get_characteristic("strength")
	)
	if not bool(move_result.get("ok", false)):
		return move_result
	candidate.inventory = move_result["inventory"]
	return _commit_candidate(candidate, run_state, "inventory_drop", {
		"stack_id": stack_id,
		"location_id": location_id,
		"quantity": quantity,
	})


static func use(run_state: RunState, stack_id: String) -> Dictionary:
	return _perform_item_action(run_state, stack_id, "use")


static func disassemble(run_state: RunState, stack_id: String) -> Dictionary:
	return _perform_item_action(run_state, stack_id, "disassemble")


static func select(run_state: RunState, stack_id: String) -> Dictionary:
	var candidate := run_state.clone()
	if candidate == null:
		return _failure("invalid_run_state", "Состояние попытки повреждено.")
	candidate.inventory = InventoryStateScript.set_selected_stack(candidate.inventory, stack_id)
	if String(candidate.inventory.get("selected_stack_id", "")) != stack_id:
		return _failure("missing_stack", "Предмет больше не найден.")
	if not run_state.replace_from(candidate):
		return _failure("commit_failed", "Не удалось выбрать предмет.")
	return _success({"stack_id": stack_id})


static func _perform_item_action(
	run_state: RunState,
	stack_id: String,
	action_id: String
) -> Dictionary:
	var stack: Dictionary = InventoryStateScript.find_stack(run_state.inventory, stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return _failure("missing_stack", "Предмет больше не находится у героя.")
	var item_id := String(stack.get("item_id", ""))
	var definition: Variant = ItemCatalogScript.definition(item_id)
	var action: Dictionary = definition.action(action_id)
	if action.is_empty():
		return _failure("action_not_allowed", "С этим предметом нельзя выполнить выбранное действие.")
	var requirements := CheckResolver.evaluate_all(
		run_state,
		Array(action.get("conditions", [])).duplicate(true),
		{"source": "inventory", "stack_id": stack_id, "item_id": item_id}
	)
	if not bool(requirements.get("allowed", false)):
		return {
			"ok": false,
			"code": "item_action_blocked",
			"error": "Сейчас это действие недоступно.",
			"reasons": Array(requirements.get("reasons", [])).duplicate(true),
		}
	var candidate := run_state.clone()
	if candidate == null:
		return _failure("invalid_run_state", "Состояние попытки повреждено.")
	var consumes := bool(action.get("consumes", action_id in ["use", "disassemble"]))
	if consumes:
		var removal := InventoryStateScript.remove_stack(candidate.inventory, stack_id, 1)
		if not bool(removal.get("ok", false)):
			return removal
		candidate.inventory = removal["inventory"]
	for output_value in Array(action.get("outputs", [])):
		if not output_value is Dictionary:
			return _failure("invalid_item_action", "Результат разбора предмета повреждён.")
		var output: Dictionary = output_value
		var addition := InventoryStateScript.add_item(
			candidate.inventory,
			String(output.get("item_id", "")),
			int(output.get("quantity", 1)),
			int(output.get("condition", 100)),
			String(stack.get("container_id", "pockets")),
			candidate.get_characteristic("strength")
		)
		if not bool(addition.get("ok", false)):
			return addition
		candidate.inventory = addition["inventory"]
	var effects: Array = Array(action.get("effects", [])).duplicate(true)
	var duration := int(action.get("duration_minutes", 0))
	if duration > 0:
		effects.push_front({
			"type": "advance_time",
			"minutes": duration,
			"reason": "%s: %s" % [definition.title(), String(action.get("title", action_id))],
		})
	if not effects.is_empty():
		var transaction := ActionTransaction.execute(candidate, {
			"id": "item:%s:%s" % [item_id, action_id],
			"title": String(action.get("title", action_id)),
			"conditions": [],
			"effects": effects,
			"journal_message": "%s — %s" % [definition.title(), String(action.get("title", action_id))],
			"journal_payload": {"item_id": item_id, "item_action": action_id},
		}, {"source": "inventory", "stack_id": stack_id})
		if not transaction.success:
			return {
				"ok": false,
				"code": transaction.code,
				"error": transaction.message,
				"reasons": transaction.reasons,
			}
	return _commit_candidate(candidate, run_state, "inventory_%s" % action_id, {
		"stack_id": stack_id,
		"item_id": item_id,
		"action_id": action_id,
		"consumes": consumes,
	})


static func _commit_inventory_result(
	run_state: RunState,
	inventory_result: Dictionary,
	journal_type: String,
	payload: Dictionary
) -> Dictionary:
	if not bool(inventory_result.get("ok", false)):
		return inventory_result
	var candidate := run_state.clone()
	if candidate == null:
		return _failure("invalid_run_state", "Состояние попытки повреждено.")
	candidate.inventory = Dictionary(inventory_result["inventory"]).duplicate(true)
	return _commit_candidate(candidate, run_state, journal_type, payload)


static func _commit_candidate(
	candidate: RunState,
	run_state: RunState,
	journal_type: String,
	payload: Dictionary
) -> Dictionary:
	if not candidate.add_journal_entry("inventory", journal_type, payload):
		return _failure("journal_failed", "Не удалось записать изменение инвентаря.")
	var validation := candidate.validate()
	if not bool(validation.get("ok", false)):
		return _failure("inventory_validation_failed", "Изменение создало некорректный инвентарь.", {
			"validation": validation,
		})
	if not run_state.replace_from(candidate):
		return _failure("commit_failed", "Не удалось применить изменение инвентаря.")
	return _success({
		"transaction": {
			"success": true,
			"code": "ok",
			"changes": [{
				"effect_type": journal_type,
				"target_type": "inventory",
				"target_id": String(payload.get("item_id", payload.get("stack_id", ""))),
				"after": payload.duplicate(true),
			}],
		},
		"inventory": run_state.inventory.duplicate(true),
	})


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(extra, true)
	return result


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
