class_name WorldMutation
extends RefCounted

## Whitelisted, data-only mutation interpreter for WorldState.

const SCHEMA_VERSION := 1
const OPERATION_TYPES := [
	"set_world_fact",
	"change_world_metric",
	"advance_world_process",
	"schedule_world_mutation",
	"cancel_world_mutation",
	"replace_stock",
]


static func apply(
	target: WorldState,
	mutation: Dictionary,
	definitions: Dictionary = {}
) -> Dictionary:
	if target == null:
		return _failure("missing_world_state", "Состояние мира отсутствует")
	var validation := validate(mutation)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_world_mutation", "; ".join(PackedStringArray(validation["errors"])))
	var working := target.clone()
	if working == null:
		return _failure("world_clone_failed", "Не удалось создать копию состояния мира")
	var changes: Array[Dictionary] = []
	var source_id := String(mutation.get("source_id", ""))
	var at: Dictionary = Dictionary(mutation.get("at", {})).duplicate(true)
	for index: int in Array(mutation["operations"]).size():
		var operation: Dictionary = mutation["operations"][index]
		var result := _apply_operation(working, operation, source_id, at, definitions)
		if not bool(result.get("ok", false)):
			return _failure(
				String(result.get("code", "world_operation_failed")),
				String(result.get("error", "Не удалось изменить мир")),
				{"failed_index": index, "changes": changes}
			)
		changes.append(Dictionary(result["change"]).duplicate(true))
	working.revision += 1
	var state_validation := working.validate()
	if not bool(state_validation.get("ok", false)):
		return _failure(
			"invalid_world_result",
			"Мутация создала недопустимое состояние мира",
			{"validation": state_validation}
		)
	if not target.replace_from(working):
		return _failure("world_commit_failed", "Не удалось зафиксировать состояние мира")
	return {"ok": true, "code": "ok", "error": "", "changes": changes}


static func apply_due(
	target: WorldState,
	current_stamp: Dictionary,
	definitions: Dictionary = {}
) -> Dictionary:
	if target == null or typeof(current_stamp.get("elapsed_minutes", null)) != TYPE_INT:
		return _failure("invalid_due_context", "Нельзя обработать очередь мира без времени")
	var working := target.clone()
	if working == null:
		return _failure("world_clone_failed", "Не удалось создать копию состояния мира")
	var due: Array = []
	var pending: Array = []
	for raw_entry: Variant in working.scheduled_mutations:
		var entry: Dictionary = raw_entry
		if int(Dictionary(entry.get("due", {})).get("elapsed_minutes", 0)) <= int(current_stamp["elapsed_minutes"]):
			due.append(entry.duplicate(true))
		else:
			pending.append(entry.duplicate(true))
	due.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_due := int(Dictionary(left.get("due", {})).get("elapsed_minutes", 0))
		var right_due := int(Dictionary(right.get("due", {})).get("elapsed_minutes", 0))
		return left_due < right_due or (left_due == right_due and String(left.get("mutation_id", "")) < String(right.get("mutation_id", "")))
	)
	working.scheduled_mutations = pending
	var changes: Array[Dictionary] = []
	for entry: Dictionary in due:
		var result := apply(working, {
			"schema_version": SCHEMA_VERSION,
			"source_id": String(entry.get("source_id", "")),
			"at": current_stamp.duplicate(true),
			"operations": Array(entry.get("operations", [])).duplicate(true),
		}, definitions)
		if not bool(result.get("ok", false)):
			return _failure(
				"due_world_mutation_failed",
				String(result.get("error", "Отложенное изменение мира не применилось")),
				{"mutation_id": String(entry.get("mutation_id", "")), "cause": result}
			)
		changes.append_array(Array(result.get("changes", [])).duplicate(true))
	if due.is_empty():
		return {"ok": true, "code": "ok", "error": "", "changes": [], "applied": 0}
	var validation := working.validate()
	if not bool(validation.get("ok", false)) or not target.replace_from(working):
		return _failure("due_world_commit_failed", "Не удалось зафиксировать очередь мира")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"changes": changes,
		"applied": due.size(),
	}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["world_mutation must be a dictionary"]}
	var mutation: Dictionary = value
	if int(mutation.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("world_mutation.schema_version is unsupported")
	if String(mutation.get("source_id", "")).strip_edges().is_empty():
		errors.append("world_mutation.source_id cannot be empty")
	if not mutation.get("at", null) is Dictionary:
		errors.append("world_mutation.at must be a dictionary")
	var operations: Variant = mutation.get("operations", null)
	if not operations is Array or operations.is_empty():
		errors.append("world_mutation.operations must be a non-empty array")
	else:
		for index: int in operations.size():
			var operation: Variant = operations[index]
			if not operation is Dictionary:
				errors.append("world_mutation.operations[%d] must be a dictionary" % index)
				continue
			if String(operation.get("type", "")) not in OPERATION_TYPES:
				errors.append("world_mutation.operations[%d].type is unsupported" % index)
	return {"ok": errors.is_empty(), "errors": errors}


static func _apply_operation(
	state: WorldState,
	operation: Dictionary,
	source_id: String,
	at: Dictionary,
	definitions: Dictionary
) -> Dictionary:
	var operation_type := String(operation.get("type", ""))
	var identifier := String(operation.get("id", ""))
	match operation_type:
		"set_world_fact":
			if not _known(definitions, "facts", identifier) or typeof(operation.get("value", null)) != TYPE_BOOL:
				return _failure("invalid_world_fact", "Неизвестный или неверный факт мира: %s" % identifier)
			var before := state.fact_value(identifier)
			state.facts[identifier] = {
				"value": bool(operation["value"]),
				"source_id": source_id,
				"changed_at": at.duplicate(true),
			}
			return _change(operation_type, identifier, before, bool(operation["value"]))
		"change_world_metric":
			if not _known(definitions, "metrics", identifier) or typeof(operation.get("delta", null)) != TYPE_INT:
				return _failure("invalid_world_metric", "Неизвестный или неверный показатель мира: %s" % identifier)
			var before := state.metric_value(identifier)
			var after := before + int(operation["delta"])
			if after < WorldState.METRIC_MIN or after > WorldState.METRIC_MAX:
				return _failure("world_metric_out_of_range", "Показатель %s вышел за пределы 0..100" % identifier)
			state.metrics[identifier] = after
			return _change(operation_type, identifier, before, after)
		"advance_world_process":
			var process_definition := _definition(definitions, "processes", identifier)
			if process_definition.is_empty():
				return _failure("unknown_world_process", "Неизвестный процесс мира: %s" % identifier)
			var before := state.process_stage(identifier)
			if before.is_empty():
				before = String(process_definition.get(
					"initial_stage_id",
					process_definition.get("initial_stage", "")
				))
			var after := String(operation.get("stage", operation.get("to_stage", "")))
			var trigger_id := String(operation.get("trigger_id", ""))
			if not _transition_allowed(process_definition, before, after, trigger_id, state):
				return _failure("invalid_world_process_transition", "Недопустимый переход %s: %s → %s" % [identifier, before, after])
			state.processes[identifier] = {"stage": after, "source_id": source_id, "changed_at": at.duplicate(true)}
			return _change(operation_type, identifier, before, after)
		"schedule_world_mutation":
			var mutation_id := String(operation.get("mutation_id", identifier))
			var due: Variant = operation.get("due", null)
			var operations: Variant = operation.get("operations", null)
			if mutation_id.is_empty() or not _valid_due(due) or not _valid_scheduled_operations(operations):
				return _failure("invalid_scheduled_world_mutation", "Отложенная мутация мира заполнена неверно")
			for existing: Variant in state.scheduled_mutations:
				if String(Dictionary(existing).get("mutation_id", "")) == mutation_id:
					return _failure("duplicate_world_mutation", "Мутация %s уже запланирована" % mutation_id)
			state.scheduled_mutations.append({
				"mutation_id": mutation_id,
				"due": Dictionary(due).duplicate(true),
				"source_id": source_id,
				"operations": Array(operations).duplicate(true),
			})
			return _change(operation_type, mutation_id, null, due)
		"cancel_world_mutation":
			var mutation_id := String(operation.get("mutation_id", identifier))
			for index: int in state.scheduled_mutations.size():
				if String(Dictionary(state.scheduled_mutations[index]).get("mutation_id", "")) == mutation_id:
					var removed: Dictionary = state.scheduled_mutations[index]
					state.scheduled_mutations.remove_at(index)
					return _change(operation_type, mutation_id, removed, null)
			return _failure("unknown_scheduled_world_mutation", "Мутация %s не найдена" % mutation_id)
		"replace_stock":
			var store_id := String(operation.get("store_id", identifier))
			var snapshot: Variant = operation.get("snapshot", null)
			if store_id.is_empty() or not snapshot is Dictionary or String(Dictionary(snapshot).get("store_id", "")) != store_id:
				return _failure("invalid_stock_snapshot", "Поставка магазина заполнена неверно")
			var before: Variant = state.stock_snapshots.get(store_id)
			state.stock_snapshots[store_id] = Dictionary(snapshot).duplicate(true)
			return _change(operation_type, store_id, before, snapshot)
	return _failure("unknown_world_operation", "Неизвестное изменение мира")


static func _known(definitions: Dictionary, section: String, identifier: String) -> bool:
	if identifier.is_empty():
		return false
	if definitions.is_empty():
		return true
	return not _definition(definitions, section, identifier).is_empty()


static func _definition(definitions: Dictionary, section: String, identifier: String) -> Dictionary:
	var raw_section: Variant = definitions.get(section, {})
	if raw_section is Dictionary:
		var value: Variant = Dictionary(raw_section).get(identifier)
		return Dictionary(value).duplicate(true) if value is Dictionary else {}
	if raw_section is Array:
		for raw_value: Variant in raw_section:
			if raw_value is Dictionary and String(raw_value.get("id", "")) == identifier:
				return Dictionary(raw_value).duplicate(true)
	return {}


static func _transition_allowed(
	definition: Dictionary,
	before: String,
	after: String,
	trigger_id: String,
	state: WorldState
) -> bool:
	if before.is_empty() or after.is_empty() or before == after:
		return false
	var transitions: Variant = definition.get("transitions", {})
	if transitions is Dictionary:
		return after in Array(Dictionary(transitions).get(before, []))
	if transitions is Array:
		for raw_transition: Variant in transitions:
			if not raw_transition is Dictionary:
				continue
			var transition: Dictionary = raw_transition
			var from_id := String(transition.get("from_stage_id", transition.get("from", "")))
			var to_id := String(transition.get("to_stage_id", transition.get("to", "")))
			if from_id != before or to_id != after:
				continue
			var expected_trigger := String(transition.get("trigger_id", ""))
			if not expected_trigger.is_empty() and trigger_id != expected_trigger:
				continue
			if not _facts_satisfied(state, transition):
				continue
			return true
	return false


static func _facts_satisfied(state: WorldState, transition: Dictionary) -> bool:
	for raw_id: Variant in Array(transition.get("required_fact_ids", [])):
		if not state.fact_value(String(raw_id)):
			return false
	for raw_id: Variant in Array(transition.get("excluded_fact_ids", [])):
		if state.fact_value(String(raw_id)):
			return false
	return true


static func _valid_due(value: Variant) -> bool:
	return (
		value is Dictionary
		and typeof(Dictionary(value).get("elapsed_minutes", null)) == TYPE_INT
		and int(Dictionary(value).get("elapsed_minutes", -1)) >= 0
	)


static func _valid_scheduled_operations(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	for raw_operation: Variant in value:
		if not raw_operation is Dictionary:
			return false
		var operation_type := String(Dictionary(raw_operation).get("type", ""))
		if operation_type not in OPERATION_TYPES or operation_type == "schedule_world_mutation":
			return false
	return true


static func _change(kind: String, identifier: String, before: Variant, after: Variant) -> Dictionary:
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"change": {"effect_type": kind, "target_id": identifier, "before": before, "after": after},
	}


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
