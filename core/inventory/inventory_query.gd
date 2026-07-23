extends RefCounted

const ItemCatalog := preload("res://core/inventory/item_catalog.gd")


static func item_count(inventory: Dictionary, item_id: String) -> int:
	var result := 0
	for entry in all_stacks(inventory):
		if (
			not bool(entry.get("external", false))
			and String(entry.get("item_id", "")) == item_id
		):
			result += int(entry.get("quantity", 0))
	return result


static func all_stacks(inventory: Dictionary) -> Array:
	var result: Array = []
	for group_name in ["containers", "external_containers"]:
		var group: Dictionary = inventory.get(group_name, {})
		for container_id in group:
			var container: Dictionary = group[container_id]
			for stack_value in Array(container.get("stacks", [])):
				if stack_value is Dictionary:
					var stack := Dictionary(stack_value).duplicate(true)
					stack["container_id"] = String(container_id)
					stack["external"] = group_name == "external_containers"
					result.append(stack)
	return result


static func find_stack(inventory: Dictionary, stack_id: String) -> Dictionary:
	for entry in all_stacks(inventory):
		if String(entry.get("stack_id", "")) == stack_id:
			return entry
	return {}


static func locate_container(inventory: Dictionary, container_id: String) -> Dictionary:
	for group_name in ["containers", "external_containers"]:
		var group: Dictionary = inventory.get(group_name, {})
		if group.has(container_id) and group[container_id] is Dictionary:
			return {"group": group_name, "container": Dictionary(group[container_id])}
	return {}


static func container_usage(inventory: Dictionary, container_id: String) -> Dictionary:
	var located := locate_container(inventory, container_id)
	if located.is_empty():
		return {}
	var mass := 0
	var volume := 0
	for stack_value in Array(Dictionary(located["container"]).get("stacks", [])):
		if not stack_value is Dictionary:
			continue
		var stack: Dictionary = stack_value
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		var quantity := int(stack.get("quantity", 0))
		mass += definition.mass_grams() * quantity
		volume += definition.volume_ml() * quantity
	return {"mass_grams": mass, "volume_ml": volume}


static func capacity(inventory: Dictionary, container_id: String, strength: int) -> Dictionary:
	var located := locate_container(inventory, container_id)
	if located.is_empty():
		return {}
	var container: Dictionary = located["container"]
	var active := bool(container.get("active", true))
	var mass_capacity := (
		int(container.get("base_mass_capacity_grams", 0))
		+ int(container.get("mass_per_strength_grams", 0)) * maxi(strength, 0)
	)
	if not active:
		mass_capacity = 0
	var volume_capacity := int(container.get("volume_capacity_ml", 0)) if active else 0
	var usage := container_usage(inventory, container_id)
	return {
		"active": active,
		"mass_capacity_grams": mass_capacity,
		"volume_capacity_ml": volume_capacity,
		"mass_used_grams": int(usage.get("mass_grams", 0)),
		"volume_used_ml": int(usage.get("volume_ml", 0)),
		"mass_overloaded": mass_capacity >= 0 and int(usage.get("mass_grams", 0)) > mass_capacity,
		"volume_overloaded": volume_capacity >= 0 and int(usage.get("volume_ml", 0)) > volume_capacity,
	}


static func can_add(
	inventory: Dictionary,
	container_id: String,
	definition: Variant,
	quantity: int,
	strength: int
) -> bool:
	var limits := capacity(inventory, container_id, strength)
	if limits.is_empty() or not bool(limits.get("active", false)):
		return false
	var mass_capacity := int(limits.get("mass_capacity_grams", 0))
	var volume_capacity := int(limits.get("volume_capacity_ml", 0))
	var next_mass: int = int(limits.get("mass_used_grams", 0)) + definition.mass_grams() * quantity
	var next_volume: int = int(limits.get("volume_used_ml", 0)) + definition.volume_ml() * quantity
	return (
		(mass_capacity < 0 or next_mass <= mass_capacity)
		and (volume_capacity < 0 or next_volume <= volume_capacity)
	)


static func comparison(inventory: Dictionary, container_id: String) -> Array:
	var result: Array = []
	var located := locate_container(inventory, container_id)
	if located.is_empty():
		return result
	for stack_value in Array(Dictionary(located["container"]).get("stacks", [])):
		if not stack_value is Dictionary:
			continue
		var stack: Dictionary = stack_value
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		result.append({
			"stack_id": String(stack.get("stack_id", "")),
			"title": definition.title(),
			"quantity": int(stack.get("quantity", 0)),
			"mass_grams": definition.mass_grams() * int(stack.get("quantity", 0)),
			"volume_ml": definition.volume_ml() * int(stack.get("quantity", 0)),
		})
	return result
