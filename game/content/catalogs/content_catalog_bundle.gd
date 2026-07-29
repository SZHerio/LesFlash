class_name ContentCatalogBundle
extends RefCounted

## Loads the read-only M3F.1 definition catalogs and validates references that
## cross catalog boundaries. Runtime state deliberately does not live here.

const Rules := preload("res://game/content/catalogs/catalog_rules.gd")
const KnowledgeCatalog := preload("res://game/content/catalogs/knowledge_catalog.gd")
const NpcCatalog := preload("res://game/content/catalogs/npc_catalog.gd")
const ReputationCatalog := preload("res://game/content/catalogs/reputation_catalog.gd")
const JobCatalog := preload("res://game/content/catalogs/job_catalog.gd")
const WorldCatalog := preload("res://game/content/catalogs/world_definition_catalog.gd")

## One list, in CityPlaces. Six catalogs used to carry their own copy of this.
const KNOWN_LOCATION_IDS := CityPlaces.PLACES


static func load_default() -> Dictionary:
	var errors: Array[String] = []
	var catalogs: Dictionary = {}
	_load_one("knowledge", KnowledgeCatalog.load_default(), catalogs, errors)
	_load_one("npcs", NpcCatalog.load_default(), catalogs, errors)
	_load_one("reputations", ReputationCatalog.load_default(), catalogs, errors)
	_load_one("jobs", JobCatalog.load_default(), catalogs, errors)
	_load_one("world", WorldCatalog.load_default(), catalogs, errors)
	if not errors.is_empty():
		return {"ok": false, "catalogs": {}, "errors": errors}
	var validation := validate(catalogs)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "catalogs": {}, "errors": validation.get("errors", [])}
	return {"ok": true, "catalogs": catalogs.duplicate(true), "errors": []}


static func validate(catalogs: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var knowledge := _catalog(catalogs, "knowledge", errors)
	var npcs := _catalog(catalogs, "npcs", errors)
	var reputations := _catalog(catalogs, "reputations", errors)
	var jobs := _catalog(catalogs, "jobs", errors)
	var world := _catalog(catalogs, "world", errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	Rules.append_errors("knowledge", KnowledgeCatalog.validate(knowledge), errors)
	Rules.append_errors("npcs", NpcCatalog.validate(npcs), errors)
	Rules.append_errors("reputations", ReputationCatalog.validate(reputations), errors)
	Rules.append_errors("jobs", JobCatalog.validate(jobs), errors)
	Rules.append_errors("world", WorldCatalog.validate(world), errors)
	if errors.is_empty():
		_validate_cross_references(knowledge, npcs, reputations, jobs, world, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _load_one(
	key: String,
	loaded: Dictionary,
	catalogs: Dictionary,
	errors: Array[String]
) -> void:
	if not bool(loaded.get("ok", false)):
		Rules.append_errors(key, loaded, errors)
		return
	catalogs[key] = Dictionary(loaded.get("catalog", {})).duplicate(true)


static func _catalog(
	catalogs: Dictionary,
	key: String,
	errors: Array[String]
) -> Dictionary:
	var value: Variant = catalogs.get(key, null)
	if not value is Dictionary:
		errors.append("catalogs.%s должен быть объектом каталога" % key)
		return {}
	return Dictionary(value)


static func _validate_cross_references(
	knowledge: Dictionary,
	npcs: Dictionary,
	reputations: Dictionary,
	jobs: Dictionary,
	world: Dictionary,
	errors: Array[String]
) -> void:
	var indexes := {
		"knowledge": _index(knowledge.get("knowledge", [])),
		"npc": _index(npcs.get("npcs", [])),
		"reputation": _index(reputations.get("reputations", [])),
		"audience": _index(reputations.get("audiences", [])),
		"job": _index(jobs.get("jobs", [])),
		"fact": _index(world.get("facts", [])),
		"metric": _index(world.get("metrics", [])),
		"world_process": _index(world.get("processes", [])),
	}
	_validate_npc_refs(npcs, indexes, errors)
	_validate_job_refs(jobs, indexes, errors)
	_validate_world_refs(world, indexes, errors)


static func _validate_npc_refs(
	catalog: Dictionary,
	indexes: Dictionary,
	errors: Array[String]
) -> void:
	for raw_npc: Variant in catalog.get("npcs", []):
		var npc: Dictionary = raw_npc
		var npc_id := String(npc.get("id", ""))
		for index: int in Array(npc.get("appearance_refs", [])).size():
			var ref: Dictionary = npc.get("appearance_refs", [])[index]
			var kind := String(ref.get("kind", ""))
			var ref_id := String(ref.get("id", ""))
			var path := "npcs.%s.appearance_refs[%d]" % [npc_id, index]
			if kind == "location":
				if ref_id not in KNOWN_LOCATION_IDS:
					errors.append("%s ссылается на неизвестную локацию %s" % [path, ref_id])
				continue
			var index_key := "metric" if kind == "world_metric" else kind
			if not indexes.has(index_key) or not Dictionary(indexes[index_key]).has(ref_id):
				errors.append("%s ссылается на неизвестный %s ID %s" % [path, kind, ref_id])


static func _validate_job_refs(
	catalog: Dictionary,
	indexes: Dictionary,
	errors: Array[String]
) -> void:
	var knowledge_index: Dictionary = indexes["knowledge"]
	var fact_index: Dictionary = indexes["fact"]
	for raw_task: Variant in catalog.get("task_classes", []):
		var task: Dictionary = raw_task
		var task_id := String(task.get("id", ""))
		_validate_ids_exist(
			task.get("knowledge_ids", []),
			knowledge_index,
			"task_classes.%s.knowledge_ids" % task_id,
			errors
		)
		_validate_ids_exist(
			task.get("world_fact_ids", []),
			fact_index,
			"task_classes.%s.world_fact_ids" % task_id,
			errors
		)
	for raw_job: Variant in catalog.get("jobs", []):
		var job: Dictionary = raw_job
		var job_id := String(job.get("id", ""))
		_validate_ref(
			String(job.get("supervisor_npc_id", "")),
			indexes["npc"],
			"jobs.%s.supervisor_npc_id" % job_id,
			errors
		)
		_validate_ref(
			String(job.get("organization_id", "")),
			indexes["audience"],
			"jobs.%s.organization_id" % job_id,
			errors
		)
		_validate_ids_exist(
			job.get("process_ids", []),
			indexes["world_process"],
			"jobs.%s.process_ids" % job_id,
			errors
		)


static func _validate_world_refs(
	catalog: Dictionary,
	indexes: Dictionary,
	errors: Array[String]
) -> void:
	for raw_fact: Variant in catalog.get("facts", []):
		var fact: Dictionary = raw_fact
		if String(fact.get("scope_kind", "")) == "organization":
			_validate_ref(
				String(fact.get("scope_id", "")),
				indexes["audience"],
				"facts.%s.scope_id" % String(fact.get("id", "")),
				errors
			)
	for raw_process: Variant in catalog.get("processes", []):
		var process: Dictionary = raw_process
		var process_id := String(process.get("id", ""))
		if String(process.get("scope_kind", "")) == "organization":
			_validate_ref(
				String(process.get("scope_id", "")),
				indexes["audience"],
				"processes.%s.scope_id" % process_id,
				errors
			)
		for raw_stage: Variant in process.get("stages", []):
			var stage: Dictionary = raw_stage
			var stage_id := String(stage.get("id", ""))
			for index: int in Array(stage.get("observable_refs", [])).size():
				var ref: Dictionary = stage.get("observable_refs", [])[index]
				_validate_observable_ref(ref, process_id, stage_id, index, indexes, errors)


static func _validate_observable_ref(
	ref: Dictionary,
	process_id: String,
	stage_id: String,
	ref_index: int,
	indexes: Dictionary,
	errors: Array[String]
) -> void:
	var kind := String(ref.get("kind", ""))
	var ref_id := String(ref.get("id", ""))
	var path := "processes.%s.stages.%s.observable_refs[%d]" % [
		process_id, stage_id, ref_index,
	]
	if kind == "location":
		if ref_id not in KNOWN_LOCATION_IDS:
			errors.append("%s ссылается на неизвестную локацию %s" % [path, ref_id])
		return
	if not indexes.has(kind) or not Dictionary(indexes[kind]).has(ref_id):
		errors.append("%s ссылается на неизвестный %s ID %s" % [path, kind, ref_id])


static func _validate_ids_exist(
	raw_ids: Variant,
	known: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	for raw_id: Variant in raw_ids:
		_validate_ref(String(raw_id), known, path, errors)


static func _validate_ref(
	ref_id: String,
	known: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	if not known.has(ref_id):
		errors.append("%s ссылается на неизвестный ID %s" % [path, ref_id])


static func _index(raw_entries: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_entries is Array:
		return result
	for raw_entry: Variant in raw_entries:
		if raw_entry is Dictionary:
			result[String(raw_entry.get("id", ""))] = true
	return result
