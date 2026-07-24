class_name SearchSnapshotGenerator
extends RefCounted

const RngScript := preload("res://core/random/deterministic_rng.gd")
const SeedScript := preload("res://game/search/search_seed.gd")
const TemplateValidator := preload("res://game/search/search_template_validator.gd")
const SnapshotValidator := preload("res://game/search/search_snapshot_validator.gd")

const SNAPSHOT_SCHEMA_VERSION := 1


static func generate(
	template: Dictionary,
	run_seed: int,
	visit_index: int,
	generation_context: Dictionary = {}
) -> Dictionary:
	var template_validation := TemplateValidator.validate(template)
	if not bool(template_validation.get("ok", false)):
		return _failure("invalid_template", Array(template_validation.get("errors", [])))
	if visit_index < 1:
		return _failure("invalid_visit", ["visit_index должен быть не меньше 1"])
	var context_result := _normalize_context(generation_context)
	if not bool(context_result.get("ok", false)):
		return _failure("invalid_context", Array(context_result.get("errors", [])))
	var context: Dictionary = context_result["context"]
	var template_id := String(template["id"])
	var template_version := int(template["template_version"])
	var derived_seed := SeedScript.derive(run_seed, template_id, template_version, visit_index)
	var rng: DeterministicRng = RngScript.new(derived_seed)
	var objects := _resolve_objects(template, rng, int(context["luck"]))
	var map_data: Dictionary = Dictionary(template["map"]).duplicate(true)
	var spawn_node := String(map_data["spawn_node"])
	var spawn_position := _node_position(template, spawn_node)
	var stream := rng.to_dict()
	stream["stream_id"] = SeedScript.stream_id(template_id, template_version, visit_index)
	var snapshot := {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"template_id": template_id,
		"template_version": template_version,
		"visit_index": visit_index,
		"map": map_data,
		"walk_graph": Dictionary(template["walk_graph"]).duplicate(true),
		"rng": stream,
		"generation_context": context,
		"player": {
			"node_id": spawn_node,
			"position": spawn_position,
		},
		"risk": {
			"noise": 0,
			"trespass": 0,
			"repeated_attempts": 0,
		},
		"objects": objects,
		"ground_items": [],
		"applied_command_ids": [],
	}
	var snapshot_validation := SnapshotValidator.validate(snapshot, template)
	if not bool(snapshot_validation.get("ok", false)):
		return _failure("invalid_snapshot", Array(snapshot_validation.get("errors", [])))
	return {"ok": true, "snapshot": snapshot, "errors": []}


static func _resolve_objects(
	template: Dictionary,
	rng: DeterministicRng,
	luck: int
) -> Array:
	var result: Array = []
	var loot_tables: Dictionary = template["loot_tables"]
	for raw_object: Variant in Array(template["objects"]):
		var object: Dictionary = raw_object
		var object_id := String(object["id"])
		var loot_table_id := String(object["loot_table_id"])
		var loot_table: Dictionary = loot_tables[loot_table_id]
		result.append({
			"id": object_id,
			"title": String(object["title"]),
			"type": String(object["type"]),
			"position": Array(object["position"]).duplicate(),
			"approach_node": String(object["approach_node"]),
			"loot_table_id": loot_table_id,
			"approaches": Array(object["approaches"]).duplicate(true),
			"state": "concealed" if String(object["type"]) == "hidden" else "available",
			"revealed": String(object["type"]) != "hidden",
			"interacted": false,
			"contents": _roll_contents(object_id, loot_table, rng, luck),
		})
	return result


static func _roll_contents(
	object_id: String,
	loot_table: Dictionary,
	rng: DeterministicRng,
	luck: int
) -> Array:
	var rolls: Array = loot_table["rolls"]
	var roll_count := rng.next_int(int(rolls[0]), int(rolls[1]))
	var entries: Array = loot_table["entries"]
	var weights: Array = []
	for raw_entry: Variant in entries:
		var entry: Dictionary = raw_entry
		var weight := float(entry["weight"])
		weight += float(int(entry.get("luck_bias", 0)) * (luck - 5))
		weights.append(maxf(weight, 0.0))
	var result: Array = []
	for roll_index: int in roll_count:
		var entry_index := rng.weighted_index(weights)
		if entry_index < 0:
			break
		var selected: Dictionary = entries[entry_index]
		var quantity_range: Array = selected["quantity"]
		var condition_range: Array = selected["condition"]
		result.append({
			"loot_id": "%s:loot:%02d" % [object_id, roll_index + 1],
			"item_id": String(selected["item_id"]),
			"quantity": rng.next_int(int(quantity_range[0]), int(quantity_range[1])),
			"condition": rng.next_int(int(condition_range[0]), int(condition_range[1])),
			"claimed": false,
		})
	return result


static func _normalize_context(source: Dictionary) -> Dictionary:
	var luck_value: Variant = source.get("luck", 5)
	if typeof(luck_value) != TYPE_INT or int(luck_value) < 1 or int(luck_value) > 10:
		return {"ok": false, "errors": ["generation_context.luck должен быть целым числом 1–10"]}
	var depletion_value: Variant = source.get("depletion", 0)
	if typeof(depletion_value) != TYPE_INT or int(depletion_value) < 0:
		return {"ok": false, "errors": ["generation_context.depletion должен быть неотрицательным целым числом"]}
	var weather_value: Variant = source.get("weather", "dry")
	var time_band_value: Variant = source.get("time_band", "day")
	if typeof(weather_value) != TYPE_STRING or String(weather_value).strip_edges().is_empty():
		return {"ok": false, "errors": ["generation_context.weather должен быть непустой строкой"]}
	if typeof(time_band_value) != TYPE_STRING or String(time_band_value).strip_edges().is_empty():
		return {"ok": false, "errors": ["generation_context.time_band должен быть непустой строкой"]}
	return {
		"ok": true,
		"errors": [],
		"context": {
			"luck": int(luck_value),
			"depletion": int(depletion_value),
			"weather": String(weather_value),
			"time_band": String(time_band_value),
		},
	}


static func _node_position(template: Dictionary, node_id: String) -> Array:
	for raw_node: Variant in Array(Dictionary(template["walk_graph"])["nodes"]):
		if raw_node is Dictionary and String(raw_node.get("id", "")) == node_id:
			return Array(raw_node["position"]).duplicate()
	return []


static func _failure(code: String, raw_errors: Array) -> Dictionary:
	var errors: Array[String] = []
	for raw_error: Variant in raw_errors:
		errors.append(String(raw_error))
	return {"ok": false, "code": code, "snapshot": {}, "errors": errors}
