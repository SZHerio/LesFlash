class_name RoutineSessionCommand
extends RefCounted

## Writing the week down, and deciding to keep to it.
##
## Editing a plan costs nothing and changes no meter — it is a person deciding
## what they intend to do, not doing it. It still goes through the ordinary
## clone-validate-publish path, because a plan that referred to an activity the
## catalog no longer has would be a save that reloads into a week nobody can
## live.

const CatalogScript := preload("res://game/routine/routine_catalog.gd")


## Everything that can be put in one stretch of one day, with what stands in the
## way of each. A blocked activity is still listed here: the planner is where a
## player is allowed to see what exists, unlike the location screen where rule
## 3.4 says the unreachable is simply absent.
static func options_for(session: Object, block_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null or not WeekSchedule.is_block(block_id):
		return result
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var routine: RoutineState = session.get("routine_state")
	for entry: Dictionary in CatalogScript.for_block(Dictionary(loaded["catalog"]), block_id):
		var activity_id := String(entry.get("id", ""))
		var repeats := int(entry.get("mastery_repeats", 4))
		result.append({
			"id": activity_id,
			"title": String(entry.get("title", "")),
			"description": String(entry.get("description", "")),
			"kind": String(entry.get("kind", "")),
			"location_id": String(entry.get("location_id", "")),
			"minutes": int(entry.get("minutes", 0)),
			"practised": routine.practice_count(activity_id) if routine != null else 0,
			"unattended": routine != null and routine.is_mastered(activity_id, repeats),
		})
	return result


## Puts one activity in one stretch, or clears it when the id is empty.
static func set_block(
	target: Object,
	day_of_week: int,
	block_id: String,
	activity_id: String,
	command_id: String
) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if not WeekSchedule.is_block(block_id):
		return _failure("unknown_block", "Такого времени суток нет")
	if day_of_week < 1 or day_of_week > WeekSchedule.DAYS_PER_WEEK:
		return _failure("unknown_day", "Такого дня недели нет")
	var trimmed := activity_id.strip_edges()
	if not trimmed.is_empty():
		var loaded := CatalogScript.load_default()
		if not bool(loaded.get("ok", false)):
			return _failure("invalid_catalog", "Список занятий недоступен")
		var entry := CatalogScript.find(Dictionary(loaded["catalog"]), trimmed)
		if entry.is_empty():
			return _failure("unknown_activity", "Такого занятия нет")
		if block_id not in Array(entry.get("blocks", [])):
			return _failure(
				"wrong_block",
				"«%s» в это время суток не делают" % String(entry.get("title", ""))
			)
	return _publish(target, command_id, func(routine: RoutineState) -> bool:
		return routine.set_activity(day_of_week, block_id, trimmed)
	)


## Starts or stops keeping to the plan. Stopping never erases it.
static func set_following(target: Object, following: bool, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var routine: RoutineState = target.get("routine_state")
	if following and (routine == null or not routine.is_planned()):
		return _failure("nothing_planned", "Сначала распишите неделю")
	return _publish(target, command_id, func(candidate: RoutineState) -> bool:
		candidate.following = following
		return true
	)


static func clear(target: Object, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	return _publish(target, command_id, func(routine: RoutineState) -> bool:
		routine.clear_plan()
		routine.following = false
		return true
	)


## Clone, change, validate, publish — the same contract as every other command,
## even though nothing here costs the hero a minute.
static func _publish(target: Object, command_id: String, change: Callable) -> Dictionary:
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить изменение")
	var routine: RoutineState = candidate.get("routine_state")
	if routine == null:
		return _failure("missing_routine", "Распорядок недоступен")
	if not bool(change.call(routine)):
		return _failure("rejected", "Изменение не принято")
	var validation := routine.validate()
	if not bool(validation.get("ok", false)):
		return _failure("invalid_routine", String(Array(validation.get("errors", ["Распорядок неверен"]))[0]))
	# The ledger entry is written on the candidate, before publishing, so the
	# state that goes live already knows this command happened. Writing it on the
	# target afterwards would leave a window where the change is committed and
	# the record of it is not.
	Dictionary(candidate.get("applied_command_ids"))[command_id] = {
		"source_id": "routine",
		"applied_at": candidate.get("run_state").calendar.current_stamp(),
	}
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила изменение")
	return {"ok": true, "code": "ok", "error": "", "idempotent": false}


static func _guard(target: Object, command_id: String) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Изменение должно иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	return {}


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
