class_name RoutineViewModel
extends RefCounted

## The week as the planner screen shows it: seven rows, four stretches each.
##
## Read-only, like every view model here — building it must not write a single
## field back into the session. What it adds to the raw plan is wording: the day
## a person would say out loud, the stretch of the day, and whether the hero
## knows this well enough that it will run without him being asked.

const CatalogScript := preload("res://game/routine/routine_catalog.gd")
const RunnerScript := preload("res://app/routine/routine_runner.gd")


static func build(session: Object) -> Dictionary:
	if session == null:
		return {}
	var routine: RoutineState = session.get("routine_state")
	if routine == null:
		return {}
	var loaded := CatalogScript.load_default()
	var catalog: Dictionary = Dictionary(loaded.get("catalog", {})) if bool(loaded.get("ok", false)) else {}
	var run_state: RunState = session.get("run_state")
	var elapsed := 0 if run_state == null else int(run_state.calendar.elapsed_minutes)
	var minute := 0 if run_state == null else int(run_state.calendar.minute_of_day)
	var today := WeekSchedule.day_of_week(elapsed)
	var now_block := WeekSchedule.block_of_minute(minute)

	var days: Array[Dictionary] = []
	for day_index: int in range(1, WeekSchedule.DAYS_PER_WEEK + 1):
		var blocks: Array[Dictionary] = []
		for block_id: String in WeekSchedule.BLOCK_IDS:
			var activity_id := routine.activity_for(day_index, block_id)
			var day_plan: Dictionary = Dictionary(Dictionary(routine.plan).get(str(day_index), {}))
			var holder := CatalogScript.holder_of(catalog, day_plan, block_id)
			var spilled: Dictionary = holder if bool(holder.get("spills", false)) else {}
			blocks.append(_block_entry(
				catalog, routine, day_index, block_id, activity_id, today, now_block, spilled
			))
		days.append({
			"day_of_week": day_index,
			"title": WeekSchedule.day_title(day_index),
			"today": day_index == today,
			"blocks": blocks,
		})

	return {
		"ok": true,
		"days": days,
		"following": routine.following,
		"planned_count": routine.planned_count(),
		"summary": _summary(routine),
		"today": today,
		"now_block": now_block,
	}


static func _block_entry(
	catalog: Dictionary,
	routine: RoutineState,
	day_index: int,
	block_id: String,
	activity_id: String,
	today: int,
	now_block: String,
	spilled_from: Dictionary = {}
) -> Dictionary:
	var entry: Dictionary = {} if activity_id.is_empty() else CatalogScript.find(catalog, activity_id)
	var repeats := int(entry.get("mastery_repeats", 4))
	if entry.is_empty() and not spilled_from.is_empty():
		# The stretch the morning's shift is still running through. Showing it as
		# free would invite a plan the day cannot hold.
		return {
			"block_id": block_id,
			"title": WeekSchedule.block_title(block_id),
			"activity_id": "",
			"activity_title": "занято: %s" % String(Dictionary(spilled_from["entry"]).get("title", "")),
			"empty": false,
			"missing": false,
			"occupied": true,
			"unattended": false,
			"now": day_index == today and block_id == now_block,
		}
	return {
		"block_id": block_id,
		"title": WeekSchedule.block_title(block_id),
		"activity_id": activity_id,
		# An empty stretch is left in words rather than blank: a week with gaps in
		# it is a decision, not an oversight.
		"activity_title": String(entry.get("title", "")) if not entry.is_empty() else "свободно",
		"empty": activity_id.is_empty(),
		"missing": not activity_id.is_empty() and entry.is_empty(),
		"occupied": false,
		"unattended": not entry.is_empty() and routine.is_mastered(activity_id, repeats),
		"now": day_index == today and block_id == now_block,
	}


## One line describing the week, in the words someone would use about their own.
static func _summary(routine: RoutineState) -> String:
	var planned := routine.planned_count()
	if planned == 0:
		return "Неделя пока ничем не занята"
	if not routine.following:
		return "Неделя расписана, но вы ей не следуете"
	return "Вы держитесь этого распорядка"


## What the runner would say right now if asked to carry on. Empty means it can.
static func obstacles(adapter: Object) -> Array[String]:
	return RunnerScript.need_reasons(adapter)
