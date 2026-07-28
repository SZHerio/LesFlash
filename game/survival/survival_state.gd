class_name SurvivalState
extends RefCounted

## Saved progress of the short M3F survival loop.
##
## Needs themselves remain in RunState. This companion state stores only the
## fixed-point debt required for interval-independent simulation and the
## lifecycle boundary of the seven-day prototype.

const SCHEMA_VERSION := 1
const WEEK_MINUTES := 7 * 24 * 60
const FIXED_DENOMINATOR := 60

const STATUS_ACTIVE := "active"
const STATUS_DEAD := "dead"
const STATUS_WEEK_COMPLETE := "week_complete"
const STATUSES := [STATUS_ACTIVE, STATUS_DEAD, STATUS_WEEK_COMPLETE]
const REMAINDER_KEYS := ["hunger", "energy", "health", "mental_state"]

var start_elapsed_minutes: int = 0
var processed_elapsed_minutes: int = 0
var remainders: Dictionary = _empty_remainders()
var status: String = STATUS_ACTIVE
var death_reason: String = ""
var applied_passage_ids: Dictionary = {}


func _init(start_elapsed: int = 0) -> void:
	start_elapsed_minutes = maxi(start_elapsed, 0)
	processed_elapsed_minutes = start_elapsed_minutes


static func fresh(start_elapsed: int = 0) -> SurvivalState:
	if start_elapsed < 0:
		return null
	return SurvivalState.new(start_elapsed)


func week_end_elapsed_minutes() -> int:
	return start_elapsed_minutes + WEEK_MINUTES


func minutes_until_week_complete() -> int:
	return maxi(week_end_elapsed_minutes() - processed_elapsed_minutes, 0)


func is_terminal() -> bool:
	return status != STATUS_ACTIVE


func has_applied(passage_id: String) -> bool:
	return bool(applied_passage_ids.get(passage_id, false))


func record_applied(passage_id: String) -> bool:
	if passage_id.is_empty() or has_applied(passage_id):
		return false
	applied_passage_ids[passage_id] = true
	return true


func mark_dead(reason: String) -> bool:
	if status != STATUS_ACTIVE or reason.strip_edges().is_empty():
		return false
	status = STATUS_DEAD
	death_reason = reason.strip_edges()
	return true


func mark_week_complete() -> bool:
	if status != STATUS_ACTIVE or processed_elapsed_minutes != week_end_elapsed_minutes():
		return false
	status = STATUS_WEEK_COMPLETE
	death_reason = ""
	return true


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"start_elapsed_minutes": start_elapsed_minutes,
		"processed_elapsed_minutes": processed_elapsed_minutes,
		"remainders": remainders.duplicate(true),
		"status": status,
		"death_reason": death_reason,
		"applied_passage_ids": applied_passage_ids.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SurvivalState:
	var schema: Variant = SerializedValue.parse_integral(data.get("schema_version", null))
	var start: Variant = SerializedValue.parse_integral(data.get("start_elapsed_minutes", null))
	var processed: Variant = SerializedValue.parse_integral(data.get("processed_elapsed_minutes", null))
	if schema == null or int(schema) != SCHEMA_VERSION or start == null or processed == null:
		return null
	if not data.get("remainders", null) is Dictionary:
		return null
	if not data.get("applied_passage_ids", null) is Dictionary:
		return null
	if typeof(data.get("status", null)) != TYPE_STRING or typeof(data.get("death_reason", null)) != TYPE_STRING:
		return null

	var parsed_remainders: Dictionary = {}
	var raw_remainders: Dictionary = data["remainders"]
	if raw_remainders.size() != REMAINDER_KEYS.size():
		return null
	for key: String in REMAINDER_KEYS:
		var value: Variant = SerializedValue.parse_integral(raw_remainders.get(key, null))
		if value == null:
			return null
		parsed_remainders[key] = int(value)

	var parsed_ids: Dictionary = {}
	for raw_id: Variant in Dictionary(data["applied_passage_ids"]):
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty():
			return null
		if typeof(data["applied_passage_ids"][raw_id]) != TYPE_BOOL or not bool(data["applied_passage_ids"][raw_id]):
			return null
		parsed_ids[String(raw_id)] = true

	var result := SurvivalState.new(int(start))
	result.processed_elapsed_minutes = int(processed)
	result.remainders = parsed_remainders
	result.status = String(data["status"])
	result.death_reason = String(data["death_reason"])
	result.applied_passage_ids = parsed_ids
	return result if bool(result.validate().get("ok", false)) else null


func clone() -> SurvivalState:
	return SurvivalState.from_dict(to_dict())


func replace_from(other: SurvivalState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	start_elapsed_minutes = other.start_elapsed_minutes
	processed_elapsed_minutes = other.processed_elapsed_minutes
	remainders = other.remainders.duplicate(true)
	status = other.status
	death_reason = other.death_reason
	applied_passage_ids = other.applied_passage_ids.duplicate(true)
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	if start_elapsed_minutes < 0:
		errors.append("start_elapsed_minutes не может быть отрицательным")
	if processed_elapsed_minutes < start_elapsed_minutes:
		errors.append("processed_elapsed_minutes не может предшествовать началу")
	if processed_elapsed_minutes > week_end_elapsed_minutes():
		errors.append("прогресс не может выходить за границу семидневного прототипа")
	if remainders.size() != REMAINDER_KEYS.size():
		errors.append("remainders должен содержать точный набор потребностей")
	for key: String in REMAINDER_KEYS:
		if not remainders.has(key) or typeof(remainders.get(key)) != TYPE_INT:
			errors.append("remainders.%s должен быть целым числом" % key)
		elif int(remainders[key]) < 0 or int(remainders[key]) >= FIXED_DENOMINATOR:
			errors.append("remainders.%s находится вне диапазона" % key)
	if status not in STATUSES:
		errors.append("неизвестный статус жизненного цикла")
	if status == STATUS_DEAD and death_reason.strip_edges().is_empty():
		errors.append("смерть должна иметь причину")
	if status != STATUS_DEAD and not death_reason.is_empty():
		errors.append("причина смерти допустима только для dead")
	if status == STATUS_ACTIVE and processed_elapsed_minutes >= week_end_elapsed_minutes():
		errors.append("активная неделя уже достигла границы завершения")
	if status == STATUS_WEEK_COMPLETE and processed_elapsed_minutes != week_end_elapsed_minutes():
		errors.append("week_complete допустим только на точной границе недели")
	for raw_id: Variant in applied_passage_ids:
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty():
			errors.append("идентификатор подтверждённого прохода должен быть строкой")
		elif typeof(applied_passage_ids[raw_id]) != TYPE_BOOL or not bool(applied_passage_ids[raw_id]):
			errors.append("ledger проходов хранит только true")
	return {"ok": errors.is_empty(), "errors": errors}


static func _empty_remainders() -> Dictionary:
	var result: Dictionary = {}
	for key: String in REMAINDER_KEYS:
		result[key] = 0
	return result

