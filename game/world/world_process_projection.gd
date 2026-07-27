class_name WorldProcessProjection
extends RefCounted

## Pure observable projection of an authored process stage. Consumers receive
## one shared source for job, commerce, location and event consequences.

const WorldCatalog := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)
const RECYCLING_PROCESS_ID := "process_recycling_inspection"


static func recycling_inspection(
	state: WorldState,
	definitions: Dictionary = {}
) -> Dictionary:
	return build(state, RECYCLING_PROCESS_ID, definitions)


static func build(
	state: WorldState,
	process_id: String,
	definitions: Dictionary = {}
) -> Dictionary:
	if state == null:
		return _failure("missing_world_state", "Состояние мира отсутствует")
	var stage_id := state.process_stage(process_id)
	if stage_id.is_empty():
		return _failure("process_not_initialized", "Процесс мира не инициализирован")
	var resolved := _definitions(definitions)
	if not bool(resolved.get("ok", false)):
		return resolved
	var process := _find_by_id(
		Array(Dictionary(resolved["catalog"]).get("processes", [])),
		process_id
	)
	if process.is_empty():
		return _failure("missing_process_definition", "Определение процесса отсутствует")
	var stage := _find_by_id(Array(process.get("stages", [])), stage_id)
	if stage.is_empty():
		return _failure("unknown_process_stage", "Стадия процесса не определена")
	var projection: Dictionary = Dictionary(stage.get("projection", {})).duplicate(true)
	var job: Dictionary = Dictionary(projection.get("job", {})).duplicate(true)
	var recycling: Dictionary = Dictionary(
		projection.get("recycling", {})
	).duplicate(true)
	var location: Dictionary = Dictionary(
		projection.get("location", {})
	).duplicate(true)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"world_revision": state.revision,
		"process_id": process_id,
		"stage_id": stage_id,
		"stage_title": String(stage.get("title", stage_id)),
		"terminal": bool(stage.get("terminal", false)),
		"job": job,
		"recycling": recycling,
		"location": location,
		"event_tags": Array(projection.get("event_tags", [])).duplicate(),
		"job_available": bool(job.get("available", false)),
		"job_pay_basis_points": int(job.get("pay_basis_points", 0)),
		"recycling_accepting_materials": bool(
			recycling.get("accepting_materials", false)
		),
		"recycling_price_basis_points": int(
			recycling.get("price_basis_points", 0)
		),
		"location_status_id": String(location.get("status_id", "")),
	}


static func _definitions(definitions: Dictionary) -> Dictionary:
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


static func _find_by_id(entries: Array, identifier: String) -> Dictionary:
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == identifier:
			return Dictionary(raw_entry).duplicate(true)
	return {}


static func _failure(
	code: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
