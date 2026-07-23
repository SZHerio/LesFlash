class_name InventoryState
extends RefCounted

## Small façade over schema, query and mutation modules. The serialized
## dictionary remains the aggregate boundary used by RunState and saves.

const Schema := preload("res://core/inventory/inventory_schema.gd")
const Query := preload("res://core/inventory/inventory_query.gd")
const Mutation := preload("res://core/inventory/inventory_mutation.gd")
const Replacement := preload("res://core/inventory/inventory_replacement.gd")

const SCHEMA_VERSION := 1


static func fresh() -> Dictionary:
	return Schema.fresh()


static func migrate_legacy(legacy: Dictionary) -> Dictionary:
	var result := fresh()
	if legacy.is_empty():
		return result
	var backpack: Dictionary = result["containers"]["backpack"]
	backpack["active"] = true
	backpack["title"] = "Старый мешок"
	result["containers"]["backpack"] = backpack
	var item_ids: Array = legacy.keys()
	item_ids.sort()
	for raw_id in item_ids:
		var item_id := String(raw_id)
		var quantity := int(legacy[raw_id])
		if item_id.is_empty() or quantity <= 0:
			continue
		var stack_id := "stack:%06d" % int(result["next_stack_sequence"])
		result["next_stack_sequence"] = int(result["next_stack_sequence"]) + 1
		backpack["stacks"].append({
			"stack_id": stack_id,
			"item_id": item_id,
			"quantity": quantity,
			"quantity_encoding": Schema.LEGACY_QUANTITY_ENCODING,
			"condition": 100,
			"metadata": {},
		})
	result["containers"]["backpack"] = backpack
	return result


static func normalize_serialized(value: Dictionary) -> Dictionary:
	return Schema.normalize_serialized(value)


static func validate(value: Variant) -> Dictionary:
	return Schema.validate(value)


static func item_count(inventory: Dictionary, item_id: String) -> int:
	return Query.item_count(inventory, item_id)


static func all_stacks(inventory: Dictionary) -> Array:
	return Query.all_stacks(inventory)


static func find_stack(inventory: Dictionary, stack_id: String) -> Dictionary:
	return Query.find_stack(inventory, stack_id)


static func container_usage(inventory: Dictionary, container_id: String) -> Dictionary:
	return Query.container_usage(inventory, container_id)


static func capacity(inventory: Dictionary, container_id: String, strength: int) -> Dictionary:
	return Query.capacity(inventory, container_id, strength)


static func add_item(
	inventory: Dictionary,
	item_id: String,
	quantity: int = 1,
	condition: int = 100,
	preferred_container: String = "",
	strength: int = 5,
	allow_overflow: bool = false,
	metadata: Dictionary = {}
) -> Dictionary:
	return Mutation.add_item(
		inventory,
		item_id,
		quantity,
		condition,
		preferred_container,
		strength,
		allow_overflow,
		metadata
	)


static func remove_item(inventory: Dictionary, item_id: String, quantity: int = 1) -> Dictionary:
	return Mutation.remove_item(inventory, item_id, quantity)


static func remove_stack(
	inventory: Dictionary,
	stack_id: String,
	quantity: int = 1
) -> Dictionary:
	return Mutation.remove_stack(inventory, stack_id, quantity)


static func move_stack(
	inventory: Dictionary,
	stack_id: String,
	target_container_id: String,
	quantity: int,
	strength: int
) -> Dictionary:
	return Mutation.move_stack(inventory, stack_id, target_container_id, quantity, strength)


static func replace_stack(
	inventory: Dictionary,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String,
	strength: int
) -> Dictionary:
	return Replacement.replace_stack(
		inventory,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id,
		strength
	)


static func ensure_external_container(
	inventory: Dictionary,
	container_id: String,
	title: String,
	kind: String = "ground"
) -> Dictionary:
	return Mutation.ensure_external_container(inventory, container_id, title, kind)


static func set_selected_stack(inventory: Dictionary, stack_id: String) -> Dictionary:
	return Mutation.set_selected_stack(inventory, stack_id)
