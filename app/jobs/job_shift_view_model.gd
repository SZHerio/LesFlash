class_name JobShiftViewModel
extends RefCounted

## Pure presentation boundary for an active or completed work shift. It accepts
## a saved snapshot/progress pair and never mutates either value or resolves a
## job choice. Semantic IDs are selected from typed fields, never Russian copy.

const SCORE_FIELDS := [&"production", &"quality", &"safety"]
const SCORE_LABELS := {
	&"production": "Выработка",
	&"quality": "Качество",
	&"safety": "Безопасность",
}
const GRADE_LABELS := {
	"unsafe": "Опасная работа",
	"weak": "Слабый результат",
	"acceptable": "Приемлемо",
	"solid": "Надёжная смена",
	"excellent": "Отличная смена",
}


static func build(raw: Dictionary, reduced_motion: bool = false) -> Dictionary:
	var snapshot := _dictionary(raw.get("snapshot", {}))
	var progress := _dictionary(raw.get("progress", {}))
	var steps := _array(snapshot.get("steps", []))
	var completed_count := clampi(
		int(progress.get("next_step_index", _array(progress.get("completed_steps", [])).size())),
		0,
		steps.size()
	)
	var result := _result_source(raw, progress)
	var completed := (
		String(progress.get("status", "active")) == "completed"
		or bool(raw.get("completed", false))
		or not result.is_empty() and completed_count >= steps.size()
	)
	var briefing := _dictionary(snapshot.get("briefing", {}))
	var scores := _dictionary(progress.get("scores", {}))
	if completed and not result.is_empty():
		for score_id: StringName in SCORE_FIELDS:
			if result.has(score_id):
				scores[score_id] = result[score_id]
	return {
		"job_id": _text(snapshot.get("job_id", raw.get("job_id", ""))),
		"shift_id": _text(snapshot.get("shift_id", raw.get("shift_id", ""))),
		"title": _text(raw.get("title", "Сортировщик вторсырья"), "Сортировщик вторсырья"),
		"briefing_title": _text(briefing.get("title", "Рабочая смена"), "Рабочая смена"),
		"briefing_text": _text(briefing.get("text", "Подготовьтесь к задачам смены."), "Подготовьтесь к задачам смены."),
		"supervisor_text": _text(raw.get("supervisor_text", "Мастер смены · Виктор Корен")),
		"shift_meta_tokens": _shift_meta(snapshot),
		"progress": _progress_model(completed_count, steps.size(), completed),
		"metrics": _metrics(scores),
		"current_step": {} if completed else _current_step(raw, snapshot, progress),
		"result": _result_model(result, progress, completed),
		"quick_resolve": _quick_resolve(raw.get("quick_resolve", false), completed),
		"expected_revision": int(raw.get("expected_revision", raw.get("revision", 0))),
		"reduced_motion": bool(raw.get("reduced_motion", reduced_motion)),
	}


static func _current_step(raw: Dictionary, snapshot: Dictionary, progress: Dictionary) -> Dictionary:
	var explicit: Variant = raw.get("current_step", null)
	var step: Dictionary = {}
	var choices: Array = []
	if explicit is Dictionary and not Dictionary(explicit).is_empty():
		var container: Dictionary = explicit
		if container.get("step", null) is Dictionary:
			step = _dictionary(container.get("step", {}))
			choices = _array(container.get("choices", step.get("choices", [])))
		else:
			step = container.duplicate(true)
			choices = _array(step.get("choices", []))
	else:
		var steps := _array(snapshot.get("steps", []))
		var index := int(progress.get("next_step_index", 0))
		if index >= 0 and index < steps.size() and steps[index] is Dictionary:
			step = _dictionary(steps[index])
			choices = _array(step.get("choices", []))
	if step.is_empty():
		return {}
	var kind := String(step.get("kind", "task"))
	var choice_models: Array[Dictionary] = []
	for raw_choice: Variant in choices:
		if raw_choice is Dictionary:
			var choice := _choice_model(Dictionary(raw_choice), kind)
			if not String(choice.get("id", "")).is_empty():
				choice_models.append(choice)
	return {
		"step_id": _text(step.get("step_id", "")),
		"kind": kind,
		"eyebrow": "РЕШЕНИЕ СМЕНЫ" if kind == "decision" else "ЗАДАЧА СМЕНЫ",
		"icon_id": &"meta_risk" if kind == "decision" else &"action_work",
		"title": _text(step.get("title", "Текущая задача"), "Текущая задача"),
		"description": _text(step.get("description", "Выберите способ работы."), "Выберите способ работы."),
		"choices": choice_models,
	}


static func _choice_model(source: Dictionary, kind: String) -> Dictionary:
	var enabled := bool(source.get("enabled", source.get("available", true)))
	var reason := _text(source.get("locked_reason", source.get("reason", "")))
	var deltas := _dictionary(source.get(
		"projected_score_deltas",
		source.get("score_deltas", source.get("scores", {}))
	))
	var tokens: Array[Dictionary] = []
	for score_id: StringName in SCORE_FIELDS:
		if not deltas.has(score_id):
			continue
		var delta := int(deltas[score_id])
		tokens.append({
			"icon_id": &"",
			"text": "%s %s%d" % [SCORE_LABELS[score_id], "+" if delta >= 0 else "", delta],
			"accessible_text": "%s: %s%d" % [SCORE_LABELS[score_id], "+" if delta >= 0 else "", delta],
		})
	return {
		"id": _text(source.get("id", "")),
		"title": _text(source.get("title", "Способ работы"), "Способ работы"),
		"description": _text(source.get("description", "")),
		"enabled": enabled,
		"locked_reason": reason,
		"category_icon_id": &"meta_risk" if kind == "decision" else &"action_work",
		"variant": StringName(source.get("variant", &"normal")),
		"meta_tokens": tokens,
	}


static func _metrics(scores: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for score_id: StringName in SCORE_FIELDS:
		result.append({
			"id": score_id,
			"label": SCORE_LABELS[score_id],
			"value": clampi(int(scores.get(score_id, 50)), 0, 100),
		})
	return result


static func _progress_model(done: int, total: int, completed: bool) -> Dictionary:
	var safe_total := maxi(total, 1)
	return {
		"value": clampi(done, 0, safe_total),
		"maximum": safe_total,
		"fraction": clampf(float(done) / float(safe_total), 0.0, 1.0),
		"label": "Смена завершена" if completed else "Шаг %d из %d" % [mini(done + 1, safe_total), safe_total],
		"detail": "%d из %d решений подтверждено" % [done, total],
	}


static func _shift_meta(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var duration := maxi(int(snapshot.get("duration_minutes", 0)), 0)
	if duration > 0:
		result.append({
			"icon_id": &"meta_time",
			"text": _duration_text(duration),
			"accessible_text": _duration_accessible(duration),
		})
	var payout := maxi(int(snapshot.get("base_payout_ard", 0)), 0)
	if payout > 0:
		result.append({
			"icon_id": &"currency_arden_compact",
			"text": str(payout),
			"accessible_text": "%d %s" % [payout, _arden_word(payout)],
		})
	return result


static func _result_source(raw: Dictionary, progress: Dictionary) -> Dictionary:
	var explicit := _dictionary(raw.get("result", {}))
	return explicit if not explicit.is_empty() else _dictionary(progress.get("result", {}))


static func _result_model(result: Dictionary, progress: Dictionary, completed: bool) -> Dictionary:
	if not completed:
		return {"visible": false}
	var grade := String(result.get("grade", "acceptable"))
	var summary := _text(result.get("summary", result.get("outcome", "")))
	if summary.is_empty():
		var completed_steps := _array(progress.get("completed_steps", []))
		if not completed_steps.is_empty() and completed_steps[-1] is Dictionary:
			summary = _text(Dictionary(completed_steps[-1]).get("outcome", ""))
	if summary.is_empty():
		summary = "Рабочая смена закончена, результат внесён в журнал."
	var payout_text := ""
	var payout := int(result.get("payout_ard", result.get("paid_ard", -1)))
	if payout >= 0:
		payout_text = "Оплата: %d %s" % [payout, _arden_word(payout)]
	var mastery := int(result.get("mastery_awarded", 0))
	return {
		"visible": true,
		"title": _text(result.get("title", "Смена завершена"), "Смена завершена"),
		"grade": GRADE_LABELS.get(grade, "Смена завершена"),
		"summary": summary,
		"overall_text": "Общий результат: %d из 100" % clampi(int(result.get("overall", 0)), 0, 100),
		"payout_text": payout_text,
		"mastery_text": "Новый опыт: +%d" % mastery if mastery > 0 else "",
	}


static func _quick_resolve(value: Variant, completed: bool) -> Dictionary:
	var source := _dictionary(value)
	var allowed := bool(value) if value is bool else bool(source.get(
		"eligible",
		source.get("allowed", source.get("enabled", false))
	))
	return {
		"visible": allowed and not completed and bool(source.get("visible", true)),
		"enabled": allowed and bool(source.get("enabled", true)),
		"title": _text(source.get("title", "Рассчитать освоенную смену"), "Рассчитать освоенную смену"),
		"description": _text(source.get("description", "Знакомые операции будут рассчитаны сразу; значимое решение не пропускается.")),
		"blocked_reason": _text(source.get("blocked_reason", source.get("reason", ""))),
	}


static func _duration_text(minutes: int) -> String:
	if minutes % 60 == 0:
		return "%d ч" % (minutes / 60)
	if minutes > 60:
		return "%d ч %d мин" % [minutes / 60, minutes % 60]
	return "%d мин" % minutes


static func _duration_accessible(minutes: int) -> String:
	return "%d %s" % [minutes, _minute_word(minutes)]


static func _minute_word(value: int) -> String:
	var last_two := value % 100
	if last_two >= 11 and last_two <= 14:
		return "минут"
	match value % 10:
		1:
			return "минута"
		2, 3, 4:
			return "минуты"
		_:
			return "минут"


static func _arden_word(value: int) -> String:
	var last_two := value % 100
	if last_two >= 11 and last_two <= 14:
		return "арденов"
	match value % 10:
		1:
			return "арден"
		2, 3, 4:
			return "ардена"
		_:
			return "арденов"


static func _dictionary(value: Variant) -> Dictionary:
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func _array(value: Variant) -> Array:
	return Array(value).duplicate(true) if value is Array else []


static func _text(value: Variant, fallback: String = "") -> String:
	if value == null:
		return fallback
	var result := String(value).strip_edges()
	return fallback if result.is_empty() else result
