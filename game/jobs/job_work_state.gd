class_name JobWorkState
extends RefCounted

## Serializable owner of the modern work loop. The immutable generated shift,
## its mutable progress and long-term practice are kept together so save/load
## cannot pair a result with a different generated task list.
##
## The hero may hold more than one job. Only one shift runs at a time, but
## practice and standing are earned per employer: being let go from the yard
## says nothing about the market, and mastery of sorting is not mastery of
## loading.

const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")
const ProgressScript := preload("res://game/jobs/job_shift_progress.gd")
const MasteryScript := preload("res://game/jobs/job_mastery.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 3

## A supervisor keeps someone on while the work is adequate. A shift that puts
## people at risk counts double, a good one repairs standing, and three strikes
## end that job. The player is never shown this count — the supervisor's line in
## the result is how a person would learn it, and rule 3.4 says the interface
## does not explain its own mechanics.
const STRIKES_BEFORE_DISMISSAL := 3
const GRADE_STRIKES := {
	"unsafe": 2,
	"weak": 1,
	"acceptable": 0,
	"solid": -1,
	"excellent": -1,
}
## The employer a save written before second jobs existed belonged to.
const LEGACY_JOB_ID := "job_recycling_sorter"

var snapshot: Dictionary = {}
var progress: Dictionary = {}
## job_id -> {mastery, standing, next_shift_sequence, last_completed_day_index}
var employment: Dictionary = {}


static func fresh() -> JobWorkState:
	return JobWorkState.new()


static func fresh_standing() -> Dictionary:
	return {"strikes": 0, "dismissed": false}


static func fresh_employment(job_id: String) -> Dictionary:
	return {
		"mastery": MasteryScript.fresh(job_id),
		"standing": fresh_standing(),
		"next_shift_sequence": 1,
		"last_completed_day_index": -1,
	}


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
	if int(version) < 3:
		# Everything a version 1 or 2 save recorded belonged to the yard, so it
		# is filed under that employer rather than discarded.
		var carried := {
			"mastery": source.get("mastery", MasteryScript.fresh(LEGACY_JOB_ID)),
			"standing": source.get("standing", fresh_standing()),
			"next_shift_sequence": source.get("next_shift_sequence", 1),
			"last_completed_day_index": source.get("last_completed_day_index", -1),
		}
		source = {
			"schema_version": SCHEMA_VERSION,
			"snapshot": source.get("snapshot", {}),
			"progress": source.get("progress", {}),
			"employment": {LEGACY_JOB_ID: carried},
		}
	if source.size() != 4:
		return null
	for field: String in ["snapshot", "progress", "employment"]:
		if not source.get(field, null) is Dictionary:
			return null
	var result := JobWorkState.new()
	result.snapshot = Dictionary(source["snapshot"]).duplicate(true)
	result.progress = Dictionary(source["progress"]).duplicate(true)
	for raw_job_id: Variant in Dictionary(source["employment"]):
		var job_id := String(raw_job_id)
		var raw_record: Variant = Dictionary(source["employment"])[raw_job_id]
		if not raw_record is Dictionary:
			return null
		var record: Dictionary = raw_record
		var sequence: Variant = _integral(record.get("next_shift_sequence", null))
		var completed_day: Variant = _integral(record.get("last_completed_day_index", null))
		if sequence == null or completed_day == null:
			return null
		if not record.get("mastery", null) is Dictionary:
			return null
		var raw_standing: Variant = record.get("standing", null)
		if not raw_standing is Dictionary:
			return null
		var strikes: Variant = _integral(Dictionary(raw_standing).get("strikes", null))
		if strikes == null or typeof(Dictionary(raw_standing).get("dismissed", null)) != TYPE_BOOL:
			return null
		result.employment[job_id] = {
			"mastery": Dictionary(record["mastery"]).duplicate(true),
			"standing": {
				"strikes": clampi(int(strikes), 0, STRIKES_BEFORE_DISMISSAL),
				"dismissed": bool(Dictionary(raw_standing)["dismissed"]),
			},
			"next_shift_sequence": int(sequence),
			"last_completed_day_index": int(completed_day),
		}
	return result if bool(result.validate().get("ok", false)) else null


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"snapshot": snapshot.duplicate(true),
		"progress": progress.duplicate(true),
		"employment": employment.duplicate(true),
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
	# Standing is the record that can end a job, so it must survive a copy
	# exactly like the shift it was earned in.
	employment = candidate.employment.duplicate(true)
	return true


# --- per-employer records ---------------------------------------------------


## Read-only. Building a location read-model asks whether the hero is dismissed,
## and a lazy insert there would make a pure read write to the session — which
## is exactly what the M3F.3 suite caught.
func record_for(job_id: String) -> Dictionary:
	if employment.has(job_id):
		return employment[job_id]
	return fresh_employment(job_id)


## Creates the record. Only the commands that actually change employment call
## this: taking a first shift is the moment a hero is on the books.
func _ensure_record(job_id: String) -> Dictionary:
	if not employment.has(job_id):
		employment[job_id] = fresh_employment(job_id)
	return employment[job_id]


func mastery_for(job_id: String) -> Dictionary:
	return Dictionary(record_for(job_id)["mastery"])


func standing_for(job_id: String) -> Dictionary:
	return Dictionary(record_for(job_id)["standing"])


func sequence_for(job_id: String) -> int:
	return int(record_for(job_id)["next_shift_sequence"])


func is_dismissed(job_id: String) -> bool:
	return bool(standing_for(job_id).get("dismissed", false))


func active_job_id() -> String:
	return String(snapshot.get("job_id", "")) if has_shift() else ""


# --- the one running shift --------------------------------------------------


func has_shift() -> bool:
	return not snapshot.is_empty() and not progress.is_empty()


func is_active() -> bool:
	return has_shift() and String(progress.get("status", "")) == "active"


func is_completed() -> bool:
	return has_shift() and String(progress.get("status", "")) == "completed"


func can_work_on_day(job_id: String, day_index: int) -> bool:
	if day_index < 0 or is_active() or is_dismissed(job_id):
		return false
	return int(record_for(job_id)["last_completed_day_index"]) != day_index


## A shift is credited to the day it starts. Crediting completion instead meant
## an evening shift that ran past midnight burned the following day as well,
## and the hero woke up already unable to work.
func begin_shift(next_snapshot: Dictionary, next_progress: Dictionary, day_index: int = -1) -> bool:
	var job_id := String(next_snapshot.get("job_id", ""))
	if job_id.is_empty() or is_active() or is_dismissed(job_id):
		return false
	if int(next_snapshot.get("sequence", -1)) != sequence_for(job_id):
		return false
	if not bool(SnapshotScript.validate(next_snapshot).get("ok", false)):
		return false
	if not bool(ProgressScript.validate(next_progress, next_snapshot).get("ok", false)):
		return false
	if String(next_progress.get("status", "")) != "active":
		return false
	snapshot = next_snapshot.duplicate(true)
	progress = next_progress.duplicate(true)
	var record := _ensure_record(job_id)
	record["next_shift_sequence"] = sequence_for(job_id) + 1
	if day_index >= 0:
		record["last_completed_day_index"] = day_index
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
	var job_id := active_job_id()
	if String(next_mastery.get("job_id", "")) != job_id:
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
	var record := _ensure_record(job_id)
	record["mastery"] = next_mastery.duplicate(true)
	record["last_completed_day_index"] = maxi(int(record["last_completed_day_index"]), 0)
	_record_standing(job_id, String(Dictionary(next_progress.get("result", {})).get("grade", "acceptable")))
	return bool(validate().get("ok", false))


func _record_standing(job_id: String, grade: String) -> void:
	var record := _ensure_record(job_id)
	var current: Dictionary = record["standing"]
	if bool(current.get("dismissed", false)):
		return
	var strikes := clampi(
		int(current.get("strikes", 0)) + int(GRADE_STRIKES.get(grade, 0)),
		0,
		STRIKES_BEFORE_DISMISSAL
	)
	record["standing"] = {
		"strikes": strikes,
		"dismissed": strikes >= STRIKES_BEFORE_DISMISSAL,
	}


func activity_projection() -> Dictionary:
	if not is_active():
		return {}
	return {
		"kind": "job_shift",
		"id": active_job_id(),
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
	for job_id: String in employment:
		var record: Dictionary = employment[job_id]
		if int(record.get("next_shift_sequence", 0)) < 1:
			errors.append("job_work_state.%s.next_shift_sequence должен быть не меньше 1" % job_id)
		if int(record.get("last_completed_day_index", -1)) < -1:
			errors.append("job_work_state.%s.last_completed_day_index не может быть меньше -1" % job_id)
		_append_errors(
			"%s.mastery" % job_id,
			MasteryScript.validate(Dictionary(record.get("mastery", {}))),
			errors
		)
		if String(Dictionary(record.get("mastery", {})).get("job_id", "")) != job_id:
			errors.append("job_work_state.%s.mastery относится к другой работе" % job_id)
	if snapshot.is_empty() != progress.is_empty():
		errors.append("job_work_state snapshot и progress должны существовать вместе")
	elif not snapshot.is_empty():
		_append_errors("snapshot", SnapshotScript.validate(snapshot), errors)
		_append_errors("progress", ProgressScript.validate(progress, snapshot), errors)
		var job_id := active_job_id()
		if not employment.has(job_id):
			errors.append("job_work_state: активная смена без записи о найме")
		elif int(snapshot.get("sequence", -1)) != sequence_for(job_id) - 1:
			errors.append("job_work_state sequence не согласован со следующим номером смены")
		if is_completed():
			if int(record_for(job_id)["last_completed_day_index"]) < 0:
				errors.append("завершённая смена должна хранить день расчёта")
			if not _mastery_has_shift(job_id, String(progress.get("shift_id", ""))):
				errors.append("завершённая смена отсутствует в истории освоения")
	return {"ok": errors.is_empty(), "errors": errors}


func _mastery_has_shift(job_id: String, shift_id: String) -> bool:
	for raw_record: Variant in Array(mastery_for(job_id).get("completed_shifts", [])):
		if raw_record is Dictionary and String(raw_record.get("shift_id", "")) == shift_id:
			return true
	return false


static func _append_errors(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append("job_work_state.%s: %s" % [prefix, String(raw_error)])


static func _integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return null
