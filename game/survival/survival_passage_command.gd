class_name SurvivalPassageCommand
extends RefCounted

## Atomic boundary for a confirmed time decision. It advances the RunState
## calendar and the survival fixed-point state together or commits neither.

const TimeRules := preload("res://game/survival/survival_time_rules.gd")
const SurvivalStateScript := preload("res://game/survival/survival_state.gd")


static func execute(run_state: RunState, survival_state: SurvivalState, request: Dictionary) -> Dictionary:
	var contract_error := _contract_error(run_state, survival_state, request)
	if not contract_error.is_empty():
		return _failure("invalid_passage", contract_error)
	var passage_id := String(request["passage_id"])
	if survival_state.has_applied(passage_id):
		return {
			"ok": true,
			"code": "already_applied",
			"error": "",
			"consumed_minutes": 0,
			"status": survival_state.status,
			"changes": [],
		}
	if not bool(request["confirmed"]):
		return _failure("not_confirmed", "Время движется только после подтверждения решения")
	if survival_state.status != SurvivalStateScript.STATUS_ACTIVE:
		return _failure("lifecycle_complete", "Текущая семидневная попытка уже завершена")
	if run_state.calendar == null or int(run_state.calendar.elapsed_minutes) != survival_state.processed_elapsed_minutes:
		return _failure("time_desynchronized", "Календарь и survival-прогресс рассинхронизированы")

	var run_candidate := run_state.clone()
	if run_candidate == null:
		return _failure("invalid_run_state", "Не удалось создать атомарный снимок героя")
	var simulation := TimeRules.simulate(
		run_candidate.meters,
		survival_state,
		int(request["minutes"]),
		Dictionary(request.get("profile", {}))
	)
	if not bool(simulation.get("ok", false)):
		return simulation
	var survival_candidate: SurvivalState = simulation["survival_state"]
	for key: String in ["health", "hunger", "energy", "mental_state"]:
		if not run_candidate.set_meter(key, int(simulation["meters"][key])):
			return _failure("meter_commit_failed", "Не удалось применить показатель %s" % key)
	var consumed := int(simulation["consumed_minutes"])
	if consumed > 0:
		var reason := String(request.get("reason", "Подтверждённое действие"))
		if not run_candidate.advance_time(consumed, reason, {
			"survival_passage_id": passage_id,
			"requested_minutes": int(request["minutes"]),
			"status": survival_candidate.status,
		}):
			return _failure("time_commit_failed", "Не удалось продвинуть календарь")
	if not survival_candidate.record_applied(passage_id):
		return _failure("ledger_failed", "Не удалось записать подтверждённое решение")
	if survival_candidate.status != SurvivalStateScript.STATUS_ACTIVE:
		if not run_candidate.add_journal_entry(
			"lifecycle",
			"survival_%s" % survival_candidate.status,
			{
				"status": survival_candidate.status,
				"death_reason": survival_candidate.death_reason,
				"passage_id": passage_id,
			}
		):
			return _failure("journal_failed", "Не удалось записать итог жизненного цикла")
	if not bool(run_candidate.validate().get("ok", false)):
		return _failure("invalid_result", "Результат прохода повреждает RunState")
	if not bool(survival_candidate.validate().get("ok", false)):
		return _failure("invalid_result", "Результат прохода повреждает SurvivalState")
	if not run_state.replace_from(run_candidate) or not survival_state.replace_from(survival_candidate):
		return _failure("commit_failed", "Не удалось атомарно зафиксировать проход")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"consumed_minutes": consumed,
		"unconsumed_minutes": int(simulation["unconsumed_minutes"]),
		"status": survival_state.status,
		"changes": _changes(simulation["meter_deltas"], consumed),
	}


static func _contract_error(run_state: RunState, survival_state: SurvivalState, request: Dictionary) -> String:
	if run_state == null or not bool(run_state.validate().get("ok", false)):
		return "RunState повреждён"
	if survival_state == null or not bool(survival_state.validate().get("ok", false)):
		return "SurvivalState повреждён"
	if typeof(request.get("passage_id", null)) != TYPE_STRING or String(request.get("passage_id", "")).is_empty():
		return "passage_id обязателен"
	if typeof(request.get("confirmed", null)) != TYPE_BOOL:
		return "confirmed должен быть логическим значением"
	if typeof(request.get("minutes", null)) != TYPE_INT or int(request.get("minutes", 0)) <= 0:
		return "minutes должен быть положительным целым числом"
	if not request.get("profile", {}) is Dictionary:
		return "profile должен быть словарём"
	return ""


static func _changes(deltas: Dictionary, minutes: int) -> Array:
	var result: Array = [{
		"effect_type": "advance_time",
		"target_kind": "time",
		"target_id": "calendar",
		"delta": minutes,
	}]
	for key: String in ["health", "hunger", "energy", "mental_state"]:
		var delta := int(deltas.get(key, 0))
		if delta != 0:
			result.append({
				"effect_type": "change_state",
				"target_kind": "state",
				"target_id": key,
				"delta": delta,
			})
	return result


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "changes": []}
