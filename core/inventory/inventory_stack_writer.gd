extends RefCounted

const Schema := preload("res://core/inventory/inventory_schema.gd")
const Query := preload("res://core/inventory/inventory_query.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const Metadata := preload("res://core/inventory/inventory_metadata.gd")


static func add_to_container(
	inventory: Dictionary,
	container_id: String,
	item_id: String,
	quantity: int,
	condition: int,
	preserved_stack_id: String = "",
	metadata: Dictionary = {},
	quantity_encoding: String = ""
) -> Dictionary:
	var located := Query.locate_container(inventory, container_id)
	if located.is_empty():
		return _failure("missing_container", "Контейнер не найден.")
	var candidate := inventory.duplicate(true)
	located = Query.locate_container(candidate, container_id)
	var container: Dictionary = located["container"]
	var stacks: Array = Array(container.get("stacks", [])).duplicate(true)
	var definition: Variant = ItemCatalog.definition(item_id)
	var remaining := quantity
	var affected: Array[String] = []
	var compact := quantity_encoding == Schema.LEGACY_QUANTITY_ENCODING
	var stack_limit: int = Schema.LEGACY_QUANTITY_MAX if compact else definition.stack_limit()
	for index in range(stacks.size()):
		var stack: Dictionary = stacks[index]
		if not _can_merge(stack, item_id, condition, metadata, quantity_encoding):
			continue
		var room: int = stack_limit - int(stack.get("quantity", 0))
		if room <= 0:
			continue
		var added := mini(room, remaining)
		stack["quantity"] = int(stack.get("quantity", 0)) + added
		stacks[index] = stack
		affected.append(String(stack.get("stack_id", "")))
		remaining -= added
		if remaining == 0:
			break
	while remaining > 0:
		var added := mini(stack_limit, remaining)
		var stack_id := preserved_stack_id
		if stack_id.is_empty() or not affected.is_empty():
			stack_id = _next_stack_id(candidate)
		else:
			candidate["next_stack_sequence"] = maxi(
				int(candidate.get("next_stack_sequence", 1)),
				_stack_sequence(stack_id) + 1
			)
		var new_stack := {
			"stack_id": stack_id,
			"item_id": item_id,
			"quantity": added,
			"condition": condition,
			"metadata": metadata.duplicate(true),
		}
		if compact:
			new_stack["quantity_encoding"] = Schema.LEGACY_QUANTITY_ENCODING
		stacks.append(new_stack)
		affected.append(stack_id)
		remaining -= added
	container["stacks"] = stacks
	var group: Dictionary = candidate.get(String(located["group"]), {})
	group[container_id] = container
	candidate[String(located["group"])] = group
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"inventory": candidate,
		"container_id": container_id,
		"stack_ids": affected,
		"stack_id": affected[0] if not affected.is_empty() else "",
	}


static func _can_merge(
	stack: Dictionary,
	item_id: String,
	condition: int,
	metadata: Dictionary,
	quantity_encoding: String
) -> bool:
	return (
		String(stack.get("item_id", "")) == item_id
		and int(stack.get("condition", 100)) == condition
		and String(stack.get("quantity_encoding", "")) == quantity_encoding
		and Metadata.exactly_equal(Dictionary(stack.get("metadata", {})), metadata)
	)


static func _next_stack_id(inventory: Dictionary) -> String:
	var sequence := int(inventory.get("next_stack_sequence", 1))
	inventory["next_stack_sequence"] = sequence + 1
	return "stack:%06d" % sequence


static func _stack_sequence(stack_id: String) -> int:
	return int(stack_id.trim_prefix("stack:")) if stack_id.begins_with("stack:") else 0


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
