class_name JobShiftGenerator
extends RefCounted

const RngScript := preload("res://core/random/deterministic_rng.gd")
const CatalogScript := preload("res://game/jobs/job_shift_catalog.gd")
const SeedScript := preload("res://game/jobs/job_shift_seed.gd")
const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")


static func generate(catalog: Dictionary, job_id: String, run_seed: int, sequence: int) -> Dictionary:
	var catalog_validation := CatalogScript.validate(catalog)
	if not bool(catalog_validation.get("ok", false)):
		return _failure("invalid_catalog", catalog_validation.get("errors", []))
	if sequence < 1:
		return _failure("invalid_sequence", ["sequence должен быть не меньше 1"])
	var job := CatalogScript.find_job(catalog, job_id)
	if job.is_empty():
		return _failure("unknown_job", ["Работа %s не найдена" % job_id])
	var catalog_version := int(catalog["schema_version"])
	var derived_seed := SeedScript.derive(run_seed, job_id, sequence, catalog_version)
	var rng: DeterministicRng = RngScript.new(derived_seed)
	var task_count_range: Array = job["tasks_per_shift"]
	var task_count := rng.next_int(int(task_count_range[0]), int(task_count_range[1]))
	var classes := _rotated_classes(Array(job["task_class_ids"]), sequence, rng)
	var shift_id := "job_shift:%s:%06d:v%d" % [job_id, sequence, catalog_version]
	var steps: Array = []
	for index: int in task_count:
		var task_class_id := String(classes[index])
		var pool := CatalogScript.tasks_for_class(catalog, task_class_id)
		if pool.is_empty():
			return _failure("missing_task_class", ["Нет задачи для %s" % task_class_id])
		steps.append(_task_step(pool[rng.next_int(0, pool.size() - 1)], shift_id, index))
	var decisions := CatalogScript.decisions(catalog)
	if decisions.is_empty():
		return _failure("missing_decision", ["В каталоге нет значимого решения"])
	steps.append(_decision_step(decisions[rng.next_int(0, decisions.size() - 1)], shift_id, steps.size()))
	var snapshot := {
		"schema_version": int(catalog["snapshot_schema_version"]),
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_schema_version": catalog_version,
		"shift_id": shift_id,
		"job_id": job_id,
		"sequence": sequence,
		"seed": {
			"run_seed": str(run_seed),
			"derived_seed": str(derived_seed),
			"stream_id": SeedScript.stream_id(job_id, sequence, catalog_version),
		},
		"briefing": {
			"title": String(job["briefing_title"]),
			"text": String(job["briefing"]),
			"supervisor_npc_id": String(job["supervisor_npc_id"]),
		},
		"duration_minutes": int(job["duration_minutes"]),
		"base_payout_ard": int(job["base_payout_ard"]),
		"steps": steps,
	}
	var validation := SnapshotScript.validate(snapshot)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_snapshot", validation.get("errors", []))
	return {"ok": true, "code": "ok", "snapshot": snapshot.duplicate(true), "errors": []}


static func _rotated_classes(source: Array, sequence: int, rng: DeterministicRng) -> Array:
	var result: Array = []
	var start := (sequence - 1) % source.size()
	var direction := 1 if rng.next_int(0, 1) == 0 else -1
	for offset: int in source.size():
		result.append(source[posmod(start + offset * direction, source.size())])
	return result


static func _task_step(task: Dictionary, shift_id: String, order: int) -> Dictionary:
	return {
		"step_id": "%s:step:%02d" % [shift_id, order],
		"order": order,
		"kind": "task",
		"content_id": String(task["id"]),
		"task_class_id": String(task["task_class_id"]),
		"title": String(task["title"]),
		"description": String(task["description"]),
		"attribute_id": String(task["attribute_id"]),
		"skill_id": String(task["skill_id"]),
		"difficulty": int(task["difficulty"]),
		"choices": Array(task["choices"]).duplicate(true),
	}


static func _decision_step(decision: Dictionary, shift_id: String, order: int) -> Dictionary:
	return {
		"step_id": "%s:step:%02d" % [shift_id, order],
		"order": order,
		"kind": "decision",
		"content_id": String(decision["id"]),
		"title": String(decision["title"]),
		"description": String(decision["description"]),
		"choices": Array(decision["choices"]).duplicate(true),
	}


static func _failure(code: String, raw_errors: Variant) -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(raw_errors):
		errors.append(String(raw))
	return {"ok": false, "code": code, "snapshot": {}, "errors": errors}
