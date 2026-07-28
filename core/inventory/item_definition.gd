class_name ItemDefinition
extends RefCounted

## Immutable runtime view of one versioned item definition.

var _data: Dictionary


func _init(source: Dictionary) -> void:
	_data = source.duplicate(true)


func id() -> String:
	return String(_data.get("id", ""))


func title() -> String:
	return String(_data.get("title", id()))


func description() -> String:
	return String(_data.get("description", ""))


func tags() -> Array:
	return Array(_data.get("tags", [])).duplicate(true)


func stack_limit() -> int:
	return int(_data.get("stack_limit", 1))


func mass_grams() -> int:
	return int(_data.get("mass_grams", 0))


func volume_ml() -> int:
	return int(_data.get("volume_ml", 0))


func base_value() -> int:
	return int(_data.get("base_value", 0))


func action(action_id: String) -> Dictionary:
	var actions: Dictionary = _data.get("actions", {}) if _data.get("actions", {}) is Dictionary else {}
	var value: Variant = actions.get(action_id, {})
	if not value is Dictionary:
		return {}
	var result := Dictionary(value).duplicate(true)
	if not result.has("consumes"):
		result["consumes"] = action_id in ["use", "disassemble"]
	return result


func allowed_actions() -> Array[String]:
	var result: Array[String] = []
	var actions: Dictionary = _data.get("actions", {}) if _data.get("actions", {}) is Dictionary else {}
	for action_id in actions:
		result.append(String(action_id))
	result.sort()
	return result


func equip_slot() -> String:
	return String(action("equip").get("slot", ""))


func equip_modifiers() -> Dictionary:
	var modifiers: Variant = action("equip").get("modifiers", {})
	return Dictionary(modifiers).duplicate(true) if modifiers is Dictionary else {}


## A bag is the only equipment that carries other things, so its container
## specification travels with the item rather than being hard-coded per bag.
func equip_container() -> Dictionary:
	var container: Variant = action("equip").get("container", {})
	return Dictionary(container).duplicate(true) if container is Dictionary else {}


func is_unknown() -> bool:
	return bool(_data.get("unknown_fallback", false))


func to_view() -> Dictionary:
	return {
		"id": id(),
		"title": title(),
		"description": description(),
		"tags": tags(),
		"stack_limit": stack_limit(),
		"mass_grams": mass_grams(),
		"volume_ml": volume_ml(),
		"base_value": base_value(),
		"allowed_actions": allowed_actions(),
		"equip_slot": equip_slot(),
		"equip_modifiers": equip_modifiers(),
		"unknown_fallback": is_unknown(),
	}
