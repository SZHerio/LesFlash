class_name WorldState
extends RefCounted

## Objective, serializable state of one world timeline.
##
## Hero knowledge and NPC attitudes deliberately live elsewhere. This object
## stores only facts which are true in the run, slow district metrics, staged
## processes, scheduled mutations and persisted store stock.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1
const METRIC_MIN := 0
const METRIC_MAX := 100
const SCHEDULED_OPERATION_TYPES := [
	"set_world_fact",
	"change_world_metric",
	"advance_world_process",
	"cancel_world_mutation",
	"replace_stock",
]

var revision: int = 0
var facts: Dictionary = {}
var metrics: Dictionary = {}
var processes: Dictionary = {}
var scheduled_mutations: Array = []
var stock_snapshots: Dictionary = {}


static func fresh(
	metric_defaults: Dictionary = {},
	process_defaults: Dictionary = {}
) -> WorldState:
	var result := WorldState.new()
	for raw_id: Variant in metric_defaults:
		result.metrics[String(raw_id)] = int(metric_defaults[raw_id])
	for raw_id: Variant in process_defaults:
		result.processes[String(raw_id)] = {
			"stage": String(process_defaults[raw_id]),
			"source_id": "world_bootstrap",
			"changed_at": {},
		}
	return result if bool(result.validate().get("ok", false)) else null


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": revision,
		"facts": facts.duplicate(true),
		"metrics": metrics.duplicate(true),
		"processes": processes.duplicate(true),
		"scheduled_mutations": scheduled_mutations.duplicate(true),
		"stock_snapshots": stock_snapshots.duplicate(true),
	}


static func from_dict(data: Dictionary) -> WorldState:
	var normalized: Variant = JsonValidator.normalize_numbers(data)
	if not normalized is Dictionary:
		return null
	var source: Dictionary = normalized
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return null
	var parsed_revision: Variant = _integral(source.get("revision", null))
	if parsed_revision == null or int(parsed_revision) < 0:
		return null
	for field: String in ["facts", "metrics", "processes", "stock_snapshots"]:
		if not source.get(field, null) is Dictionary:
			return null
	if not source.get("scheduled_mutations", null) is Array:
		return null
	var result := WorldState.new()
	result.revision = int(parsed_revision)
	result.facts = Dictionary(source["facts"]).duplicate(true)
	result.metrics = Dictionary(source["metrics"]).duplicate(true)
	result.processes = Dictionary(source["processes"]).duplicate(true)
	result.scheduled_mutations = Array(source["scheduled_mutations"]).duplicate(true)
	result.stock_snapshots = Dictionary(source["stock_snapshots"]).duplicate(true)
	var validation := result.validate()
	return result if bool(validation.get("ok", false)) else null


func clone() -> WorldState:
	return WorldState.from_dict(to_dict())


func replace_from(other: WorldState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	revision = other.revision
	facts = other.facts.duplicate(true)
	metrics = other.metrics.duplicate(true)
	processes = other.processes.duplicate(true)
	scheduled_mutations = other.scheduled_mutations.duplicate(true)
	stock_snapshots = other.stock_snapshots.duplicate(true)
	return true


func fact_value(fact_id: String) -> bool:
	var record: Variant = facts.get(fact_id)
	return bool(Dictionary(record).get("value", false)) if record is Dictionary else false


func metric_value(metric_id: String, fallback: int = 0) -> int:
	return int(metrics.get(metric_id, fallback))


func process_stage(process_id: String) -> String:
	var record: Variant = processes.get(process_id)
	return String(Dictionary(record).get("stage", "")) if record is Dictionary else ""


func validate() -> Dictionary:
	var errors: Array[String] = []
	if revision < 0:
		errors.append("world_state.revision cannot be negative")
	_validate_facts(errors)
	_validate_metrics(errors)
	_validate_processes(errors)
	_validate_scheduled(errors)
	_validate_stock(errors)
	var json_validation := JsonValidator.validate(to_dict(), "world_state")
	for raw_error: Variant in Array(json_validation.get("errors", [])):
		errors.append(String(raw_error))
	return {"ok": errors.is_empty(), "errors": errors}


func _validate_facts(errors: Array[String]) -> void:
	for raw_id: Variant in facts:
		var fact_id := String(raw_id)
		var record: Variant = facts[raw_id]
		if not _valid_id(fact_id) or not record is Dictionary:
			errors.append("world_state.facts contains an invalid record")
			continue
		var value: Dictionary = record
		if typeof(value.get("value", null)) != TYPE_BOOL:
			errors.append("world_state.facts.%s.value must be boolean" % fact_id)
		if typeof(value.get("source_id", null)) != TYPE_STRING:
			errors.append("world_state.facts.%s.source_id must be a string" % fact_id)
		if not value.get("changed_at", null) is Dictionary:
			errors.append("world_state.facts.%s.changed_at must be a dictionary" % fact_id)


func _validate_metrics(errors: Array[String]) -> void:
	for raw_id: Variant in metrics:
		var metric_id := String(raw_id)
		if not _valid_id(metric_id) or typeof(metrics[raw_id]) != TYPE_INT:
			errors.append("world_state.metrics contains an invalid value")
			continue
		var value := int(metrics[raw_id])
		if value < METRIC_MIN or value > METRIC_MAX:
			errors.append("world_state.metrics.%s is outside 0..100" % metric_id)


func _validate_processes(errors: Array[String]) -> void:
	for raw_id: Variant in processes:
		var process_id := String(raw_id)
		var record: Variant = processes[raw_id]
		if not _valid_id(process_id) or not record is Dictionary:
			errors.append("world_state.processes contains an invalid record")
			continue
		var value: Dictionary = record
		if not _valid_id(value.get("stage", null)):
			errors.append("world_state.processes.%s.stage is invalid" % process_id)
		if typeof(value.get("source_id", null)) != TYPE_STRING:
			errors.append("world_state.processes.%s.source_id must be a string" % process_id)
		if not value.get("changed_at", null) is Dictionary:
			errors.append("world_state.processes.%s.changed_at must be a dictionary" % process_id)


func _validate_scheduled(errors: Array[String]) -> void:
	var ids: Dictionary = {}
	for index: int in scheduled_mutations.size():
		var raw_entry: Variant = scheduled_mutations[index]
		if not raw_entry is Dictionary:
			errors.append("world_state.scheduled_mutations[%d] must be a dictionary" % index)
			continue
		var entry: Dictionary = raw_entry
		var mutation_id := String(entry.get("mutation_id", ""))
		if not _valid_id(mutation_id) or ids.has(mutation_id):
			errors.append("world_state.scheduled_mutations[%d].mutation_id is invalid" % index)
		else:
			ids[mutation_id] = true
		if typeof(entry.get("source_id", null)) != TYPE_STRING:
			errors.append("world_state.scheduled_mutations[%d].source_id must be a string" % index)
		var due: Variant = entry.get("due", null)
		if not due is Dictionary or typeof(Dictionary(due).get("elapsed_minutes", null)) != TYPE_INT or int(Dictionary(due).get("elapsed_minutes", -1)) < 0:
			errors.append("world_state.scheduled_mutations[%d].due is invalid" % index)
		if not entry.get("operations", null) is Array or Array(entry.get("operations", [])).is_empty():
			errors.append("world_state.scheduled_mutations[%d].operations must be non-empty" % index)
		else:
			for raw_operation: Variant in Array(entry.get("operations", [])):
				if not raw_operation is Dictionary or String(Dictionary(raw_operation).get("type", "")) not in SCHEDULED_OPERATION_TYPES:
					errors.append("world_state.scheduled_mutations[%d] contains an invalid nested operation" % index)
					break


func _validate_stock(errors: Array[String]) -> void:
	for raw_id: Variant in stock_snapshots:
		var store_id := String(raw_id)
		var snapshot: Variant = stock_snapshots[raw_id]
		if not _valid_id(store_id) or not snapshot is Dictionary:
			errors.append("world_state.stock_snapshots contains an invalid snapshot")
			continue
		if String(Dictionary(snapshot).get("store_id", "")) != store_id:
			errors.append("world_state.stock_snapshots.%s store_id mismatch" % store_id)


static func _integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)):
		return int(value)
	return null


static func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := String(value)
	if identifier.is_empty() or identifier != identifier.to_lower():
		return false
	for character: String in identifier:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true
