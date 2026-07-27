class_name WorldProcessTimeAdvancer
extends RefCounted

## Pure planner for autonomous process transitions caused by confirmed time.
## It never mutates WorldState and never advances the calendar. The selected
## effect must be committed by SessionCommandTransaction through WorldMutation.

const WorldCatalog := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)

const ADVANCE_MODE := "confirmed_time"
const RECYCLING_PROCESS_ID := "process_recycling_inspection"


static func plan(
	state: WorldState,
	before_elapsed_minutes: int,
	after_elapsed_minutes: int,
	definitions: Dictionary = {}
) -> Dictionary:
	if state == null:
		return _failure("missing_world_state", "Состояние мира отсутствует")
	if before_elapsed_minutes < 0 or after_elapsed_minutes < 0:
		return _failure("invalid_time_interval", "Границы времени не могут быть отрицательными")
	if after_elapsed_minutes < before_elapsed_minutes:
		return _failure("time_went_backwards", "Время мира не может идти назад")
	if after_elapsed_minutes == before_elapsed_minutes:
		return _idle("no_confirmed_time", before_elapsed_minutes, after_elapsed_minutes)
	if state.process_stage(RECYCLING_PROCESS_ID).is_empty():
		return _idle("process_not_initialized", before_elapsed_minutes, after_elapsed_minutes)
	var resolved := _resolve_definitions(definitions)
	if not bool(resolved.get("ok", false)):
		return resolved
	var catalog: Dictionary = resolved["catalog"]
	var process := _find_by_id(
		Array(catalog.get("processes", [])), RECYCLING_PROCESS_ID
	)
	if process.is_empty():
		return _failure(
			"missing_process_definition",
			"Определение процесса %s отсутствует" % RECYCLING_PROCESS_ID
		)
	if String(process.get("advance_mode", "")) != ADVANCE_MODE:
		return _failure(
			"unsupported_process_advance_mode",
			"Процесс не поддерживает подтверждённое продвижение времени"
		)
	var current_stage := state.process_stage(RECYCLING_PROCESS_ID)
	var stage_definition := _find_by_id(Array(process.get("stages", [])), current_stage)
	if stage_definition.is_empty():
		return _failure(
			"unknown_process_stage",
			"Стадия процесса %s не определена" % current_stage
		)
	if bool(stage_definition.get("terminal", false)):
		return _idle(
			"terminal_stage",
			before_elapsed_minutes,
			after_elapsed_minutes,
			current_stage
		)
	if _changed_during_interval(state, before_elapsed_minutes):
		return _idle(
			"already_changed_in_command",
			before_elapsed_minutes,
			after_elapsed_minutes,
			current_stage
		)
	var candidates := _eligible_transitions(
		state,
		process,
		current_stage,
		after_elapsed_minutes
	)
	if candidates.is_empty():
		return _idle(
			"not_due",
			before_elapsed_minutes,
			after_elapsed_minutes,
			current_stage
		)
	candidates.sort_custom(_transition_precedes)
	if (
		candidates.size() > 1
		and int(candidates[0].get("priority", -1))
			== int(candidates[1].get("priority", -1))
	):
		return _failure(
			"ambiguous_world_process_transition",
			"Несколько переходов процесса имеют одинаковый приоритет"
		)
	var selected: Dictionary = candidates[0]
	var effect := {
		"type": "advance_world_process",
		"id": RECYCLING_PROCESS_ID,
		"stage": String(selected.get("to_stage_id", "")),
		"trigger_id": String(selected.get("trigger_id", "")),
	}
	return {
		"ok": true,
		"code": "transition_planned",
		"error": "",
		"advanced": true,
		"before_elapsed_minutes": before_elapsed_minutes,
		"after_elapsed_minutes": after_elapsed_minutes,
		"process_id": RECYCLING_PROCESS_ID,
		"from_stage_id": current_stage,
		"to_stage_id": effect["stage"],
		"transition_id": String(selected.get("id", "")),
		"trigger_id": effect["trigger_id"],
		"priority": int(selected.get("priority", 0)),
		"eligible_candidate_ids": _ids(candidates),
		"effects": [effect],
	}


static func _resolve_definitions(definitions: Dictionary) -> Dictionary:
	if not definitions.is_empty():
		var validation := WorldCatalog.validate(definitions)
		if not bool(validation.get("ok", false)):
			return _failure(
				"invalid_world_definitions",
				"Определения процессов мира не прошли проверку",
				{"validation": validation}
			)
		return {"ok": true, "catalog": definitions.duplicate(true)}
	var loaded := WorldCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure(
			"world_definitions_load_failed",
			"Не удалось загрузить определения процессов мира",
			{"validation": loaded}
		)
	return {
		"ok": true,
		"catalog": Dictionary(loaded.get("catalog", {})).duplicate(true),
	}


static func _changed_during_interval(state: WorldState, before_elapsed: int) -> bool:
	var record: Variant = state.processes.get(RECYCLING_PROCESS_ID)
	if not record is Dictionary:
		return false
	var changed_at: Variant = Dictionary(record).get("changed_at", null)
	return (
		changed_at is Dictionary
		and typeof(Dictionary(changed_at).get("elapsed_minutes", null)) == TYPE_INT
		and int(Dictionary(changed_at)["elapsed_minutes"]) > before_elapsed
	)


static func _eligible_transitions(
	state: WorldState,
	process: Dictionary,
	current_stage: String,
	after_elapsed_minutes: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_transition: Variant in Array(process.get("transitions", [])):
		if not raw_transition is Dictionary:
			continue
		var transition: Dictionary = raw_transition
		if String(transition.get("from_stage_id", "")) != current_stage:
			continue
		if typeof(transition.get("priority", null)) != TYPE_INT:
			continue
		if typeof(transition.get("eligible_after_elapsed_minutes", null)) != TYPE_INT:
			continue
		if int(transition["eligible_after_elapsed_minutes"]) > after_elapsed_minutes:
			continue
		if not _facts_satisfied(state, transition):
			continue
		result.append(transition.duplicate(true))
	return result


static func _facts_satisfied(state: WorldState, transition: Dictionary) -> bool:
	for raw_id: Variant in Array(transition.get("required_fact_ids", [])):
		if not state.fact_value(String(raw_id)):
			return false
	for raw_id: Variant in Array(transition.get("excluded_fact_ids", [])):
		if state.fact_value(String(raw_id)):
			return false
	return true


static func _transition_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return String(left.get("id", "")) < String(right.get("id", ""))


static func _find_by_id(entries: Array, identifier: String) -> Dictionary:
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == identifier:
			return Dictionary(raw_entry).duplicate(true)
	return {}


static func _ids(entries: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in entries:
		result.append(String(entry.get("id", "")))
	return result


static func _idle(
	code: String,
	before_elapsed_minutes: int,
	after_elapsed_minutes: int,
	stage_id: String = ""
) -> Dictionary:
	return {
		"ok": true,
		"code": code,
		"error": "",
		"advanced": false,
		"before_elapsed_minutes": before_elapsed_minutes,
		"after_elapsed_minutes": after_elapsed_minutes,
		"process_id": RECYCLING_PROCESS_ID,
		"from_stage_id": stage_id,
		"effects": [],
	}


static func _failure(
	code: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message, "effects": []}
	result.merge(details, true)
	return result
