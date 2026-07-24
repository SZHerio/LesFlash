class_name SearchLootTransaction
extends RefCounted

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")


static func materialize_object(
	run_state: RunState,
	snapshot: Dictionary,
	object: Dictionary,
	activity_id: String
) -> Dictionary:
	var container_id := ground_container_id(activity_id)
	run_state.inventory = InventoryStateScript.ensure_external_container(
		run_state.inventory,
		container_id,
		"На земле",
		"search_ground"
	)
	var result_snapshot := snapshot.duplicate(true)
	var ground_items: Array = Array(result_snapshot.get("ground_items", [])).duplicate(true)
	var updated_object := object.duplicate(true)
	var contents: Array = Array(updated_object.get("contents", [])).duplicate(true)
	var materialized: Array = []
	for index in range(contents.size()):
		if not contents[index] is Dictionary:
			return _failure("invalid_loot", "Содержимое объекта повреждено.")
		var loot: Dictionary = contents[index].duplicate(true)
		if bool(loot.get("claimed", false)):
			continue
		var metadata := {
			"source_kind": "search",
			"source_id": activity_id,
			"object_id": String(object.get("id", "")),
			"loot_id": String(loot.get("loot_id", "")),
		}
		var addition := InventoryStateScript.add_item(
			run_state.inventory,
			String(loot.get("item_id", "")),
			int(loot.get("quantity", 0)),
			int(loot.get("condition", 100)),
			container_id,
			run_state.get_characteristic("strength"),
			true,
			metadata
		)
		if not bool(addition.get("ok", false)):
			return addition
		run_state.inventory = addition["inventory"]
		var stack_ids: Array = Array(addition.get("stack_ids", []))
		for stack_index in range(stack_ids.size()):
			var stack_id := String(stack_ids[stack_index])
			var stack := InventoryStateScript.find_stack(run_state.inventory, stack_id)
			if stack.is_empty():
				return _failure(
					"loot_stack_missing",
					"Созданная находка отсутствует во внешнем контейнере."
				)
			var ground_ref := _ground_reference(
				stack,
				loot,
				object,
				stack_index
			)
			ground_items.append(ground_ref)
			materialized.append(ground_ref.duplicate(true))
		loot["claimed"] = true
		contents[index] = loot
	updated_object["contents"] = contents
	result_snapshot["ground_items"] = ground_items
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": result_snapshot,
		"object": updated_object,
		"ground_items": materialized,
	}


static func pick_up(
	run_state: RunState,
	snapshot: Dictionary,
	stack_id: String,
	target_container_id: String
) -> Dictionary:
	var ground_ref := find_ground(snapshot, stack_id)
	if ground_ref.is_empty():
		return _failure("missing_ground_item", "Находка больше не лежит в зоне.")
	var inventory_result := InventoryTransaction.pick_up(
		run_state,
		stack_id,
		target_container_id
	)
	if not bool(inventory_result.get("ok", false)):
		return inventory_result
	var result_snapshot := remove_ground(snapshot, stack_id)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": result_snapshot,
		"ground_item": ground_ref,
		"inventory_result": inventory_result,
	}


static func replace(
	run_state: RunState,
	snapshot: Dictionary,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	var incoming_ref := find_ground(snapshot, incoming_stack_id)
	if incoming_ref.is_empty():
		return _failure("missing_ground_item", "Находка больше не лежит в зоне.")
	var inventory_result := InventoryTransaction.replace(
		run_state,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	if not bool(inventory_result.get("ok", false)):
		return inventory_result
	var displaced := InventoryStateScript.find_stack(
		run_state.inventory,
		displaced_stack_id
	)
	if displaced.is_empty() or not bool(displaced.get("external", false)):
		return _failure(
			"replacement_ground_missing",
			"Вытесненный предмет не оказался на земле."
		)
	var result_snapshot := remove_ground(snapshot, incoming_stack_id)
	var ground_items: Array = Array(result_snapshot.get("ground_items", [])).duplicate(true)
	ground_items.append({
		"ground_id": "replacement:%s" % displaced_stack_id,
		"stack_id": displaced_stack_id,
		"item_id": String(displaced.get("item_id", "")),
		"quantity": int(displaced.get("quantity", 1)),
		"condition": int(displaced.get("condition", 100)),
		"position": Array(incoming_ref.get("position", [0, 0])).duplicate(),
		"object_id": String(incoming_ref.get("object_id", "")),
		"metadata": Dictionary(displaced.get("metadata", {})).duplicate(true),
	})
	result_snapshot["ground_items"] = ground_items
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": result_snapshot,
		"incoming": incoming_ref,
		"displaced": displaced.duplicate(true),
		"inventory_result": inventory_result,
	}


static func find_ground(snapshot: Dictionary, stack_id: String) -> Dictionary:
	for raw_ref: Variant in Array(snapshot.get("ground_items", [])):
		if raw_ref is Dictionary and (
			String(raw_ref.get("stack_id", "")) == stack_id
			or String(raw_ref.get("ground_id", "")) == stack_id
		):
			return Dictionary(raw_ref).duplicate(true)
	return {}


static func remove_ground(snapshot: Dictionary, stack_id: String) -> Dictionary:
	var result := snapshot.duplicate(true)
	var filtered: Array = []
	for raw_ref: Variant in Array(result.get("ground_items", [])):
		if not raw_ref is Dictionary:
			continue
		if (
			String(raw_ref.get("stack_id", "")) == stack_id
			or String(raw_ref.get("ground_id", "")) == stack_id
		):
			continue
		filtered.append(Dictionary(raw_ref).duplicate(true))
	result["ground_items"] = filtered
	return result


static func ground_container_id(activity_id: String) -> String:
	return "search:%s:ground" % activity_id


static func _ground_reference(
	stack: Dictionary,
	loot: Dictionary,
	object: Dictionary,
	stack_index: int
) -> Dictionary:
	var loot_id := String(loot.get("loot_id", "loot"))
	return {
		"ground_id": (
			loot_id
			if stack_index == 0
			else "%s:%02d" % [loot_id, stack_index + 1]
		),
		"stack_id": String(stack.get("stack_id", "")),
		"item_id": String(stack.get("item_id", "")),
		"quantity": int(stack.get("quantity", 1)),
		"condition": int(stack.get("condition", 100)),
		"position": Array(object.get("position", [0, 0])).duplicate(),
		"object_id": String(object.get("id", "")),
		"metadata": Dictionary(stack.get("metadata", {})).duplicate(true),
	}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
