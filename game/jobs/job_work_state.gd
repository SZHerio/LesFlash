class_name JobWorkState
extends RefCounted

## Serializable owner of the modern work loop. The immutable generated shift,
## its mutable progress and long-term practice are kept together so save/load
## cannot pair a result with a different generated task list.

const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")
const ProgressScript := preload("res://game/jobs/job_shift_progress.gd")
const MasteryScript := preload("res://game/jobs/job_mastery.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 2

## Viktor keeps the sorter on while the work is adequate. A shift that puts
## people at risk counts double, a good one repairs standing, and three strikes
## end the job. The player is never shown this count — the supervisor's line in
## the shift result is how a person would learn it, and rule 3.4 says the
## interface does not explain its own mechanics.
const STRIKES_BEFORE_DISMISSAL := 3
const GRADE_STRIKES := {
	"unsafe": 2,
	"weak": 1,
	"acceptable": 0,
	"solid": -1,
	"excellent": -1,
}
const JOB_ID := "job_recycling_sorter"

var snapshot: Dictionary = {}
var progress: Dictionary = {}
var mastery: Dictionary = MasteryScript.fresh(JOB_ID)
var next_shift_sequence: int = 1
var last_completed_day_index: int = -1
var standing: Dictionary = fresh_standing()


static func fresh() -> JobWorkState:
	return JobWorkState.new()


static func fresh_standing() -> Dictionary:
	return {"strikes": 0, "dismissed": false}


static func from_dict(value: Variant) -> JobWorkState:
	if not value is Dictionary:
		return null
	var source: Dictionary = JsonValidator.normalize_numbers(
		Dictionary(value).duplicate(true)
	)
	var version: Variant = _integral(source.get("schema_version", null))
	if version == null or int(version) < 1 or int(version) > SCHEMA_VERSION:
		return null
	if int(version) < 2:
		source["standing"] = fresh_standing()
		source["schema_version"] = SCHEMA_VERSION
	if source.size() != 7:
		return null
	for field: String in ["snapshot", "progress", "mastery"]:
		if not source.get(field, null) is Dictionary:
			return null
	var sequence: Variant = _integral(source.get("next_shift_sequence", null))
	var completed_day: Variant = _integral(source.get("last_completed_day_index", null))
	if sequence == null or completed_day == null:
		return null
	var result := JobWorkState.new()
	result.snapshot = Dictionary(source["snapshot"]).duplicate(true)
	result.progress = Dictionary(source["progress"]).duplicate(true)
	result.mastery = Dictionary(source["mastery"]).duplicate(true)
	result.next_shift_sequence = int(sequence)
	result.last_completed_day_index = int(completed_day)
	var standing_source: Variant = source.get("standing", null)
	if not standing_source is Dictionary:
		return null
	var strikes: Variant = _integral(Dictionary(standing_source).get("strikes", null))
	if strikes == null or typeof(Dictionary(standing_source).get("dismissed", null)) != TYPE_BOOL:
		return null
	result.standing = {
		"strikes": clampi(int(strikes), 0, STRIKES_BEFORE_DISMISSAL),
		"dismissed": bool(Dictionary(standing_source)["dismissed"]),
	}
	return result if bool(result.validate().get("ok", false)) else null


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"snapshot": snapshot.duplicate(true),
		"progress": progress.duplicate(true),
		"mastery": mastery.duplicate(true),
		"next_shift_sequence": next_shift_sequence,
		"last_completed_day_index": last_completed_day_index,
		"standing": standing.duplicate(true),
	}


func clone() -> JobWorkState:
	return JobWorkState.from_dict(to_dict())


func replace_from(other: JobWorkState) -> bool:
	if other == null:
		return false
	var candidate := JobWorkState.from_dict(other.to_dict())
	if candidate == null:
		return false
	snapshot = candidate.snapshot
	progress = candidate.progress
	mastery = candidate.mastery
	next_shift_sequence = candidate.next_shift_sequence
	last_completed_day_index = candidate.last_completed_day_index
	return true


func has_shift() -> bool:
	return not snapshot.is_empty() and not progress.is_empty()


func is_active() -> bool:
	return has_shift() and String(progress.get("status", "")) == "active"


func is_completed() -> bool:
	return has_shift() and String(progress.get("status", "")) == "completed"


func can_work_on_day(day_index: int) -> bool:
	return day_index >= 0 and not is_active() and last_completed_day_index != day_index


func begin_shift(next_snapshot: Dictionary, next_progress: Dictionary) -> bool:
	if is_active() or int(next_snapshot.get("sequence", -1)) != next_shift_sequence:
		return false
	if not bool(SnapshotScript.validate(next_snapshot).get("ok", false)):
		return false
	if not bool(ProgressScript.validate(next_progress, next_snapshot).get("ok", false)):
		return false
	if String(next_progress.get("status", "")) != "active":
		return false
	snapshot = next_snapshot.duplicate(true)
	progress = next_progress.duplicate(true)
	next_shift_sequence += 1
	return bool(validate().get("ok", false))


func replace_progress(next_progress: Dictionary) -> bool:
	if not has_shift() or not bool(
		ProgressScript.validate(next_progress, snapshot).get("ok", false)
	):
		return false
	if String(next_progress.get("status", "")) != "active":
		return false
	progress = next_progress.duplicate(true)
	return true


func complete_shift(
	next_progress: Dictionary,
	next_mastery: Dictionary,
	day_index: int
) -> bool:
	if not is_active() or day_index < 0:
		return false
	if not bool(ProgressScript.validate(next_progress, snapshot).get("ok", false)):
		return false
	if String(next_progress.get("status", "")) != "completed":
		return false
	if not bool(MasteryScript.validate(next_mastery).get("ok", false)):
		return false
	var shift_id := String(next_progress.get("shift_id", ""))
	var recorded := false
	for raw_record: Variant in Array(next_mastery.get("completed_shifts", [])):
		if raw_record is Dictionary and String(raw_record.get("shift_id", "")) == shift_id:
			recorded = true
			break
	if not recorded:
		return false
	progress = next_progress.duplicate(true)
	mastery = next_mastery.duplicate(true)
	last_completed_day_index = day_index
	_record_standing(String(Dictionary(next_progress.get("result", {})).get("grade", "acceptable")))
	return bool(validate().get("ok", false))


func _record_standing(grade: String) -> void:
	if bool(standing.get("dismissed", false)):
		return
	var strikes := clampi(
		int(standing.get("strikes", 0)) + int(GRADE_STRIKES.get(grade, 0)),
		0,
		STRIKES_BEFORE_DISMISSAL
	)
	standing = {
		"strikes": strikes,
		"dismissed": strikes >= STRIKES_BEFORE_DISMISSAL,
	}


func is_dismissed() -> bool:
	return bool(standing.get("dismissed", false))


func activity_projection() -> Dictionary:
	if not is_active():
		return {}
	return {
		"kind": "job_shift",
		"id": String(progress.get("job_id", JOB_ID)),
		"snapshot": {
			"shift_id": String(progress.get("shift_id", "")),
			"next_step_index": int(progress.get("next_step_index", 0)),
			"status": String(progress.get("status", "active")),
		},
	}


func validate() -> Dictionary:
	var errors: Array[String] = []
	for raw_error: Variant in Array(JsonValidator.validate(to_dict(), "job_work_state").get("errors", [])):
		errors.append(String(raw_error))
	if next_shift_sequence < 1:
		errors.append("job_work_state.next_shift_sequence должен быть не меньше 1")
	if last_completed_day_index < -1:
		errors.append("job_work_state.last_completed_day_index не может быть меньше -1")
	var mastery_validation := MasteryScript.validate(mastery)
	_append_errors("mastery", mastery_validation, errors)
	if snapshot.is_empty() != progress.is_empty():
		errors.append("job_work_state snapshot и progress должны существовать вместе")
	elif not snapshot.is_empty():
		_append_errors("snapshot", SnapshotScript.validate(snapshot), errors)
		_append_errors("progress", ProgressScript.validate(progress, snapshot), errors)
		if int(snapshot.get("sequence", -1)) != next_shift_sequence - 1:
			errors.append("job_work_state sequence не согласован со следующим номером смены")
		if is_completed():
			if last_completed_day_index < 0:
				errors.append("завершённая смена должна хранить день расчёта")
			var shift_id := String(progress.get("shift_id", ""))
			if not _mastery_has_shift(shift_id):
				errors.append("завершённая смена отсутствует в истории освоения")
	return {"ok": errors.is_empty(), "errors": errors}


func _mastery_has_shift(shift_id: String) -> bool:
	for raw_record: Variant in Array(mastery.get("completed_shifts", [])):
		if raw_record is Dictionary and String(raw_record.get("shift_id", "")) == shift_id:
			return true
	return false


static func _append_errors(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append("job_work_state.%s: %s" % [prefix, String(raw_error)])


static func _integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var number := float(value)
	return int(number) if is_finite(number) and number == floor(number) else null
