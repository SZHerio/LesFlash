class_name JobLocationActions
extends RefCounted

## Surfaces the sorting shift as an action of the yard that owns it.
##
## Without this the shift domain was unreachable: it existed, it was tested, and
## no player could ever start one.

const CatalogScript := preload("res://game/jobs/job_shift_catalog.gd")
const CommandScript := preload("res://game/jobs/job_session_command.gd")
const ScheduleResolver := preload("res://game/npc/npc_schedule_resolver.gd")

const YARD_LOCATION := JobSessionCommand.YARD_LOCATION
const SHIFT_START_MINUTE := 450
const SHIFT_LAST_START_MINUTE := 900


static func location_actions(
	session: Object,
	include_blocked: bool = false
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null or String(session.get("location")) != YARD_LOCATION:
		return result
	var work_state: JobWorkState = session.get("job_work_state")
	if work_state == null:
		return result
	var stamp: Dictionary = session.get("run_state").calendar.current_stamp()
	var minute := int(stamp.get("minute_of_day", 0))
	var active := work_state.is_active()

	# Rule 3.4: a hero who has been let go is not shown a disabled button that
	# explains the mechanic. The action is simply gone, and Viktor is the one
	# who tells him why.
	if work_state.is_dismissed():
		return result

	var reasons: Array[String] = []
	if not active:
		if minute < SHIFT_START_MINUTE:
			reasons.append("Площадка ещё закрыта")
		elif minute > SHIFT_LAST_START_MINUTE:
			reasons.append("На сегодня смены разобраны")
	var available := reasons.is_empty()
	if not available and not include_blocked:
		return result
	result.append({
		"id": "job_shift_%s" % JobSessionCommand.JOB_ID,
		"kind": "job_shift",
		"category_id": "work",
		"category_icon_id": "action_work",
		"title": "Вернуться на смену" if active else "Выйти на смену",
		"description": "Сортировочная площадка. Виктор распределяет участок.",
		"available": available,
		"reasons": reasons,
		"intent": {"type": "open_job_shift", "payload": {"job_id": JobSessionCommand.JOB_ID}},
		"confirmation_required": false,
		"minutes": 0 if active else JobSessionCommand.SHIFT_MINUTES,
	})
	return result
