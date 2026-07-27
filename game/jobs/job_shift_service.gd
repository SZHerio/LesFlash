class_name JobShiftService
extends RefCounted

## Pure step resolver. The caller owns the atomic transaction and command
## ledger; this service never mutates the supplied snapshot or progress.

const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")
const ProgressScript := preload("res://game/jobs/job_shift_progress.gd")

const SCORE_FIELDS := ["production", "quality", "safety"]


static func start(snapshot: Dictionary) -> Dictionary:
	return SnapshotScript.initial_progress(snapshot)


static func preview(snapshot: Dictionary, progress: Dictionary, actor_profile: Dictionary = {}) -> Dictionary:
	var guard := _guard(snapshot, progress)
	if not bool(guard.get("ok", false)):
		return guard
	if String(progress.get("status", "")) == "completed":
		return {
			"ok": true,
			"code": "shift_completed",
			"completed": true,
			"result": Dictionary(progress.get("result", {})).duplicate(true),
		}
	var step: Dictionary = Array(snapshot["steps"])[int(progress["next_step_index"])]
	var profile := _normalize_profile(actor_profile)
	var modifier := _competence_modifier(step, profile)
	var choices: Array = []
	for raw: Variant in Array(step["choices"]):
		var choice: Dictionary = raw
		choices.append({
			"id": String(choice["id"]),
			"title": String(choice["title"]),
			"description": String(choice["description"]),
			"projected_score_deltas": _score_deltas(choice, modifier),
		})
	return {
		"ok": true,
		"code": "ok",
		"completed": false,
		"step": _public_step(step),
		"choices": choices,
		"competence_modifier": modifier,
		"scores": Dictionary(progress["scores"]).duplicate(true),
	}


static func resolve_step(
	snapshot: Dictionary,
	progress: Dictionary,
	choice_id: String,
	actor_profile: Dictionary = {}
) -> Dictionary:
	var guard := _guard(snapshot, progress)
	if not bool(guard.get("ok", false)):
		return guard
	if String(progress.get("status", "")) == "completed":
		return _failure("shift_completed", "Смена уже завершена")
	var step: Dictionary = Array(snapshot["steps"])[int(progress["next_step_index"])]
	var choice := _find_choice(Array(step["choices"]), choice_id)
	if choice.is_empty():
		return _failure("unknown_choice", "Вариант больше не относится к текущему шагу")
	var candidate := progress.duplicate(true)
	var modifier := _competence_modifier(step, _normalize_profile(actor_profile))
	var deltas := _score_deltas(choice, modifier)
	var scores: Dictionary = candidate["scores"]
	for field: String in SCORE_FIELDS:
		scores[field] = clampi(int(scores[field]) + int(deltas[field]), 0, 100)
	var completion := {
		"step_id": String(step["step_id"]),
		"kind": String(step["kind"]),
		"content_id": String(step["content_id"]),
		"choice_id": String(choice["id"]),
		"choice_title": String(choice["title"]),
		"outcome": String(choice["outcome"]),
		"task_class_id": String(step.get("task_class_id", "")),
		"competence_modifier": modifier,
		"score_deltas": deltas,
		"scores_after": scores.duplicate(true),
	}
	var completed_steps: Array = candidate["completed_steps"]
	completed_steps.append(completion)
	if String(step["kind"]) == "task":
		var task_class_id := String(step["task_class_id"])
		var practiced_classes: Array = candidate["practiced_task_class_ids"]
		if task_class_id not in practiced_classes:
			practiced_classes.append(task_class_id)
	candidate["next_step_index"] = int(candidate["next_step_index"]) + 1
	if int(candidate["next_step_index"]) == Array(snapshot["steps"]).size():
		candidate["status"] = "completed"
		candidate["result"] = _result(snapshot, candidate)
	var validation := ProgressScript.validate(candidate, snapshot)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_candidate",
			"error": "Результат шага нарушил контракт смены",
			"errors": validation.get("errors", []),
		}
	return {
		"ok": true,
		"code": "ok",
		"progress": candidate,
		"receipt": completion.duplicate(true),
		"completed": String(candidate["status"]) == "completed",
		"result": Dictionary(candidate["result"]).duplicate(true),
	}


static func _guard(snapshot: Dictionary, progress: Dictionary) -> Dictionary:
	var snapshot_validation := SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_snapshot",
			"error": "Снимок смены повреждён",
			"errors": snapshot_validation.get("errors", []),
		}
	var progress_validation := ProgressScript.validate(progress, snapshot)
	if not bool(progress_validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_progress",
			"error": "Прогресс смены повреждён",
			"errors": progress_validation.get("errors", []),
		}
	return {"ok": true}


static func _normalize_profile(source: Dictionary) -> Dictionary:
	var characteristics: Dictionary = source.get("characteristics", {})
	var skills: Dictionary = source.get("skills", {})
	var normalized_characteristics := {}
	for attribute_id: String in ["strength", "charisma", "intelligence", "luck"]:
		normalized_characteristics[attribute_id] = clampi(int(characteristics.get(attribute_id, 5)), 1, 10)
	var normalized_skills := {}
	for raw_id: Variant in skills:
		normalized_skills[String(raw_id)] = clampi(int(skills[raw_id]), 0, 3)
	return {"characteristics": normalized_characteristics, "skills": normalized_skills}


static func _competence_modifier(step: Dictionary, profile: Dictionary) -> int:
	if String(step.get("kind", "")) != "task":
		return 0
	var attribute := int(Dictionary(profile["characteristics"]).get(String(step["attribute_id"]), 5))
	var skill := int(Dictionary(profile["skills"]).get(String(step["skill_id"]), 0))
	var margin := attribute + skill * 2 - int(step["difficulty"])
	if margin >= 5:
		return 3
	if margin >= 2:
		return 2
	if margin >= 0:
		return 1
	if margin <= -5:
		return -3
	if margin <= -2:
		return -2
	return -1


static func _score_deltas(choice: Dictionary, competence_modifier: int) -> Dictionary:
	var authored: Dictionary = choice["scores"]
	return {
		"production": int(authored["production"]) + competence_modifier,
		"quality": int(authored["quality"]) + competence_modifier,
		"safety": int(authored["safety"]) + competence_modifier,
	}


static func _result(snapshot: Dictionary, progress: Dictionary) -> Dictionary:
	var scores: Dictionary = progress["scores"]
	@warning_ignore("integer_division")
	var overall := (int(scores["production"]) * 40 + int(scores["quality"]) * 35 + int(scores["safety"]) * 25) / 100
	var payout_basis_points := clampi(7_500 + (overall - 50) * 90, 6_500, 12_500)
	if int(scores["safety"]) < 35:
		payout_basis_points = mini(payout_basis_points, 7_000)
	var grade := "unsafe" if int(scores["safety"]) < 35 else "weak"
	if int(scores["safety"]) >= 35 and overall >= 75:
		grade = "excellent"
	elif int(scores["safety"]) >= 35 and overall >= 60:
		grade = "solid"
	elif int(scores["safety"]) >= 35 and overall >= 45:
		grade = "acceptable"
	return {
		"shift_id": String(progress["shift_id"]),
		"job_id": String(progress["job_id"]),
		"production": int(scores["production"]),
		"quality": int(scores["quality"]),
		"safety": int(scores["safety"]),
		"overall": overall,
		"grade": grade,
		"payout_basis_points": payout_basis_points,
		"base_payout_ard": int(snapshot["base_payout_ard"]),
		"practiced_task_class_ids": Array(progress["practiced_task_class_ids"]).duplicate(),
	}


static func _public_step(step: Dictionary) -> Dictionary:
	var result := step.duplicate(true)
	result.erase("choices")
	return result


static func _find_choice(choices: Array, choice_id: String) -> Dictionary:
	for raw: Variant in choices:
		if raw is Dictionary and String(raw.get("id", "")) == choice_id:
			return Dictionary(raw).duplicate(true)
	return {}


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
