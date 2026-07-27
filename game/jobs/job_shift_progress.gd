class_name JobShiftProgress
extends RefCounted

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")

const SCHEMA_VERSION := 1
const STATUSES := ["active", "completed"]
const SCORE_FIELDS := ["production", "quality", "safety"]


static func validate(value: Variant, snapshot: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["JobShiftProgress должен быть объектом"]}
	var progress: Dictionary = value
	_expect_keys(progress, [
		"schema_version", "shift_id", "job_id", "status", "next_step_index", "scores",
		"completed_steps", "practiced_task_class_ids", "result",
	], "progress", errors)
	for raw: Variant in Array(JsonValidator.validate(progress, "progress").get("errors", [])):
		errors.append(String(raw))
	if progress.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("progress.schema_version должен быть равен %d" % SCHEMA_VERSION)
	for field: String in ["shift_id", "job_id"]:
		if typeof(progress.get(field, null)) != TYPE_STRING or String(progress.get(field, "")).is_empty():
			errors.append("progress.%s не задан" % field)
	if String(progress.get("status", "")) not in STATUSES:
		errors.append("progress.status неизвестен")
	var completed: Variant = progress.get("completed_steps", null)
	var next_index: Variant = progress.get("next_step_index", null)
	if typeof(next_index) != TYPE_INT or int(next_index) < 0:
		errors.append("progress.next_step_index должен быть неотрицательным целым числом")
	_validate_scores(progress.get("scores", null), "progress.scores", errors)
	_validate_completed(completed, errors)
	_validate_practice(progress.get("practiced_task_class_ids", null), errors)
	if not progress.get("result", null) is Dictionary:
		errors.append("progress.result должен быть объектом")
	elif completed is Array and typeof(next_index) == TYPE_INT:
		if int(next_index) != completed.size():
			errors.append("progress.next_step_index должен совпадать с числом завершённых шагов")
		if String(progress.get("status", "")) == "completed":
			_validate_result(Dictionary(progress["result"]), progress, errors)
		elif not Dictionary(progress["result"]).is_empty():
			errors.append("progress.result заполняется только после завершения смены")
	if not snapshot.is_empty():
		_validate_against_snapshot(progress, snapshot, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_against_snapshot(progress: Dictionary, snapshot: Dictionary, errors: Array[String]) -> void:
	var snapshot_validation := SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("ok", false)):
		errors.append("snapshot для progress некорректен")
		return
	if progress.get("shift_id") != snapshot.get("shift_id") or progress.get("job_id") != snapshot.get("job_id"):
		errors.append("progress относится к другой смене")
	var steps: Array = snapshot["steps"]
	var completed: Array = progress.get("completed_steps", [])
	var next_index: Variant = progress.get("next_step_index", null)
	if typeof(next_index) != TYPE_INT or int(next_index) != completed.size() or int(next_index) < 0 or int(next_index) > steps.size():
		errors.append("progress.next_step_index не совпадает с завершёнными шагами")
	for index: int in mini(completed.size(), steps.size()):
		if not completed[index] is Dictionary:
			continue
		var completion: Dictionary = completed[index]
		var step: Dictionary = steps[index]
		if completion.get("step_id") != step.get("step_id"):
			errors.append("progress.completed_steps[%d] нарушает порядок snapshot" % index)
		for field: String in ["kind", "content_id", "task_class_id"]:
			if completion.get(field, "") != step.get(field, ""):
				errors.append("progress.completed_steps[%d].%s не совпадает со snapshot" % [index, field])
		if not _has_choice(Array(step.get("choices", [])), String(completion.get("choice_id", ""))):
			errors.append("progress.completed_steps[%d].choice_id отсутствует в snapshot" % index)
	_validate_score_chain(progress, completed, errors)
	_validate_practice_chain(progress, completed, errors)
	var completed_status := String(progress.get("status", "")) == "completed"
	if completed_status != (completed.size() == steps.size()):
		errors.append("progress.status не соответствует числу завершённых шагов")


static func _validate_completed(value: Variant, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("progress.completed_steps должен быть массивом")
		return
	var ids: Dictionary = {}
	for index: int in value.size():
		var raw: Variant = value[index]
		var path := "progress.completed_steps[%d]" % index
		if not raw is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var step_id := String(raw.get("step_id", ""))
		_expect_keys(raw, [
			"step_id", "kind", "content_id", "choice_id", "choice_title", "outcome",
			"task_class_id", "competence_modifier", "affinity_modifier", "score_deltas", "scores_after",
		], path, errors)
		if step_id.is_empty() or ids.has(step_id):
			errors.append("%s.step_id пуст или повторяется" % path)
		ids[step_id] = true
		for field: String in ["kind", "content_id", "choice_id", "choice_title", "outcome"]:
			if typeof(raw.get(field, null)) != TYPE_STRING or String(raw.get(field, "")).strip_edges().is_empty():
				errors.append("%s.%s не задан" % [path, field])
		if String(raw.get("kind", "")) == "task" and String(raw.get("task_class_id", "")).is_empty():
			errors.append("%s.task_class_id не задан" % path)
		_validate_scores(raw.get("score_deltas", null), "%s.score_deltas" % path, errors, -30, 30)
		_validate_scores(raw.get("scores_after", null), "%s.scores_after" % path, errors)
		if typeof(raw.get("competence_modifier", null)) != TYPE_INT or absi(int(raw.get("competence_modifier", 0))) > 3:
			errors.append("%s.competence_modifier должен быть целым числом -3..3" % path)
		if typeof(raw.get("affinity_modifier", null)) != TYPE_INT or absi(int(raw.get("affinity_modifier", 0))) > 3:
			errors.append("%s.affinity_modifier должен быть целым числом -3..3" % path)


static func _validate_practice(value: Variant, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("progress.practiced_task_class_ids должен быть массивом")
		return
	var seen: Dictionary = {}
	for raw: Variant in value:
		var identifier := String(raw)
		if identifier.is_empty() or seen.has(identifier):
			errors.append("progress.practiced_task_class_ids содержит пустой или повторный ID")
			return
		seen[identifier] = true


static func _validate_result(result: Dictionary, progress: Dictionary, errors: Array[String]) -> void:
	_expect_keys(result, [
		"shift_id", "job_id", "production", "quality", "safety", "overall", "grade",
		"payout_basis_points", "base_payout_ard", "practiced_task_class_ids",
	], "progress.result", errors)
	for field: String in ["shift_id", "job_id", "grade"]:
		if typeof(result.get(field, null)) != TYPE_STRING or String(result.get(field, "")).is_empty():
			errors.append("progress.result.%s не задан" % field)
	if result.get("shift_id") != progress.get("shift_id") or result.get("job_id") != progress.get("job_id"):
		errors.append("progress.result относится к другой смене")
	for field: String in SCORE_FIELDS + ["overall"]:
		_integer(result.get(field, null), 0, 100, "progress.result.%s" % field, errors)
	for field: String in SCORE_FIELDS:
		if result.get(field, null) != Dictionary(progress.get("scores", {})).get(field, null):
			errors.append("progress.result.%s не совпадает с итоговым progress.scores" % field)
	_integer(result.get("payout_basis_points", null), 0, 20_000, "progress.result.payout_basis_points", errors)
	_integer(result.get("base_payout_ard", null), 180, 300, "progress.result.base_payout_ard", errors)
	if result.get("practiced_task_class_ids", null) != progress.get("practiced_task_class_ids", null):
		errors.append("progress.result.practiced_task_class_ids не совпадает с практикой смены")


static func _validate_scores(
	value: Variant,
	path: String,
	errors: Array[String],
	minimum: int = 0,
	maximum: int = 100
) -> void:
	if not value is Dictionary:
		errors.append("%s должен быть объектом" % path)
		return
	if Dictionary(value).size() != SCORE_FIELDS.size():
		errors.append("%s должен содержать ровно три показателя" % path)
	for field: String in SCORE_FIELDS:
		_integer(value.get(field, null), minimum, maximum, "%s.%s" % [path, field], errors)


static func _validate_score_chain(progress: Dictionary, completed: Array, errors: Array[String]) -> void:
	var expected := {"production": 50, "quality": 50, "safety": 50}
	for index: int in completed.size():
		if not completed[index] is Dictionary:
			continue
		var completion: Dictionary = completed[index]
		if not completion.get("score_deltas", null) is Dictionary:
			continue
		var deltas: Dictionary = completion["score_deltas"]
		for field: String in SCORE_FIELDS:
			expected[field] = clampi(int(expected[field]) + int(deltas.get(field, 0)), 0, 100)
		if completion.get("scores_after", null) != expected:
			errors.append("progress.completed_steps[%d].scores_after нарушает цепочку счёта" % index)
	if progress.get("scores", null) != expected:
		errors.append("progress.scores не совпадает с цепочкой завершённых шагов")


static func _validate_practice_chain(progress: Dictionary, completed: Array, errors: Array[String]) -> void:
	var expected: Array = []
	for raw: Variant in completed:
		if not raw is Dictionary or String(raw.get("kind", "")) != "task":
			continue
		var task_class_id := String(raw.get("task_class_id", ""))
		if not task_class_id.is_empty() and task_class_id not in expected:
			expected.append(task_class_id)
	if progress.get("practiced_task_class_ids", null) != expected:
		errors.append("progress.practiced_task_class_ids не соответствует выполненным задачам")


static func _has_choice(choices: Array, choice_id: String) -> bool:
	for raw: Variant in choices:
		if raw is Dictionary and String(raw.get("id", "")) == choice_id:
			return true
	return false


static func _integer(value: Variant, minimum: int, maximum: int, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_INT or int(value) < minimum or int(value) > maximum:
		errors.append("%s должен быть целым числом %d..%d" % [path, minimum, maximum])


static func _expect_keys(value: Dictionary, allowed: Array, path: String, errors: Array[String]) -> void:
	for raw_key: Variant in value:
		if String(raw_key) not in allowed:
			errors.append("%s содержит неизвестное поле %s" % [path, String(raw_key)])
