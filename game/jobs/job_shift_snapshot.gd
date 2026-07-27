class_name JobShiftSnapshot
extends RefCounted

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")
const SeedScript := preload("res://game/jobs/job_shift_seed.gd")

const SCHEMA_VERSION := 1
const SCORE_FIELDS := ["production", "quality", "safety"]
const STEP_KINDS := ["task", "decision"]


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["JobShiftSnapshot должен быть объектом"]}
	var snapshot: Dictionary = value
	_append_json_errors(snapshot, errors)
	_expect_keys(snapshot, [
		"schema_version", "catalog_id", "catalog_schema_version", "shift_id", "job_id",
		"sequence", "seed", "briefing", "duration_minutes", "base_payout_ard", "steps",
	], "snapshot", errors)
	if snapshot.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("snapshot.schema_version должен быть равен %d" % SCHEMA_VERSION)
	if String(snapshot.get("catalog_id", "")) != "job_shift_catalog_v1":
		errors.append("snapshot.catalog_id неизвестен")
	if snapshot.get("catalog_schema_version", null) != 1:
		errors.append("snapshot.catalog_schema_version должен быть равен 1")
	for field: String in ["shift_id", "job_id"]:
		if typeof(snapshot.get(field, null)) != TYPE_STRING or String(snapshot.get(field, "")).is_empty():
			errors.append("snapshot.%s не задан" % field)
	if String(snapshot.get("job_id", "")) != "job_recycling_sorter":
		errors.append("snapshot.job_id должен быть job_recycling_sorter")
	_integer(snapshot.get("sequence", null), 1, 1_000_000, "snapshot.sequence", errors)
	_validate_seed(snapshot.get("seed", null), errors)
	_validate_identity(snapshot, errors)
	_validate_briefing(snapshot.get("briefing", null), errors)
	_integer(snapshot.get("duration_minutes", null), 60, 720, "snapshot.duration_minutes", errors)
	_integer(snapshot.get("base_payout_ard", null), 180, 300, "snapshot.base_payout_ard", errors)
	_validate_steps(snapshot.get("steps", null), String(snapshot.get("shift_id", "")), errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func initial_progress(snapshot: Dictionary) -> Dictionary:
	var validation := validate(snapshot)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "code": "invalid_snapshot", "errors": validation.get("errors", [])}
	return {
		"ok": true,
		"progress": {
			"schema_version": 1,
			"shift_id": String(snapshot["shift_id"]),
			"job_id": String(snapshot["job_id"]),
			"status": "active",
			"next_step_index": 0,
			"scores": {"production": 50, "quality": 50, "safety": 50},
			"completed_steps": [],
			"practiced_task_class_ids": [],
			"result": {},
		}
	}


static func _validate_seed(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.seed должен быть объектом")
		return
	_expect_keys(value, ["run_seed", "derived_seed", "stream_id"], "snapshot.seed", errors)
	for field: String in ["run_seed", "derived_seed"]:
		var text := String(value.get(field, ""))
		if not text.is_valid_int():
			errors.append("snapshot.seed.%s должен быть точной целочисленной строкой" % field)
	if String(value.get("stream_id", "")).strip_edges().is_empty():
		errors.append("snapshot.seed.stream_id не задан")


static func _validate_briefing(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.briefing должен быть объектом")
		return
	_expect_keys(value, ["title", "text", "supervisor_npc_id"], "snapshot.briefing", errors)
	for field: String in ["title", "text", "supervisor_npc_id"]:
		if typeof(value.get(field, null)) != TYPE_STRING or String(value.get(field, "")).strip_edges().is_empty():
			errors.append("snapshot.briefing.%s не задан" % field)


static func _validate_identity(snapshot: Dictionary, errors: Array[String]) -> void:
	if (
		typeof(snapshot.get("sequence", null)) != TYPE_INT
		or typeof(snapshot.get("catalog_schema_version", null)) != TYPE_INT
	):
		return
	var job_id := String(snapshot.get("job_id", ""))
	var sequence := int(snapshot["sequence"])
	var catalog_version := int(snapshot["catalog_schema_version"])
	var expected_shift_id := "job_shift:%s:%06d:v%d" % [job_id, sequence, catalog_version]
	if String(snapshot.get("shift_id", "")) != expected_shift_id:
		errors.append("snapshot.shift_id не соответствует работе, последовательности и версии")
	if not snapshot.get("seed", null) is Dictionary:
		return
	var seed: Dictionary = snapshot["seed"]
	var run_seed_text := String(seed.get("run_seed", ""))
	var derived_seed_text := String(seed.get("derived_seed", ""))
	if run_seed_text.is_valid_int() and derived_seed_text.is_valid_int():
		var expected_seed := SeedScript.derive(int(run_seed_text), job_id, sequence, catalog_version)
		if int(derived_seed_text) != expected_seed:
			errors.append("snapshot.seed.derived_seed не соответствует стабильному материалу")
	var expected_stream := SeedScript.stream_id(job_id, sequence, catalog_version)
	if String(seed.get("stream_id", "")) != expected_stream:
		errors.append("snapshot.seed.stream_id не соответствует смене")


static func _validate_steps(value: Variant, shift_id: String, errors: Array[String]) -> void:
	if not value is Array or value.size() < 3 or value.size() > 4:
		errors.append("snapshot.steps должен содержать 2–3 задачи и одно решение")
		return
	var ids: Dictionary = {}
	var task_classes: Dictionary = {}
	var task_count := 0
	var decision_count := 0
	for index: int in value.size():
		var raw: Variant = value[index]
		var path := "snapshot.steps[%d]" % index
		if not raw is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var step: Dictionary = raw
		var step_id := String(step.get("step_id", ""))
		if step_id.is_empty() or ids.has(step_id) or not step_id.begins_with("%s:step:" % shift_id):
			errors.append("%s.step_id пуст, повторяется или не принадлежит смене" % path)
		else:
			ids[step_id] = true
		if step.get("order", null) != index:
			errors.append("%s.order должен совпадать с индексом" % path)
		var kind := String(step.get("kind", ""))
		if kind not in STEP_KINDS:
			errors.append("%s.kind неизвестен" % path)
		elif kind == "task":
			_expect_keys(step, [
				"step_id", "order", "kind", "content_id", "task_class_id", "title",
				"description", "attribute_id", "skill_id", "difficulty", "choices",
			], path, errors)
			task_count += 1
			var task_class_id := String(step.get("task_class_id", ""))
			if task_class_id.is_empty() or task_classes.has(task_class_id):
				errors.append("%s.task_class_id пуст или повторяется в смене" % path)
			task_classes[task_class_id] = true
			if String(step.get("attribute_id", "")) not in ["strength", "charisma", "intelligence", "luck"]:
				errors.append("%s.attribute_id неизвестен" % path)
			if not Rules.valid_id(String(step.get("skill_id", ""))):
				errors.append("%s.skill_id некорректен" % path)
			_integer(step.get("difficulty", null), 1, 10, "%s.difficulty" % path, errors)
		else:
			_expect_keys(step, [
				"step_id", "order", "kind", "content_id", "title", "description", "choices",
			], path, errors)
			decision_count += 1
			if index != value.size() - 1:
				errors.append("Значимое решение должно завершать смену")
		for field: String in ["content_id", "title", "description"]:
			if typeof(step.get(field, null)) != TYPE_STRING or String(step.get(field, "")).strip_edges().is_empty():
				errors.append("%s.%s не задан" % [path, field])
		_validate_choices(step.get("choices", null), "%s.choices" % path, errors)
	if task_count < 2 or task_count > 3 or decision_count != 1:
		errors.append("snapshot.steps должен содержать 2–3 производственные задачи и ровно одно решение")


static func _validate_choices(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or value.size() < 2:
		errors.append("%s должен быть непустым набором вариантов" % path)
		return
	var ids: Dictionary = {}
	for index: int in value.size():
		var raw: Variant = value[index]
		if not raw is Dictionary:
			errors.append("%s[%d] должен быть объектом" % [path, index])
			continue
		var choice: Dictionary = raw
		_expect_keys(
			choice,
			["id", "title", "description", "scores", "outcome", "polarity_affinity"],
			"%s[%d]" % [path, index],
			errors
		)
		_validate_affinity(choice.get("polarity_affinity", null), "%s[%d]" % [path, index], errors)
		var choice_id := String(choice.get("id", ""))
		if not Rules.valid_id(choice_id) or ids.has(choice_id):
			errors.append("%s[%d].id некорректен или повторяется" % [path, index])
		ids[choice_id] = true
		for field: String in ["title", "description", "outcome"]:
			if typeof(choice.get(field, null)) != TYPE_STRING or String(choice.get(field, "")).strip_edges().is_empty():
				errors.append("%s[%d].%s не задан" % [path, index, field])
		var scores: Variant = choice.get("scores", null)
		if not scores is Dictionary:
			errors.append("%s[%d].scores должен быть объектом" % [path, index])
			continue
		for field: String in SCORE_FIELDS:
			_integer(scores.get(field, null), -25, 25, "%s[%d].scores.%s" % [path, index, field], errors)


static func _append_json_errors(value: Variant, errors: Array[String]) -> void:
	for raw: Variant in Array(JsonValidator.validate(value, "snapshot").get("errors", [])):
		errors.append(String(raw))


static func _integer(value: Variant, minimum: int, maximum: int, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_INT or int(value) < minimum or int(value) > maximum:
		errors.append("%s должен быть целым числом %d..%d" % [path, minimum, maximum])


## Optional: a step's middle option deliberately has none.
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
