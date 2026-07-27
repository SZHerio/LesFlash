class_name NpcScheduleResolver
extends RefCounted

## Pure schedule projection for canonical recurring NPCs.
## Days use ISO order: Monday=1 ... Sunday=7. Windows are [start, end).

const MONTH_OFFSETS := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]


static func presence(
	npc_catalog: Dictionary,
	npc_id: String,
	stamp: Dictionary,
	location_id: String
) -> Dictionary:
	var npc := _find(npc_catalog.get("npcs", []), npc_id)
	if npc.is_empty():
		return _absent("unknown_npc", "Персонаж не найден")
	if not _valid_stamp(stamp):
		return _absent("invalid_calendar", "Игровая дата недоступна")
	var schedule_id := String(npc.get("schedule_id", ""))
	var schedule := _find(npc_catalog.get("schedules", []), schedule_id)
	if schedule.is_empty():
		return _absent("unknown_schedule", "Расписание персонажа не найдено")
	var weekday := iso_weekday(stamp)
	var minute := int(stamp.get("minute_of_day", -1))
	for raw: Variant in schedule.get("entries", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if weekday not in Array(entry.get("days", [])):
			continue
		if String(entry.get("location_id", "")) != location_id:
			continue
		var start := int(entry.get("start_minute", -1))
		var finish := int(entry.get("end_minute", -1))
		if minute >= start and minute < finish:
			return {
				"present": true,
				"code": "present",
				"message": "Персонаж сейчас здесь",
				"npc_id": npc_id,
				"schedule_id": schedule_id,
				"location_id": location_id,
				"iso_weekday": weekday,
				"start_minute": start,
				"end_minute": finish,
			}
	return {
		"present": false,
		"code": "outside_schedule",
		"message": "Персонажа сейчас здесь нет",
		"npc_id": npc_id,
		"schedule_id": schedule_id,
		"location_id": location_id,
		"iso_weekday": weekday,
	}


static func present_npcs(
	npc_catalog: Dictionary,
	stamp: Dictionary,
	location_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in npc_catalog.get("npcs", []):
		if not raw is Dictionary:
			continue
		var npc: Dictionary = raw
		if bool(presence(npc_catalog, String(npc.get("id", "")), stamp, location_id).get("present", false)):
			result.append(npc.duplicate(true))
	return result


static func iso_weekday(stamp: Dictionary) -> int:
	# Gregorian arithmetic is deterministic and matches the canonical calendar:
	# 1 September 1980 is Monday (1).
	var year := int(stamp.get("year", 0))
	var month := int(stamp.get("month", 0))
	var day := int(stamp.get("day", 0))
	if month < 3:
		year -= 1
	@warning_ignore("integer_division")
	var sunday_zero := posmod(
		year + year / 4 - year / 100 + year / 400 + MONTH_OFFSETS[month - 1] + day,
		7
	)
	return 7 if sunday_zero == 0 else sunday_zero


static func _find(raw_entries: Variant, identifier: String) -> Dictionary:
	for raw: Variant in Array(raw_entries):
		if raw is Dictionary and String(raw.get("id", "")) == identifier:
			return Dictionary(raw).duplicate(true)
	return {}


static func _valid_stamp(stamp: Dictionary) -> bool:
	for field: String in ["year", "month", "day", "minute_of_day"]:
		if typeof(stamp.get(field, null)) != TYPE_INT:
			return false
	return (
		int(stamp.get("year", 0)) >= 1
		and int(stamp.get("month", 0)) in range(1, 13)
		and int(stamp.get("day", 0)) in range(1, 32)
		and int(stamp.get("minute_of_day", -1)) in range(0, 1440)
	)


static func _absent(code: String, message: String) -> Dictionary:
	return {"present": false, "code": code, "message": message}
