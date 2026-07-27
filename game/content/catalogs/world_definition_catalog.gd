class_name WorldDefinitionCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")
const ProcessDefinitionValidator := preload(
	"res://game/world/world_process_definition_validator.gd"
)

const PREVIOUS_SCHEMA_VERSION := 1
const SCHEMA_VERSION := 2
const CATALOG_ID := "world_definition_catalog_v2"
const PREVIOUS_PATH := "res://game/content/data/world_definition_catalog_v1.json"
const DEFAULT_PATH := "res://game/content/data/world_definition_catalog_v2.json"
const KNOWN_SCOPE_KINDS := ["location", "district", "organization"]
const KNOWN_LOCATION_IDS := [
	"underpass", "market", "station_square", "recycling_point", "clinic_yard", "embankment",
]
const OBSERVABLE_KINDS := [
	"location", "npc", "job", "fact", "metric", "reputation",
]


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var metrics := Rules.index_entries(
		catalog.get("metrics", null), "metrics", "metric_", errors
	)
	var facts := Rules.index_entries(catalog.get("facts", null), "facts", "fact_", errors)
	var processes := Rules.index_entries(
		catalog.get("processes", null), "processes", "process_", errors
	)
	_validate_metrics(metrics, errors)
	_validate_facts(facts, errors)
	for process_id: String in processes:
		_validate_process(Dictionary(processes[process_id]), process_id, facts, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_metrics(metrics: Dictionary, errors: Array[String]) -> void:
	for metric_id: String in metrics:
		var metric: Dictionary = metrics[metric_id]
		var path := "metrics.%s" % metric_id
		Rules.validate_text(metric.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(metric.get("description", null), "%s.description" % path, errors)
		if String(metric.get("scope_kind", "")) != "district":
			errors.append("%s.scope_kind должен быть district" % path)
		if String(metric.get("scope_id", "")) != "riverside_central":
			errors.append("%s.scope_id должен быть riverside_central" % path)
		Rules.validate_int_range(metric.get("minimum", null), 0, 0, "%s.minimum" % path, errors)
		Rules.validate_int_range(metric.get("maximum", null), 100, 100, "%s.maximum" % path, errors)
		Rules.validate_int_range(metric.get("default", null), 0, 100, "%s.default" % path, errors)


static func _validate_facts(facts: Dictionary, errors: Array[String]) -> void:
	for fact_id: String in facts:
		var fact: Dictionary = facts[fact_id]
		var path := "facts.%s" % fact_id
		Rules.validate_text(fact.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(fact.get("description", null), "%s.description" % path, errors)
		_validate_scope(fact, path, errors)
		if String(fact.get("value_type", "")) != "boolean":
			errors.append("%s.value_type должен быть boolean" % path)
		if typeof(fact.get("default", null)) != TYPE_BOOL:
			errors.append("%s.default должен быть булевым" % path)


static func _validate_scope(definition: Dictionary, path: String, errors: Array[String]) -> void:
	var scope_kind := String(definition.get("scope_kind", ""))
	var scope_id := String(definition.get("scope_id", ""))
	if scope_kind not in KNOWN_SCOPE_KINDS:
		errors.append("%s.scope_kind неизвестен" % path)
	elif scope_kind == "location" and scope_id not in KNOWN_LOCATION_IDS:
		errors.append("%s.scope_id ссылается на неизвестную локацию" % path)
	elif scope_kind == "district" and scope_id != "riverside_central":
		errors.append("%s.scope_id ссылается на неизвестный район" % path)
	elif scope_kind == "organization" and not scope_id.begins_with("org_"):
		errors.append("%s.scope_id должен быть org_ ID" % path)


static func _validate_process(
	process: Dictionary,
	process_id: String,
	facts: Dictionary,
	errors: Array[String]
) -> void:
	var path := "processes.%s" % process_id
	Rules.validate_text(process.get("title", null), "%s.title" % path, errors)
	Rules.validate_text(process.get("description", null), "%s.description" % path, errors)
	_validate_scope(process, path, errors)
	var stages := Rules.index_entries(process.get("stages", null), "%s.stages" % path, "", errors)
	var transitions := Rules.index_entries(
		process.get("transitions", null), "%s.transitions" % path, "transition_", errors
	)
	var initial_stage_id := String(process.get("initial_stage_id", ""))
	if not stages.has(initial_stage_id):
		errors.append("%s.initial_stage_id ссылается на неизвестную стадию" % path)
	var terminal_ids := Rules.validate_id_array(
		process.get("terminal_stage_ids", null), "%s.terminal_stage_ids" % path, errors, true
	)
	for stage_id: String in terminal_ids:
		if not stages.has(stage_id):
			errors.append("%s содержит неизвестную терминальную стадию %s" % [path, stage_id])
	_validate_stages(stages, terminal_ids, path, errors)
	_validate_transitions(transitions, stages, facts, path, errors)
	ProcessDefinitionValidator.validate(
		process,
		stages,
		transitions,
		facts,
		path,
		errors
	)
	_validate_graph(stages, transitions, initial_stage_id, terminal_ids, path, errors)


static func _validate_stages(
	stages: Dictionary,
	terminal_ids: Array[String],
	path: String,
	errors: Array[String]
) -> void:
	for stage_id: String in stages:
		var stage: Dictionary = stages[stage_id]
		var stage_path := "%s.stages.%s" % [path, stage_id]
		Rules.validate_text(stage.get("title", null), "%s.title" % stage_path, errors)
		if typeof(stage.get("terminal", null)) != TYPE_BOOL:
			errors.append("%s.terminal должен быть булевым" % stage_path)
		elif bool(stage.get("terminal", false)) != (stage_id in terminal_ids):
			errors.append("%s.terminal расходится с terminal_stage_ids" % stage_path)
		var refs: Variant = stage.get("observable_refs", null)
		if not refs is Array or refs.size() < 2:
			errors.append("%s.observable_refs должен содержать минимум два следа" % stage_path)
			continue
		for index: int in refs.size():
			var raw_ref: Variant = refs[index]
			if not raw_ref is Dictionary:
				errors.append("%s.observable_refs[%d] должен быть объектом" % [stage_path, index])
				continue
			if String(raw_ref.get("kind", "")) not in OBSERVABLE_KINDS:
				errors.append("%s.observable_refs[%d].kind неизвестен" % [stage_path, index])
			if not Rules.valid_id(raw_ref.get("id", null)):
				errors.append("%s.observable_refs[%d].id некорректен" % [stage_path, index])


static func _validate_transitions(
	transitions: Dictionary,
	stages: Dictionary,
	facts: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var edge_keys: Dictionary = {}
	for transition_id: String in transitions:
		var transition: Dictionary = transitions[transition_id]
		var transition_path := "%s.transitions.%s" % [path, transition_id]
		var from_id := String(transition.get("from_stage_id", ""))
		var to_id := String(transition.get("to_stage_id", ""))
		if not stages.has(from_id):
			errors.append("%s.from_stage_id неизвестен" % transition_path)
		if not stages.has(to_id):
			errors.append("%s.to_stage_id неизвестен" % transition_path)
		var edge_key := "%s>%s" % [from_id, to_id]
		if edge_keys.has(edge_key):
			errors.append("%s повторяет переход %s" % [transition_path, edge_key])
		edge_keys[edge_key] = true
		if not Rules.valid_id(transition.get("trigger_id", null)):
			errors.append("%s.trigger_id некорректен" % transition_path)
		for field: String in ["required_fact_ids", "excluded_fact_ids"]:
			var fact_ids := Rules.validate_id_array(
				transition.get(field, []), "%s.%s" % [transition_path, field], errors
			)
			for fact_id: String in fact_ids:
				if not facts.has(fact_id):
					errors.append("%s.%s ссылается на неизвестный факт %s" % [transition_path, field, fact_id])


static func _validate_graph(
	stages: Dictionary,
	transitions: Dictionary,
	initial_id: String,
	terminal_ids: Array[String],
	path: String,
	errors: Array[String]
) -> void:
	if not stages.has(initial_id):
		return
	var outgoing: Dictionary = {}
	for stage_id: String in stages:
		outgoing[stage_id] = []
	for transition_id: String in transitions:
		var transition: Dictionary = transitions[transition_id]
		var from_id := String(transition.get("from_stage_id", ""))
		var to_id := String(transition.get("to_stage_id", ""))
		if stages.has(from_id) and stages.has(to_id):
			var targets: Array = outgoing[from_id]
			targets.append(to_id)
			outgoing[from_id] = targets
	var visited: Dictionary = {}
	var queue: Array[String] = [initial_id]
	while not queue.is_empty():
		var stage_id: String = queue.pop_front()
		if visited.has(stage_id):
			continue
		visited[stage_id] = true
		for target: String in outgoing.get(stage_id, []):
			if not visited.has(target):
				queue.append(target)
	for stage_id: String in stages:
		if not visited.has(stage_id):
			errors.append("%s: стадия %s недостижима" % [path, stage_id])
		var targets: Array = outgoing.get(stage_id, [])
		if stage_id in terminal_ids and not targets.is_empty():
			errors.append("%s: терминальная стадия %s имеет исходящий переход" % [path, stage_id])
		elif stage_id not in terminal_ids and targets.is_empty():
			errors.append("%s: нетерминальная стадия %s является тупиком" % [path, stage_id])


static func processes(catalog: Dictionary) -> Array:
	return Array(catalog.get("processes", [])).duplicate(true)
