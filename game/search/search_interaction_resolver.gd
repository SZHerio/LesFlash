class_name SearchInteractionResolver
extends RefCounted

## Read-only lookup and exact preview of one authored search interaction.


static func preview(
	run_state: RunState,
	snapshot: Dictionary,
	object_id: String,
	approach_id: String,
	require_proximity: bool = true
) -> Dictionary:
	var object := find_object(snapshot, object_id)
	if object.is_empty():
		return _failure("unknown_search_object", "Объект поиска не найден.")
	var approach := find_approach(object, approach_id)
	if approach.is_empty():
		return _failure("unknown_search_approach", "Способ взаимодействия не найден.")
	var costs := costs_of(approach)
	var conditions := normalized_conditions(Array(approach.get("conditions", [])))
	if int(costs["energy"]) > 0:
		conditions.append({
			"type": "state",
			"id": "energy",
			"value": int(costs["energy"]),
		})
	var checks := CheckResolver.evaluate_all(
		run_state,
		conditions,
		{
			"source": "search",
			"object_id": object_id,
			"action_id": approach_id,
		}
	)
	var reasons: Array = Array(checks.get("reasons", [])).duplicate(true)
	if String(object.get("state", "")) == "exhausted" or bool(object.get("interacted", false)):
		reasons.push_front(_manual_reason(
			"object_exhausted",
			"Здесь уже всё осмотрено."
		))
	if require_proximity and (
		String(Dictionary(snapshot.get("player", {})).get("node_id", ""))
		!= String(object.get("approach_node", ""))
	):
		reasons.push_front(_manual_reason(
			"object_out_of_range",
			"Сначала подойдите к объекту."
		))
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"allowed": reasons.is_empty(),
		"blocked_reasons": reasons,
		"checks": Array(checks.get("checks", [])).duplicate(true),
		"object": object.duplicate(true),
		"approach": approach.duplicate(true),
		"conditions": conditions,
		"costs": costs,
	}


static func find_object(snapshot: Dictionary, object_id: String) -> Dictionary:
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if raw_object is Dictionary and String(raw_object.get("id", "")) == object_id:
			return Dictionary(raw_object).duplicate(true)
	return {}


static func find_approach(object: Dictionary, approach_id: String) -> Dictionary:
	for raw_approach: Variant in Array(object.get("approaches", [])):
		if raw_approach is Dictionary and String(raw_approach.get("id", "")) == approach_id:
			return Dictionary(raw_approach).duplicate(true)
	return {}


static func costs_of(approach: Dictionary) -> Dictionary:
	var risk: Dictionary = approach.get("risk", {})
	return {
		"minutes": int(approach.get("duration_minutes", 0)),
		"energy": int(approach.get("energy_cost", 0)),
		"noise": int(risk.get("noise", 0)),
		"trespass": int(risk.get("trespass", 0)),
	}


static func normalized_conditions(raw_conditions: Array) -> Array:
	var result: Array = []
	for raw_condition: Variant in raw_conditions:
		if not raw_condition is Dictionary:
			result.append(raw_condition)
			continue
		var condition: Dictionary = raw_condition.duplicate(true)
		if String(condition.get("type", "")) == "characteristic":
			condition["type"] = "stat"
		if condition.has("minimum") and not (
			condition.has("value")
			or condition.has("amount")
			or condition.has("quantity")
			or condition.has("rank")
			or condition.has("level")
		):
			condition["value"] = condition["minimum"]
		result.append(condition)
	return result


static func exhausted_count(snapshot: Dictionary) -> int:
	var result := 0
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if raw_object is Dictionary and (
			String(raw_object.get("state", "")) == "exhausted"
			or bool(raw_object.get("interacted", false))
		):
			result += 1
	return result


static func replace_object(snapshot: Dictionary, updated: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	var objects: Array = Array(result.get("objects", [])).duplicate(true)
	for index in range(objects.size()):
		if (
			objects[index] is Dictionary
			and String(objects[index].get("id", "")) == String(updated.get("id", ""))
		):
			objects[index] = updated.duplicate(true)
			result["objects"] = objects
			return result
	return result


static func _manual_reason(code: String, message: String) -> Dictionary:
	return {
		"passed": false,
		"code": code,
		"message": message,
		"kind": "search",
		"id": "",
		"operator": "",
		"required": null,
		"actual": null,
		"condition": {},
	}


static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"error": message,
		"allowed": false,
		"blocked_reasons": [],
	}
