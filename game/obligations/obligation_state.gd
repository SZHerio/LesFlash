class_name ObligationState
extends RefCounted

## What the hero owes, and by when.
##
## This is the thing that makes a month different from a week. Everything else
## in the game is a decision he makes today about today; an obligation is a
## decision he made a week ago arriving to be paid for, whether or not today is
## a good day for it.
##
## Three kinds, and they differ only in who is owed and what happens when the
## day comes and nothing is paid:
##   rent    — the room goes, and the landlord remembers
##   debt    — the man who lent it remembers, and tells others
##   promise — nothing is taken, but somebody was let down
##
## Nothing here decides anything. It records what was taken on and what was
## paid; deciding is somebody else's job.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1

const RENT := "rent"
const DEBT := "debt"
const PROMISE := "promise"
const KINDS := [RENT, DEBT, PROMISE]

## Missing this many times ends the arrangement for good. Three is the same
## count the yard uses before it stops putting a man on shift, and for the same
## reason: twice is bad luck, three times is who you are.
const MISSES_BEFORE_BROKEN := 3

## obligation_id -> record. A record is:
##   {kind, title, amount_ard, due_at_minute, every_minutes, creditor_id,
##    missed, broken}
## `every_minutes` above zero means it comes round again — rent does, a debt
## does not.
var records: Dictionary = {}


static func fresh() -> ObligationState:
	return ObligationState.new()


func has(obligation_id: String) -> bool:
	return records.has(obligation_id)


func record_of(obligation_id: String) -> Dictionary:
	var record: Variant = records.get(obligation_id, {})
	return Dictionary(record).duplicate(true) if record is Dictionary else {}


func take_on(
	obligation_id: String,
	kind: String,
	title: String,
	amount_ard: int,
	due_at_minute: int,
	every_minutes: int = 0,
	creditor_id: String = ""
) -> bool:
	if obligation_id.strip_edges().is_empty() or records.has(obligation_id):
		return false
	if kind not in KINDS or title.strip_edges().is_empty():
		return false
	if amount_ard < 0 or due_at_minute < 0 or every_minutes < 0:
		return false
	records[obligation_id] = {
		"kind": kind,
		"title": title,
		"amount_ard": amount_ard,
		"due_at_minute": due_at_minute,
		"every_minutes": every_minutes,
		"creditor_id": creditor_id,
		"missed": 0,
		"broken": false,
	}
	return true


## Everything due at or before this minute and not yet broken.
func due_by(elapsed_minutes: int) -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in records:
		var record: Dictionary = records[raw_id]
		if bool(record.get("broken", false)):
			continue
		if int(record.get("due_at_minute", 0)) <= elapsed_minutes:
			result.append(String(raw_id))
	result.sort()
	return result


## Paid. A recurring obligation moves to its next date; a one-off is done with
## and leaves the ledger entirely.
func settle(obligation_id: String) -> bool:
	if not records.has(obligation_id):
		return false
	var record: Dictionary = records[obligation_id]
	if bool(record.get("broken", false)):
		return false
	var every := int(record.get("every_minutes", 0))
	if every <= 0:
		records.erase(obligation_id)
		return true
	record["due_at_minute"] = int(record.get("due_at_minute", 0)) + every
	record["missed"] = 0
	return true


## The day came and nothing was paid. Returns true when this was the last
## straw — the arrangement is over and whatever it granted is gone.
func miss(obligation_id: String) -> bool:
	if not records.has(obligation_id):
		return false
	var record: Dictionary = records[obligation_id]
	if bool(record.get("broken", false)):
		return false
	record["missed"] = int(record.get("missed", 0)) + 1
	var every := int(record.get("every_minutes", 0))
	if every > 0:
		# A missed rent day still moves on; what accumulates is the count, and
		# the count is what ends it.
		record["due_at_minute"] = int(record.get("due_at_minute", 0)) + every
	if int(record["missed"]) >= MISSES_BEFORE_BROKEN or every <= 0:
		record["broken"] = true
		return true
	return false


func forget(obligation_id: String) -> bool:
	return records.erase(obligation_id)


func is_broken(obligation_id: String) -> bool:
	return bool(record_of(obligation_id).get("broken", false))


func total_owed() -> int:
	var total := 0
	for raw_id: Variant in records:
		var record: Dictionary = records[raw_id]
		if not bool(record.get("broken", false)):
			total += int(record.get("amount_ard", 0))
	return total


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "records": records.duplicate(true)}


static func from_dict(data: Variant) -> ObligationState:
	if not data is Dictionary:
		return null
	var source: Dictionary = data
	if int(source.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := ObligationState.new()
	var raw: Variant = source.get("records", {})
	if not raw is Dictionary:
		return null
	for raw_id: Variant in Dictionary(raw):
		var record: Variant = Dictionary(raw)[raw_id]
		if not record is Dictionary:
			return null
		state.records[String(raw_id)] = Dictionary(record).duplicate(true)
	var validation := state.validate()
	return state if bool(validation.get("ok", false)) else null


func clone() -> ObligationState:
	var copy := ObligationState.new()
	copy.records = records.duplicate(true)
	return copy


func replace_from(other: ObligationState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	records = other.records.duplicate(true)
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(JsonValidator.validate(to_dict(), "obligation_state").get("errors", [])):
		errors.append(String(raw))
	for raw_id: Variant in records:
		var path := "obligation_state.%s" % String(raw_id)
		if typeof(raw_id) != TYPE_STRING or String(raw_id).strip_edges().is_empty():
			errors.append("obligation_state содержит пустой идентификатор")
			continue
		if not records[raw_id] is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var record: Dictionary = records[raw_id]
		if String(record.get("kind", "")) not in KINDS:
			errors.append("%s.kind неизвестен" % path)
		if String(record.get("title", "")).strip_edges().is_empty():
			errors.append("%s.title пуст" % path)
		for field: String in ["amount_ard", "due_at_minute", "every_minutes", "missed"]:
			var value: Variant = record.get(field, null)
			if typeof(value) != TYPE_INT or int(value) < 0:
				errors.append("%s.%s должен быть неотрицательным целым" % [path, field])
		if typeof(record.get("broken", null)) != TYPE_BOOL:
			errors.append("%s.broken должен быть логическим" % path)
	return {"ok": errors.is_empty(), "errors": errors}
