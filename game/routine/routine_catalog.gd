class_name RoutineCatalog
extends RefCounted

## What a person can put in their week.
##
## An activity here is not a new mechanic — every one of them is something the
## hero can already do by walking somewhere and confirming. The catalog exists so
## that doing it can be *planned* instead of chosen afresh every morning, and so
## that the planner knows what a plan costs before the week starts.
##
## Deliberately small. A routine made of thirty entries is a spreadsheet; one
## made of ten is a life someone could describe out loud.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "routine_catalog_v1"
const DEFAULT_PATH := "res://game/routine/data/routine_catalog_v1.json"

## Every kind the runner knows how to carry out. A catalog naming anything else
## would plan a day the runner cannot live.
const KINDS := ["job_shift", "search", "recycle", "meal", "stock", "npc", "shelter", "rest"]

## One list, in CityPlaces. Six catalogs used to carry their own copy of this.
const KNOWN_LOCATION_IDS := CityPlaces.PLACES

## Longest a single planned activity may run. Anything past this is not one
## stretch of a day, it is the whole day, and the plan stops describing a week.
const MAX_ACTIVITY_MINUTES := 8 * 60

## The most stretches one activity may take. Three is a working day plus its
## evening; anything longer is not an activity, it is the day itself.
const MAX_BLOCKS_USED := 3


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var entries := Rules.index_entries(
		catalog.get("activities", null), "activities", "routine_", errors
	)
	var kinds_seen: Dictionary = {}
	for activity_id: String in entries:
		var entry: Dictionary = entries[activity_id]
		var path := "activities.%s" % activity_id
		for field: String in ["title", "description"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		var kind := String(entry.get("kind", ""))
		if kind not in KINDS:
			errors.append("%s.kind должен быть одним из: %s" % [path, ", ".join(KINDS)])
		else:
			kinds_seen[kind] = true
		if entry.has("location_id") and String(entry["location_id"]) not in KNOWN_LOCATION_IDS:
			errors.append("%s.location_id неизвестен" % path)
		Rules.validate_int_range(
			entry.get("minutes", null), 0, MAX_ACTIVITY_MINUTES, "%s.minutes" % path, errors
		)
		# What counts as knowing this by heart. One repeat is not a habit and
		# twenty is a grind nobody finishes.
		Rules.validate_int_range(
			entry.get("mastery_repeats", null), 2, 12, "%s.mastery_repeats" % path, errors
		)
		_validate_blocks(entry.get("blocks", null), path, errors)
		# How much of the day it actually takes. A six-hour shift occupying one
		# stretch let a plan put shopping in the afternoon and then arrive at a
		# counter that had shut hours ago; the plan has to say what it costs.
		Rules.validate_int_range(
			entry.get("blocks_used", null), 1, MAX_BLOCKS_USED, "%s.blocks_used" % path, errors
		)
		_validate_span_fits(entry, path, errors)
	# A week has to be liveable from the catalog alone: something to earn with,
	# something to eat, and somewhere to sleep.
	for required_kind: String in ["job_shift", "meal", "shelter"]:
		if not kinds_seen.has(required_kind):
			errors.append("каталог не предлагает ни одного занятия вида %s" % required_kind)
	return {"ok": errors.is_empty(), "errors": errors}


## The stretches of the day this activity fits in. A night shelter offered in the
## morning, or a shift offered at night, is a plan that can never be kept.
static func _validate_blocks(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or Array(value).is_empty():
		errors.append("%s.blocks должен быть непустым массивом" % path)
		return
	var seen: Dictionary = {}
	for raw_block: Variant in Array(value):
		var block_id := String(raw_block)
		if not WeekSchedule.is_block(block_id):
			errors.append("%s.blocks содержит неизвестное время суток %s" % [path, block_id])
			continue
		if seen.has(block_id):
			errors.append("%s.blocks повторяет %s" % [path, block_id])
		seen[block_id] = true


## An activity that starts where it cannot finish is a plan nobody can keep: a
## shift beginning in the evening would run into the night, which is for sleep.
static func _validate_span_fits(entry: Dictionary, path: String, errors: Array[String]) -> void:
	var span := int(entry.get("blocks_used", 1))
	if span <= 1:
		return
	for raw_block: Variant in Array(entry.get("blocks", [])):
		var block_id := String(raw_block)
		var index := WeekSchedule.BLOCK_IDS.find(block_id)
		if index < 0:
			continue
		if index + span > WeekSchedule.BLOCK_IDS.size():
			errors.append(
				"%s начинается в %s, но занимает %d отрезка — день кончится раньше"
					% [path, block_id, span]
			)


static func blocks_used(entry: Dictionary) -> int:
	return maxi(int(entry.get("blocks_used", 1)), 1)


## Which activity holds this stretch of a planned day — the one written into it,
## or an earlier one that has not finished yet. Empty means the stretch is free.
static func holder_of(catalog: Dictionary, day_plan: Dictionary, block_id: String) -> Dictionary:
	var target := WeekSchedule.BLOCK_IDS.find(block_id)
	if target < 0:
		return {}
	for index: int in range(target, -1, -1):
		var candidate_block := String(WeekSchedule.BLOCK_IDS[index])
		var activity_id := String(day_plan.get(candidate_block, ""))
		if activity_id.is_empty():
			continue
		var entry := find(catalog, activity_id)
		if entry.is_empty():
			continue
		if index + blocks_used(entry) > target:
			return {
				"activity_id": activity_id,
				"entry": entry,
				"starts_block": candidate_block,
				"spills": index != target,
			}
		# The nearest written activity ended before this stretch, and anything
		# written earlier ended sooner still.
		return {}
	return {}


static func find(catalog: Dictionary, activity_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("activities", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == activity_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


## Everything that can be planned into one stretch of the day.
static func for_block(catalog: Dictionary, block_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry: Variant in Array(catalog.get("activities", [])):
		if not raw_entry is Dictionary:
			continue
		if block_id in Array(Dictionary(raw_entry).get("blocks", [])):
			result.append(Dictionary(raw_entry).duplicate(true))
	return result
