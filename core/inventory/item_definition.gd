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
		"unknown_fallback": is_unknown(),
	}
