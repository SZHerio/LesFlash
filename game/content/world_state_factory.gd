class_name WorldStateFactory
extends RefCounted

## Creates runtime WorldState only from validated, versioned definitions.

const WorldStateScript := preload("res://core/world/world_state.gd")


static func from_catalog(catalog: Dictionary, at: Dictionary = {}) -> WorldState:
	var state := WorldStateScript.new()
	for raw_metric: Variant in Array(catalog.get("metrics", [])):
		if not raw_metric is Dictionary:
			return null
		var metric: Dictionary = raw_metric
		var metric_id := String(metric.get("id", ""))
		if metric_id.is_empty() or typeof(metric.get("default", null)) != TYPE_INT:
			return null
		state.metrics[metric_id] = int(metric["default"])
	for raw_fact: Variant in Array(catalog.get("facts", [])):
		if not raw_fact is Dictionary:
			return null
		var fact: Dictionary = raw_fact
		var fact_id := String(fact.get("id", ""))
		if fact_id.is_empty() or typeof(fact.get("default", null)) != TYPE_BOOL:
			return null
		state.facts[fact_id] = {
			"value": bool(fact["default"]),
			"source_id": "world_bootstrap",
			"changed_at": at.duplicate(true),
		}
	for raw_process: Variant in Array(catalog.get("processes", [])):
		if not raw_process is Dictionary:
			return null
		var process: Dictionary = raw_process
		var process_id := String(process.get("id", ""))
		var stage_id := String(process.get("initial_stage_id", ""))
		if process_id.is_empty() or stage_id.is_empty():
			return null
		state.processes[process_id] = {
			"stage": stage_id,
			"source_id": "world_bootstrap",
			"changed_at": at.duplicate(true),
		}
	return state if bool(state.validate().get("ok", false)) else null
