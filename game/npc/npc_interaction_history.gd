class_name NpcInteractionHistory
extends RefCounted

## Rebuilds repeat limits from the authoritative RunState journal. No parallel
## cooldown save state is introduced for M3F.3.


static func summary(run_state: RunState, interaction_id: String) -> Dictionary:
	var result := {
		"interaction_id": interaction_id,
		"occurrences": 0,
		"today_occurrences": 0,
		"last_day_key": "",
		"cooldown_ready_at": 0,
	}
	if run_state == null or run_state.calendar == null or interaction_id.is_empty():
		return result
	var today := civil_day_key(run_state.calendar.current_stamp())
	for raw: Variant in run_state.journal:
		if not raw is Dictionary:
			continue
		var payload: Variant = raw.get("payload", {})
		if not payload is Dictionary:
			continue
		if String(payload.get("interaction_id", "")) != interaction_id:
			continue
		if String(payload.get("npc_id", "")).is_empty():
			continue
		result["occurrences"] = int(result["occurrences"]) + 1
		var day_key := String(payload.get("civil_day_key", ""))
		if day_key.is_empty() and raw.get("at", null) is Dictionary:
			day_key = civil_day_key(Dictionary(raw["at"]))
		result["last_day_key"] = day_key
		if day_key == today:
			result["today_occurrences"] = int(result["today_occurrences"]) + 1
		var ready_at := int(payload.get("cooldown_ready_at", 0))
		result["cooldown_ready_at"] = maxi(int(result["cooldown_ready_at"]), ready_at)
	return result


static func repeat_evaluation(run_state: RunState, definition: Dictionary) -> Dictionary:
	if run_state == null or run_state.calendar == null:
		return _blocked("missing_state", "Состояние попытки недоступно", {})
	var interaction_id := String(definition.get("id", ""))
	var history := summary(run_state, interaction_id)
	var policy: Dictionary = definition.get("repeat_policy", {})
	var kind := String(policy.get("kind", ""))
	match kind:
		"once_per_life":
			if int(history.get("occurrences", 0)) > 0:
				return _blocked("already_completed", "Это взаимодействие уже завершено в этой жизни", history)
		"once_per_civil_day":
			if int(history.get("today_occurrences", 0)) > 0:
				return _blocked("already_used_today", "Сегодня этот разговор уже состоялся", history)
		"cooldown":
			var ready_at := int(history.get("cooldown_ready_at", 0))
			var elapsed := int(run_state.calendar.elapsed_minutes)
			if ready_at > elapsed:
				return _blocked(
					"cooldown_active",
					"К разговору можно вернуться через %d мин." % (ready_at - elapsed),
					history
				)
		_:
			return _blocked("unknown_repeat_policy", "Правило повторения неизвестно", history)
	return {
		"allowed": true,
		"code": "ready",
		"message": "Взаимодействие доступно",
		"history": history,
	}


static func civil_day_key(stamp: Dictionary) -> String:
	return "%04d-%02d-%02d" % [
		int(stamp.get("year", 0)),
		int(stamp.get("month", 0)),
		int(stamp.get("day", 0)),
	]


static func _blocked(code: String, message: String, history: Dictionary) -> Dictionary:
	return {
		"allowed": false,
		"code": code,
		"message": message,
		"history": history.duplicate(true),
	}
