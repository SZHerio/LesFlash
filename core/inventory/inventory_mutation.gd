extends RefCounted

const Schema := preload("res://core/inventory/inventory_schema.gd")
const Query := preload("res://core/inventory/inventory_query.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const Metadata := preload("res://core/inventory/inventory_metadata.gd")
const StackWriter := preload("res://core/inventory/inventory_stack_writer.gd")


static func add_item(
	inventory: Dictionary,
	item_id: String,
	quantity: int,
	condition: int,
	preferred_container: String,
	strength: int,
	allow_overflow: bool,
	metadata: Dictionary = {}
) -> Dictionary:
	if item_id.is_empty() or quantity <= 0 or condition < 0 or condition > 100:
		return _failure("invalid_item", "Некорректный предмет или количество.")
	var metadata_validation := Metadata.validate(metadata)
	if not bool(metadata_validation.get("ok", false)):
		return _failure(
			"invalid_metadata",
			"Метаданные предмета не могут быть сохранены.",
			{"validation": metadata_validation}
		)
	var normalized_metadata: Dictionary = Metadata.normalize(metadata)
	var candidate := inventory.duplicate(true)
	var targets: Array[String] = []
	if not preferred_container.is_empty():
		targets.append(preferred_container)
	else:
		targets.assign(["pockets", "backpack", "hands"])
	var definition: Variant = ItemCatalog.definition(item_id)
	for target_id in targets:
		var located := Query.locate_container(candidate, target_id)
		if located.is_empty() or not bool(Dictionary(located["container"]).get("active", true)):
			continue
		if not allow_overflow and not Query.can_add(candidate, target_id, definition, quantity, strength):
			continue
		var addition := StackWriter.add_to_container(
			candidate,
			target_id,
			item_id,
			quantity,
			condition,
			"",
			normalized_metadata
		)
		if bool(addition.get("ok", false)):
			return addition
	var conflict_target := preferred_container if not preferred_container.is_empty() else "pockets"
	return _failure("capacity_conflict", "Для находки не хватает массы или объёма.", {
		"incoming": {
			"item_id": item_id,
			"title": definition.title(),
			"quantity": quantity,
			"mass_grams": definition.mass_grams() * quantity,
			"volume_ml": definition.volume_ml() * quantity,
			"metadata": normalized_metadata.duplicate(true),
		},
		"container_id": conflict_target,
		"capacity": Query.capacity(candidate, conflict_target, strength),
		"comparison": Query.comparison(candidate, conflict_target),
		"recoveries": ["choose_other_container", "replace", "leave_at_source"],
	})


static func remove_item(inventory: Dictionary, item_id: String, quantity: int) -> Dictionary:
	if item_id.is_empty() or quantity <= 0 or Query.item_count(inventory, item_id) < quantity:
		return _failure("insufficient_item", "Недостаточно предметов.")
	var candidate := inventory.duplicate(true)
	var remaining := quantity
	for group_name in ["containers", "external_containers"]:
		var group: Dictionary = candidate.get(group_name, {})
		var container_ids: Array = group.keys()
		container_ids.sort()
		for container_id in container_ids:
			var container: Dictionary = group[container_id]
			var stacks: Array = Array(container.get("stacks", [])).duplicate(true)
			for index in range(stacks.size() - 1, -1, -1):
				var stack: Dictionary = stacks[index]
				if String(stack.get("item_id", "")) != item_id:
					continue
				var taken := mini(remaining, int(stack.get("quantity", 0)))
				var left := int(stack.get("quantity", 0)) - taken
				remaining -= taken
				if left <= 0:
					stacks.remove_at(index)
				else:
					stack["quantity"] = left
					stacks[index] = stack
				if remaining == 0:
					break
			container["stacks"] = stacks
			group[container_id] = container
			if remaining == 0:
				break
		candidate[group_name] = group
		if remaining == 0:
			break
	_clear_missing_selection(candidate)
	return _success({"inventory": candidate})


static func remove_stack(
	inventory: Dictionary,
	stack_id: String,
	quantity: int
) -> Dictionary:
	if stack_id.is_empty() or quantity <= 0:
		return _failure("invalid_stack", "Некорректная стопка или количество.")
	return _remove_stack_quantity(inventory, stack_id, quantity)


static func move_stack(
	inventory: Dictionary,
	stack_id: String,
	target_container_id: String,
	quantity: int,
	strength: int
) -> Dictionary:
	var source := Query.find_stack(inventory, stack_id)
	if source.is_empty():
		return _failure("missing_stack", "Предмет больше не находится в этом месте.")
	var available := int(source.get("quantity", 0))
	var moved := available if quantity <= 0 else quantity
	if moved < 1 or moved > available:
		return _failure("invalid_quantity", "Некорректное количество для перемещения.")
	if String(source.get("container_id", "")) == target_container_id:
		return _success({"inventory": inventory.duplicate(true), "stack_id": stack_id})
	var definition: Variant = ItemCatalog.definition(String(source.get("item_id", "")))
	if not Query.can_add(inventory, target_container_id, definition, moved, strength):
		return _failure("capacity_conflict", "В выбранном месте не хватает массы или объёма.", {
			"incoming": source.duplicate(true),
			"container_id": target_container_id,
			"capacity": Query.capacity(inventory, target_container_id, strength),
			"comparison": Query.comparison(inventory, target_container_id),
			"recoveries": ["choose_other_container", "replace", "leave_at_source"],
		})
	var removal := _remove_stack_quantity(inventory, stack_id, moved)
	if not bool(removal.get("ok", false)):
		return removal
	return StackWriter.add_to_container(
		removal["inventory"],
		target_container_id,
		String(source.get("item_id", "")),
		moved,
		int(source.get("condition", 100)),
		stack_id if moved == available else "",
		Dictionary(source.get("metadata", {})).duplicate(true),
		String(source.get("quantity_encoding", ""))
	)


static func ensure_external_container(
	inventory: Dictionary,
	container_id: String,
	title: String,
	kind: String
) -> Dictionary:
	var candidate := inventory.duplicate(true)
	var external: Dictionary = candidate.get("external_containers", {})
	if not external.has(container_id):
		external[container_id] = Schema.make_container(container_id, title, kind, true, -1, 0, -1)
	candidate["external_containers"] = external
	return candidate


static func set_selected_stack(inventory: Dictionary, stack_id: String) -> Dictionary:
	if not stack_id.is_empty() and Query.find_stack(inventory, stack_id).is_empty():
		return inventory.duplicate(true)
	var candidate := inventory.duplicate(true)
	candidate["selected_stack_id"] = stack_id
	return candidate


static func _remove_stack_quantity(
	inventory: Dictionary,
	stack_id: String,
	quantity: int
) -> Dictionary:
	var candidate := inventory.duplicate(true)
	for group_name in ["containers", "external_containers"]:
		var group: Dictionary = candidate.get(group_name, {})
		for container_id in group:
			var container: Dictionary = group[container_id]
			var stacks: Array = Array(container.get("stacks", [])).duplicate(true)
			for index in range(stacks.size()):
				var stack: Dictionary = stacks[index]
				if String(stack.get("stack_id", "")) != stack_id:
					continue
				var remaining := int(stack.get("quantity", 0)) - quantity
				if remaining < 0:
					return _failure("invalid_quantity", "Недостаточно предметов в стопке.")
				if remaining == 0:
					stacks.remove_at(index)
				else:
					stack["quantity"] = remaining
					stacks[index] = stack
				container["stacks"] = stacks
				group[container_id] = container
				candidate[group_name] = group
				_clear_missing_selection(candidate)
				return _success({"inventory": candidate})
	return _failure("missing_stack", "Стопка не найдена.")


static func _clear_missing_selection(inventory: Dictionary) -> void:
	var selected := String(inventory.get("selected_stack_id", ""))
	if not selected.is_empty() and Query.find_stack(inventory, selected).is_empty():
		inventory["selected_stack_id"] = ""


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(extra, true)
	return result


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
