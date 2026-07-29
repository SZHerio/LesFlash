class_name JobMastery
extends RefCounted

## Moderate-grind policy: only newly practiced task classes award mastery.
## Repeating an already known routine may earn wages through integration, but
## it cannot farm mastery. Quick resolve is earned by varied confirmed work.

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const ProgressScript := preload("res://game/jobs/job_shift_progress.gd")

const SCHEMA_VERSION := 1
const QUICK_MIN_SHIFTS := 3
const QUICK_MIN_CLASSES := 4


static func fresh(job_id: String = "job_recycling_sorter") -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"job_id": job_id,
		"completed_shifts": [],
		"practiced_task_class_ids": [],
		"mastery_points": 0,
	}


static func record_completed_shift(history: Dictionary, progress: Dictionary) -> Dictionary:
	var history_validation := validate(history)
	if not bool(history_validation.get("ok", false)):
		return _failure("invalid_history", history_validation.get("errors", []))
	var progress_validation := ProgressScript.validate(progress)
	if not bool(progress_validation.get("ok", false)) or String(progress.get("status", "")) != "completed":
		return _failure("shift_not_completed", ["Освоение фиксируется только после завершённой смены"])
	if String(progress.get("job_id", "")) != String(history.get("job_id", "")):
		return _failure("wrong_job", ["История относится к другой работе"])
	var shift_id := String(progress["shift_id"])
	for raw: Variant in Array(history["completed_shifts"]):
		if raw is Dictionary and String(raw.get("shift_id", "")) == shift_id:
			return {
				"ok": true,
				"code": "already_recorded",
				"history": history.duplicate(true),
				"mastery_awarded": 0,
				"quick_resolve_eligible": quick_resolve_eligible(history),
			}
	var candidate := history.duplicate(true)
	var newly_practiced: Array[String] = []
	var candidate_classes: Array = candidate["practiced_task_class_ids"]
	for raw_class_id: Variant in Array(progress["practiced_task_class_ids"]):
		var task_class_id := String(raw_class_id)
		if task_class_id not in candidate_classes:
			candidate_classes.append(task_class_id)
			newly_practiced.append(task_class_id)
	candidate["mastery_points"] = int(candidate["mastery_points"]) + newly_practiced.size()
	var completed_shifts: Array = candidate["completed_shifts"]
	completed_shifts.append({
		"shift_id": shift_id,
		"task_class_ids": Array(progress["practiced_task_class_ids"]).duplicate(),
		"new_task_class_ids": newly_practiced.duplicate(),
		"overall": int(Dictionary(progress["result"]).get("overall", 0)),
	})
	var validation := validate(candidate)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_candidate", validation.get("errors", []))
	return {
		"ok": true,
		"code": "ok",
		"history": candidate,
		"mastery_awarded": newly_practiced.size(),
		"quick_resolve_eligible": quick_resolve_eligible(candidate),
	}


## The shortcut is earned by having visibly done the job several different ways:
## enough shifts behind you, and enough kinds of task among them.
##
## It used to also demand cargo_handling rank 1. That worked while ranks came
## from repetition, but M5 made a rank grow from *varied* practice — three
## different sources for the first rank — and cargo_handling is reachable from
## exactly one task class per profession. A sorter could work the yard forever
## and never see rank 1, so the shortcut had quietly become content nobody could
## reach. The variety it was standing in for is already what the class count
## measures, so the rank condition is gone rather than propped up.
static func quick_resolve_eligible(history: Dictionary) -> bool:
	return (
		Array(history.get("completed_shifts", [])).size() >= QUICK_MIN_SHIFTS
		and Array(history.get("practiced_task_class_ids", [])).size() >= QUICK_MIN_CLASSES
	)


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["JobMastery должен быть объектом"]}
	var history: Dictionary = value
	_expect_keys(history, [
		"schema_version", "job_id", "completed_shifts", "practiced_task_class_ids", "mastery_points",
	], "job_mastery", errors)
	for raw: Variant in Array(JsonValidator.validate(history, "job_mastery").get("errors", [])):
		errors.append(String(raw))
	if history.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("job_mastery.schema_version должен быть равен %d" % SCHEMA_VERSION)
	if String(history.get("job_id", "")).strip_edges().is_empty():
		errors.append("job_mastery.job_id не задан")
	if not history.get("completed_shifts", null) is Array:
		errors.append("job_mastery.completed_shifts должен быть массивом")
	if not history.get("practiced_task_class_ids", null) is Array:
		errors.append("job_mastery.practiced_task_class_ids должен быть массивом")
	if typeof(history.get("mastery_points", null)) != TYPE_INT or int(history.get("mastery_points", -1)) < 0:
		errors.append("job_mastery.mastery_points должен быть неотрицательным целым числом")
	_validate_uniqueness(history, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_uniqueness(history: Dictionary, errors: Array[String]) -> void:
	var seen_shifts: Dictionary = {}
	var expected_classes: Array = []
	for raw: Variant in Array(history.get("completed_shifts", [])):
		if not raw is Dictionary:
			errors.append("job_mastery.completed_shifts содержит не объект")
			continue
		var shift_id := String(raw.get("shift_id", ""))
		_expect_keys(raw, ["shift_id", "task_class_ids", "new_task_class_ids", "overall"], "job_mastery.completed_shifts", errors)
		if shift_id.is_empty() or seen_shifts.has(shift_id):
			errors.append("job_mastery.completed_shifts содержит пустой или повторный shift_id")
		seen_shifts[shift_id] = true
		if not raw.get("task_class_ids", null) is Array or not raw.get("new_task_class_ids", null) is Array:
			errors.append("job_mastery.completed_shifts требует массивы классов")
			continue
		if typeof(raw.get("overall", null)) != TYPE_INT or int(raw.get("overall", -1)) < 0 or int(raw.get("overall", -1)) > 100:
			errors.append("job_mastery.completed_shifts.overall должен быть 0..100")
		var expected_new: Array = []
		var local_seen: Dictionary = {}
		for raw_class_id: Variant in Array(raw["task_class_ids"]):
			var task_class_id := String(raw_class_id)
			if task_class_id.is_empty() or local_seen.has(task_class_id):
				errors.append("job_mastery.completed_shifts.task_class_ids содержит пустой или повторный ID")
				continue
			local_seen[task_class_id] = true
			if task_class_id not in expected_classes:
				expected_classes.append(task_class_id)
				expected_new.append(task_class_id)
		if raw["new_task_class_ids"] != expected_new:
			errors.append("job_mastery.completed_shifts.new_task_class_ids не соответствует новой практике")
	var seen_classes: Dictionary = {}
	for raw: Variant in Array(history.get("practiced_task_class_ids", [])):
		var task_class_id := String(raw)
		if task_class_id.is_empty() or seen_classes.has(task_class_id):
			errors.append("job_mastery.practiced_task_class_ids содержит пустой или повторный ID")
		seen_classes[task_class_id] = true
	if history.get("practiced_task_class_ids", null) != expected_classes:
		errors.append("job_mastery.practiced_task_class_ids не соответствует истории смен")
	if int(history.get("mastery_points", 0)) != seen_classes.size():
		errors.append("job_mastery.mastery_points должен равняться числу разных освоенных классов")


static func _failure(code: String, raw_errors: Variant) -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(raw_errors):
		errors.append(String(raw))
	return {"ok": false, "code": code, "errors": errors, "history": {}}


static func _expect_keys(value: Dictionary, allowed: Array, path: String, errors: Array[String]) -> void:
	for raw_key: Variant in value:
		if String(raw_key) not in allowed:
			errors.append("%s содержит неизвестное поле %s" % [path, String(raw_key)])
