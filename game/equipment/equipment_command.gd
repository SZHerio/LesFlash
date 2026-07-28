class_name EquipmentCommand
extends RefCounted

## Atomic equip/unequip boundary for the owning session.
##
## Putting a coat on takes minutes, so it is a confirmed decision like any
## other: the inventory move, the clock and the needs it costs commit together
## or not at all. A worn bag opens its own container in the same transaction,
## which is why the two cannot be separate commands.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const CheckResolverScript := preload("res://core/rules/check_resolver.gd")
const SessionTransaction := preload("res://game/session/session_command_transaction.gd")
const Rules := preload("res://game/equipment/equipment_rules.gd")

const UNEQUIP_MINUTES := 2
const UNEQUIP_TARGETS := ["backpack", "pockets", "hands"]


static func equip(target: Object, stack_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return _already_applied(command_id)
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("session_clone_failed", "Не удалось подготовить экипировку")
	var run_state: RunState = candidate.get("run_state")
	var stack := InventoryStateScript.find_stack(run_state.inventory, stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return _failure("missing_stack", "Предмет больше не находится у героя")
	if Rules.is_equipped(run_state.inventory, stack_id):
		return _failure("already_equipped", "Этот предмет уже надет")
	var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
	var action: Dictionary = definition.action("equip")
	if action.is_empty():
		return _failure("action_not_allowed", "Этот предмет нельзя надеть")
	var slot := String(definition.equip_slot())
	if slot.is_empty():
		return _failure("invalid_item_action", "У предмета не задан слот экипировки")
	var occupant := Rules.slot_occupant(run_state.inventory, slot)
	if not occupant.is_empty():
		var worn: Variant = ItemCatalogScript.definition(String(occupant.get("item_id", "")))
		return _failure("slot_taken", "Сначала снимите: %s" % String(worn.title()), {
			"slot_id": slot,
			"occupied_stack_id": String(occupant.get("stack_id", "")),
		})
	var requirements := CheckResolverScript.evaluate_all(
		run_state,
		Array(action.get("conditions", [])).duplicate(true),
		{"source": "equipment", "stack_id": stack_id, "slot_id": slot}
	)
	if not bool(requirements.get("allowed", false)):
		return _failure("equip_blocked", "Сейчас это снаряжение недоступно", {
			"reasons": Array(requirements.get("reasons", [])).duplicate(true),
		})

	var inventory := Rules.ensure_equipped_container(run_state.inventory)
	var moved := InventoryStateScript.move_stack(
		inventory,
		stack_id,
		Rules.EQUIPPED_CONTAINER_ID,
		1,
		run_state.get_characteristic("strength")
	)
	if not bool(moved.get("ok", false)):
		return moved
	inventory = Dictionary(moved["inventory"]).duplicate(true)
	var worn_stack_id := String(moved.get("stack_id", stack_id))
	var container_id := ""
	if slot == "bag":
		var opened := Rules.add_bag_container(
			inventory,
			worn_stack_id,
			definition.equip_container()
		)
		if not bool(opened.get("ok", false)):
			return opened
		inventory = Dictionary(opened["inventory"]).duplicate(true)
		container_id = String(opened["container_id"])
	run_state.inventory = inventory

	return _commit(
		target,
		candidate,
		command_id,
		{
			"source_id": "equipment_equip:%s" % String(definition.id()),
			"title": String(action.get("title", "Надеть")),
			"journal_message": "%s — %s" % [String(definition.title()), String(action.get("title", "надето"))],
			"minutes": maxi(int(action.get("duration_minutes", 0)), 1),
			"reason": "Экипировка",
			"effects": Array(action.get("effects", [])).duplicate(true),
			"payload": {
				"stack_id": worn_stack_id,
				"item_id": String(definition.id()),
				"slot_id": slot,
				"container_id": container_id,
				"equipped": true,
			},
		},
		{
			"stack_id": worn_stack_id,
			"slot_id": slot,
			"container_id": container_id,
			"equipped": true,
		}
	)


static func unequip(
	target: Object,
	stack_id: String,
	command_id: String,
	target_container_id: String = ""
) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return _already_applied(command_id)
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("session_clone_failed", "Не удалось подготовить снятие снаряжения")
	var run_state: RunState = candidate.get("run_state")
	if not Rules.is_equipped(run_state.inventory, stack_id):
		return _failure("not_equipped", "Этот предмет сейчас не надет")
	var stack := InventoryStateScript.find_stack(run_state.inventory, stack_id)
	var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
	var slot := String(definition.equip_slot())
	var inventory := run_state.inventory.duplicate(true)
	if slot == "bag":
		# The bag comes off with whatever is inside it, so an occupied bag is
		# refused instead of quietly dropping its contents on the ground.
		var closed := Rules.remove_bag_container(inventory, stack_id)
		if not bool(closed.get("ok", false)):
			return closed
		inventory = Dictionary(closed["inventory"]).duplicate(true)
	var targets: Array[String] = []
	if not target_container_id.is_empty():
		targets.append(target_container_id)
	targets.append_array(UNEQUIP_TARGETS)
	var moved: Dictionary = {}
	for container_id: String in targets:
		if Rules.is_managed_container_id(container_id):
			continue
		var attempt := InventoryStateScript.move_stack(
			inventory,
			stack_id,
			container_id,
			0,
			run_state.get_characteristic("strength")
		)
		if bool(attempt.get("ok", false)):
			moved = attempt
			break
	if moved.is_empty():
		return _failure("no_room_to_stow", "Снятую вещь некуда убрать: освободите место")
	run_state.inventory = Dictionary(moved["inventory"]).duplicate(true)

	return _commit(
		target,
		candidate,
		command_id,
		{
			"source_id": "equipment_unequip:%s" % String(definition.id()),
			"title": "Снять",
			"journal_message": "%s — снято" % String(definition.title()),
			"minutes": UNEQUIP_MINUTES,
			"reason": "Снятие снаряжения",
			"effects": [],
			"payload": {
				"stack_id": String(moved.get("stack_id", stack_id)),
				"item_id": String(definition.id()),
				"slot_id": slot,
				"equipped": false,
			},
		},
		{
			"stack_id": String(moved.get("stack_id", stack_id)),
			"slot_id": slot,
			"container_id": "",
			"equipped": false,
		}
	)


static func _commit(
	target: Object,
	candidate: Object,
	command_id: String,
	command: Dictionary,
	extra: Dictionary
) -> Dictionary:
	var effects: Array = [{
		"type": "advance_time",
		"minutes": int(command["minutes"]),
		"reason": String(command["reason"]),
	}]
	effects.append_array(Array(command.get("effects", [])))
	var transaction := SessionTransaction.execute(candidate, {
		"command_id": command_id,
		"source_id": String(command["source_id"]),
		"title": String(command["title"]),
		"journal_message": String(command["journal_message"]),
		"journal_payload": Dictionary(command["payload"]).duplicate(true),
		"conditions": [],
		"effects": effects,
	}, {"source": "equipment"})
	if not bool(transaction.get("ok", false)):
		return transaction
	var validation: Dictionary = candidate.call("validate")
	if not bool(validation.get("ok", false)):
		return _failure("session_validation_failed", "Снаряжение создало некорректную сессию", {
			"validation": validation,
		})
	var committed: Variant = target.call("replace_from", candidate)
	if committed is bool and not bool(committed):
		return _failure("session_commit_failed", "Сессия отклонила изменение снаряжения")
	var result := {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"command_id": command_id,
		"transaction": transaction,
		"modifiers": Rules.modifiers(target.get("run_state").inventory),
	}
	result.merge(extra, true)
	return result


static func _guard(target: Object, command_id: String) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	for method: String in ["clone", "replace_from", "validate"]:
		if not target.has_method(method):
			return _failure("invalid_session", "Сессия не реализует %s()" % method)
	if command_id.strip_edges().is_empty() or command_id.length() > 160:
		return _failure("invalid_command_id", "Снаряжение должно иметь стабильный command_id")
	return {}


static func _already_applied(command_id: String) -> Dictionary:
	return {
		"ok": true,
		"code": "already_applied",
		"error": "",
		"idempotent": true,
		"command_id": command_id,
	}


static func _failure(code: String, error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(details, true)
	return result
