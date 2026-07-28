class_name JobShiftCatalogValidator
extends RefCounted

const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "job_shift_catalog_v1"
## Each job declares its own six task classes. Nothing is canonical any more:
## a second profession is a catalog entry, not a code change.
const CLASSES_PER_JOB := 6
const SUPERVISORS := ["npc_viktor_koren", "npc_lidiya_maren", "npc_tamara_roven"]
const ATTRIBUTES := ["strength", "charisma", "intelligence", "luck"]
const SKILLS := ["city_navigation", "cargo_handling", "cooking", "repair", "first_aid", "trade", "search"]
const SCORE_FIELDS := ["production", "quality", "safety"]


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	_expect_keys(catalog, [
		"schema_version", "catalog_id", "snapshot_schema_version", "progress_schema_version",
		"jobs", "tasks", "decisions",
	], "catalog", errors)
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	Rules.validate_int_range(catalog.get("snapshot_schema_version", null), 1, 1, "snapshot_schema_version", errors)
	Rules.validate_int_range(catalog.get("progress_schema_version", null), 1, 1, "progress_schema_version", errors)
	var jobs := Rules.index_entries(catalog.get("jobs", null), "jobs", "job_", errors)
	var tasks := Rules.index_entries(catalog.get("tasks", null), "tasks", "shift_task_", errors)
	var decisions := Rules.index_entries(catalog.get("decisions", null), "decisions", "shift_decision_", errors)
	_validate_jobs(jobs, errors)
	_validate_tasks(tasks, errors)
	_validate_decisions(decisions, errors)
	_validate_reachability(jobs, tasks, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_jobs(jobs: Dictionary, errors: Array[String]) -> void:
	if jobs.is_empty():
		errors.append("jobs должен содержать хотя бы одну работу")
	for job_id: String in jobs:
		var job: Dictionary = jobs[job_id]
		var path := "jobs.%s" % job_id
		_expect_keys(job, [
			"id", "title", "briefing_title", "briefing", "supervisor_npc_id",
			"task_class_ids", "tasks_per_shift", "decisions_per_shift", "duration_minutes",
			"base_payout_ard",
		], path, errors)
		for field: String in ["title", "briefing_title", "briefing"]:
			Rules.validate_text(job.get(field, null), "%s.%s" % [path, field], errors)
		if String(job.get("supervisor_npc_id", "")) not in SUPERVISORS:
			errors.append("%s.supervisor_npc_id должен ссылаться на существующего NPC" % path)
		var classes := Rules.validate_id_array(job.get("task_class_ids", null), "%s.task_class_ids" % path, errors, true)
		if classes.size() != CLASSES_PER_JOB:
			errors.append("%s.task_class_ids должен содержать %d классов" % [path, CLASSES_PER_JOB])
		_validate_pair(job.get("tasks_per_shift", null), 2, 3, "%s.tasks_per_shift" % path, errors)
		Rules.validate_int_range(job.get("decisions_per_shift", null), 1, 1, "%s.decisions_per_shift" % path, errors)
		Rules.validate_int_range(job.get("duration_minutes", null), 60, 720, "%s.duration_minutes" % path, errors)
		Rules.validate_int_range(job.get("base_payout_ard", null), 180, 300, "%s.base_payout_ard" % path, errors)


static func _validate_tasks(tasks: Dictionary, errors: Array[String]) -> void:
	for task_id: String in tasks:
		var task: Dictionary = tasks[task_id]
		var path := "tasks.%s" % task_id
		_expect_keys(task, [
			"id", "task_class_id", "title", "description", "attribute_id", "skill_id",
			"difficulty", "choices",
		], path, errors)
		_validate_step_text(task, path, errors)
		if String(task.get("task_class_id", "")).strip_edges().is_empty():
			errors.append("%s.task_class_id не задан" % path)
		if String(task.get("attribute_id", "")) not in ATTRIBUTES:
			errors.append("%s.attribute_id неизвестен" % path)
		if String(task.get("skill_id", "")) not in SKILLS:
			errors.append("%s.skill_id неизвестен" % path)
		Rules.validate_int_range(task.get("difficulty", null), 1, 10, "%s.difficulty" % path, errors)
		_validate_choices(task.get("choices", null), "%s.choices" % path, errors)


static func _validate_decisions(decisions: Dictionary, errors: Array[String]) -> void:
	if decisions.size() < 2:
		errors.append("decisions должен содержать минимум два значимых решения")
	for decision_id: String in decisions:
		var decision: Dictionary = decisions[decision_id]
		var path := "decisions.%s" % decision_id
		_expect_keys(decision, ["id", "title", "description", "choices"], path, errors)
		_validate_step_text(decision, path, errors)
		_validate_choices(decision.get("choices", null), "%s.choices" % path, errors)


static func _validate_step_text(step: Dictionary, path: String, errors: Array[String]) -> void:
	Rules.validate_text(step.get("title", null), "%s.title" % path, errors)
	Rules.validate_text(step.get("description", null), "%s.description" % path, errors)


static func _validate_choices(value: Variant, path: String, errors: Array[String]) -> void:
	var indexed := Rules.index_entries(value, path, "", errors)
	if indexed.size() < 2 or indexed.size() > 4:
		errors.append("%s должен содержать от двух до четырёх вариантов" % path)
	for choice_id: String in indexed:
		var choice: Dictionary = indexed[choice_id]
		var choice_path := "%s.%s" % [path, choice_id]
		_expect_keys(
			choice,
			["id", "title", "description", "scores", "outcome", "polarity_affinity"],
			choice_path,
			errors
		)
		_validate_affinity(choice.get("polarity_affinity", null), choice_path, errors)
		for field: String in ["title", "description", "outcome"]:
			Rules.validate_text(choice.get(field, null), "%s.%s" % [choice_path, field], errors)
		var scores: Variant = choice.get("scores", null)
		if not scores is Dictionary:
			errors.append("%s.scores должен быть объектом" % choice_path)
			continue
		if Dictionary(scores).size() != SCORE_FIELDS.size():
			errors.append("%s.scores должен содержать только три итоговых показателя" % choice_path)
		for score_id: String in SCORE_FIELDS:
			Rules.validate_int_range(scores.get(score_id, null), -25, 25, "%s.scores.%s" % [choice_path, score_id], errors)


## Every class a job promises must have a task written for it, and no job may
## borrow another job's classes: a shift at the market is not a shift at the yard.
static func _validate_reachability(jobs: Dictionary, tasks: Dictionary, errors: Array[String]) -> void:
	var reachable: Dictionary = {}
	for task_id: String in tasks:
		reachable[String(Dictionary(tasks[task_id]).get("task_class_id", ""))] = true
	var claimed: Dictionary = {}
	for job_id: String in jobs:
		for raw_class: Variant in Array(Dictionary(jobs[job_id]).get("task_class_ids", [])):
			var class_id := String(raw_class)
			if not reachable.has(class_id):
				errors.append("Класс %s недостижим: для него нет производственной задачи" % class_id)
			if claimed.has(class_id):
				errors.append("Класс %s заявлен сразу двумя работами" % class_id)
			claimed[class_id] = job_id


static func _validate_pair(value: Variant, minimum: int, maximum: int, path: String, errors: Array[String]) -> void:
	if not value is Array or value.size() != 2 or value[0] != minimum or value[1] != maximum:
		errors.append("%s должен быть [%d, %d]" % [path, minimum, maximum])


static func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort()
	return result


## Optional by design: the middle option of a step carries no affinity, so a
## hero standing in the centre of every axis gets no bonus and no penalty.
static func _validate_affinity(value: Variant, path: String, errors: Array[String]) -> void:
	if value == null:
		return
	if not value is Dictionary:
		errors.append("%s.polarity_affinity должен быть объектом" % path)
		return
	var affinity: Dictionary = value
	_expect_keys(affinity, ["axis", "direction"], "%s.polarity_affinity" % path, errors)
	if not GameRules.is_stored_polarity(String(affinity.get("axis", ""))):
		errors.append("%s.polarity_affinity.axis не является хранимой полярностью" % path)
	if int(affinity.get("direction", 0)) not in [-1, 1]:
		errors.append("%s.polarity_affinity.direction должен быть -1 или 1" % path)


static func _expect_keys(value: Dictionary, allowed: Array, path: String, errors: Array[String]) -> void:
	for raw_key: Variant in value:
		if String(raw_key) not in allowed:
			errors.append("%s содержит неизвестное поле %s" % [path, String(raw_key)])
