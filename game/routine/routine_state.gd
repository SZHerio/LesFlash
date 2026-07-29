class_name RoutineState
extends RefCounted

## The week a person intends to have, and how much of it they have had before.
##
## Two things live here and they are deliberately separate. The **plan** is what
## the hero decided: which activity fills which stretch of which day. The
## **practice** is what actually happened: how many times each activity was seen
## through to the end. Practice is what turns an activity into something he can
## do without thinking about it, which is the whole reason a routine can be run
## unattended at all.
##
## Nothing here decides anything. The plan is a statement of intent; whether the
## morning actually goes that way is the runner's problem, and it very often
## does not.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1

## day_of_week (1..7 as a string key) -> block id -> activity id.
## Stored with string keys because it is written to JSON and read back, and a
## dictionary that changes its key type across a save round-trip is a bug that
## takes a day to find.
var plan: Dictionary = {}

## activity_id -> how many times it was carried through. Only completions count:
## a shift walked out of halfway teaches the hero nothing he can lean on later.
var practice: Dictionary = {}

## The slot key of the last stretch the routine was run for, so following the
## routine twice for the same morning cannot happen even across a save.
var last_slot_key: String = ""

## Whether the hero is currently keeping to it. A plan he has abandoned stays
## written down — he may pick it up again — but it does not run.
var following: bool = false


static func fresh() -> RoutineState:
	var state := RoutineState.new()
	state.plan = {}
	state.practice = {}
	state.last_slot_key = ""
	state.following = false
	return state


## What is planned for one stretch, or empty when nothing is.
func activity_for(day_of_week: int, block_id: String) -> String:
	var day_key := str(day_of_week)
	if not plan.has(day_key):
		return ""
	return String(Dictionary(plan[day_key]).get(block_id, ""))


## Writes one stretch of the plan. An empty activity clears it, because "nothing
## planned" has to be sayable — a week with every square filled is a timetable,
## not a life.
func set_activity(day_of_week: int, block_id: String, activity_id: String) -> bool:
	if day_of_week < 1 or day_of_week > WeekSchedule.DAYS_PER_WEEK:
		return false
	if not WeekSchedule.is_block(block_id):
		return false
	var day_key := str(day_of_week)
	if activity_id.strip_edges().is_empty():
		if plan.has(day_key):
			Dictionary(plan[day_key]).erase(block_id)
			if Dictionary(plan[day_key]).is_empty():
				plan.erase(day_key)
		return true
	if not plan.has(day_key):
		plan[day_key] = {}
	Dictionary(plan[day_key])[block_id] = activity_id
	return true


func clear_plan() -> void:
	plan = {}


## How many stretches of the week are spoken for.
func planned_count() -> int:
	var total := 0
	for day_key: Variant in plan:
		total += Dictionary(plan[day_key]).size()
	return total


func is_planned() -> bool:
	return planned_count() > 0


## Records one activity carried through to the end, returning the new count.
func record_practice(activity_id: String) -> int:
	var trimmed := activity_id.strip_edges()
	if trimmed.is_empty():
		return 0
	var count := int(practice.get(trimmed, 0)) + 1
	practice[trimmed] = count
	return count


func practice_count(activity_id: String) -> int:
	return int(practice.get(activity_id, 0))


## Whether the hero knows this well enough to be trusted with it unattended.
## Below this the routine still runs it, but hands the steps back to the player.
func is_mastered(activity_id: String, repeats_required: int) -> bool:
	return practice_count(activity_id) >= maxi(repeats_required, 1)


func mark_slot(slot_key: String) -> void:
	last_slot_key = slot_key


func has_run_slot(slot_key: String) -> bool:
	return not slot_key.is_empty() and last_slot_key == slot_key


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"plan": plan.duplicate(true),
		"practice": practice.duplicate(true),
		"last_slot_key": last_slot_key,
		"following": following,
	}


static func from_dict(data: Variant) -> RoutineState:
	if not data is Dictionary:
		return null
	var source: Dictionary = data
	if int(source.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := RoutineState.new()
	var parsed_plan: Variant = _parse_plan(source.get("plan", {}))
	if parsed_plan == null:
		return null
	var parsed_practice: Variant = _parse_practice(source.get("practice", {}))
	if parsed_practice == null:
		return null
	state.plan = parsed_plan
	state.practice = parsed_practice
	if typeof(source.get("last_slot_key", "")) != TYPE_STRING:
		return null
	state.last_slot_key = String(source.get("last_slot_key", ""))
	if typeof(source.get("following", false)) != TYPE_BOOL:
		return null
	state.following = bool(source.get("following", false))
	var validation := state.validate()
	if not bool(validation.get("ok", false)):
		return null
	return state


func clone() -> RoutineState:
	var copy := RoutineState.new()
	copy.plan = plan.duplicate(true)
	copy.practice = practice.duplicate(true)
	copy.last_slot_key = last_slot_key
	copy.following = following
	return copy


## Publishes another state's contents into this object without changing its
## identity, the same contract every other aggregate in the session keeps.
func replace_from(other: RoutineState) -> bool:
	if other == null:
		return false
	var validation := other.validate()
	if not bool(validation.get("ok", false)):
		return false
	plan = other.plan.duplicate(true)
	practice = other.practice.duplicate(true)
	last_slot_key = other.last_slot_key
	following = other.following
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(JsonValidator.validate(to_dict(), "routine_state").get("errors", [])):
		errors.append(String(raw))
	for raw_day: Variant in plan:
		var day_key := String(raw_day)
		if not day_key.is_valid_int():
			errors.append("routine_state.plan содержит нечисловой день %s" % day_key)
			continue
		var day_index := int(day_key)
		if day_index < 1 or day_index > WeekSchedule.DAYS_PER_WEEK:
			errors.append("routine_state.plan.%s вне диапазона недели" % day_key)
		if not plan[raw_day] is Dictionary:
			errors.append("routine_state.plan.%s должен быть объектом" % day_key)
			continue
		for raw_block: Variant in Dictionary(plan[raw_day]):
			var block_id := String(raw_block)
			if not WeekSchedule.is_block(block_id):
				errors.append("routine_state.plan.%s содержит неизвестное время суток %s" % [
					day_key, block_id,
				])
			if String(Dictionary(plan[raw_day])[raw_block]).strip_edges().is_empty():
				errors.append("routine_state.plan.%s.%s пуст" % [day_key, block_id])
	for raw_activity: Variant in practice:
		if typeof(raw_activity) != TYPE_STRING or String(raw_activity).strip_edges().is_empty():
			errors.append("routine_state.practice содержит пустой идентификатор")
			continue
		var count: Variant = practice[raw_activity]
		if typeof(count) != TYPE_INT or int(count) < 0:
			errors.append("routine_state.practice.%s должен быть неотрицательным целым" % String(raw_activity))
	return {"ok": errors.is_empty(), "errors": errors}


static func _parse_plan(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for raw_day: Variant in Dictionary(value):
		var day_key := String(raw_day)
		if not day_key.is_valid_int():
			return null
		if not Dictionary(value)[raw_day] is Dictionary:
			return null
		var day: Dictionary = {}
		for raw_block: Variant in Dictionary(Dictionary(value)[raw_day]):
			var block_id := String(raw_block)
			var activity_id := String(Dictionary(Dictionary(value)[raw_day])[raw_block])
			if activity_id.strip_edges().is_empty():
				return null
			day[block_id] = activity_id
		if not day.is_empty():
			result[day_key] = day
	return result


static func _parse_practice(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for raw_activity: Variant in Dictionary(value):
		var activity_id := String(raw_activity)
		if activity_id.strip_edges().is_empty():
			return null
		var count: Variant = SerializedValue.parse_integral(Dictionary(value)[raw_activity])
		if count == null or int(count) < 0:
			return null
		result[activity_id] = int(count)
	return result
