class_name JobDefinitionCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "job_catalog_v1"
const DEFAULT_PATH := "res://game/content/data/job_catalog_v1.json"
const ACTIVE_SKILL_IDS := [
	"city_navigation", "cargo_handling", "cooking", "repair", "first_aid", "trade", "search",
]
## One list, in CityPlaces. Six catalogs used to carry their own copy of this.
const KNOWN_LOCATION_IDS := CityPlaces.PLACES


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
	var task_classes := Rules.index_entries(
		catalog.get("task_classes", null), "task_classes", "task_", errors
	)
	var jobs := Rules.index_entries(catalog.get("jobs", null), "jobs", "job_", errors)
	_validate_tasks(task_classes, errors)
	_validate_jobs(jobs, task_classes, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_tasks(task_classes: Dictionary, errors: Array[String]) -> void:
	for task_id: String in task_classes:
		var task: Dictionary = task_classes[task_id]
		var path := "task_classes.%s" % task_id
		Rules.validate_text(task.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(task.get("description", null), "%s.description" % path, errors)
		var skill_id := String(task.get("primary_skill_id", ""))
		if skill_id not in ACTIVE_SKILL_IDS:
			errors.append("%s.primary_skill_id неизвестен" % path)
		Rules.validate_id_array(task.get("knowledge_ids", []), "%s.knowledge_ids" % path, errors)
		Rules.validate_id_array(task.get("world_fact_ids", []), "%s.world_fact_ids" % path, errors)
		Rules.validate_id_array(task.get("tags", []), "%s.tags" % path, errors, true)


static func _validate_jobs(
	jobs: Dictionary,
	task_classes: Dictionary,
	errors: Array[String]
) -> void:
	for job_id: String in jobs:
		var job: Dictionary = jobs[job_id]
		var path := "jobs.%s" % job_id
		Rules.validate_text(job.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(job.get("description", null), "%s.description" % path, errors)
		var organization_id := String(job.get("organization_id", ""))
		if not Rules.valid_id(organization_id) or not organization_id.begins_with("org_"):
			errors.append("%s.organization_id должен быть стабильным org_ ID" % path)
		var location_id := String(job.get("location_id", ""))
		if location_id not in KNOWN_LOCATION_IDS:
			errors.append("%s.location_id неизвестен" % path)
		var supervisor_npc_id := String(job.get("supervisor_npc_id", ""))
		if not Rules.valid_id(supervisor_npc_id) or not supervisor_npc_id.begins_with("npc_"):
			errors.append("%s.supervisor_npc_id должен быть стабильным npc_ ID" % path)
		var task_ids := Rules.validate_id_array(
			job.get("task_class_ids", null), "%s.task_class_ids" % path, errors, true
		)
		if task_ids.size() != 6:
			errors.append("%s должен ссылаться ровно на шесть классов задач" % path)
		for task_id: String in task_ids:
			if not task_classes.has(task_id):
				errors.append("%s ссылается на неизвестную задачу %s" % [path, task_id])
		Rules.validate_int_range(
			job.get("tasks_per_shift_min", null), 2, 2, "%s.tasks_per_shift_min" % path, errors
		)
		Rules.validate_int_range(
			job.get("tasks_per_shift_max", null), 3, 3, "%s.tasks_per_shift_max" % path, errors
		)
		Rules.validate_int_range(
			job.get("decisions_per_shift", null), 1, 1, "%s.decisions_per_shift" % path, errors
		)
		Rules.validate_id_array(
			job.get("qualification_ids", null), "%s.qualification_ids" % path, errors
		)
		Rules.validate_id_array(job.get("process_ids", null), "%s.process_ids" % path, errors, true)
	return


static func jobs(catalog: Dictionary) -> Array:
	return Array(catalog.get("jobs", [])).duplicate(true)
