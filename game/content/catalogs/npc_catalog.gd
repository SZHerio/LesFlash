class_name NpcDefinitionCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "npc_catalog_v1"
const DEFAULT_PATH := "res://game/content/data/npc_catalog_v1.json"
const SENTENCE_LENGTHS := ["short", "mixed", "long"]
const APPEARANCE_KINDS := [
	"location", "knowledge", "job", "world_process", "world_metric", "reputation",
]
## One list, in CityPlaces. Six catalogs used to carry their own copy of this.
const KNOWN_LOCATION_IDS := CityPlaces.PLACES


static var _default_cache: Dictionary = {}


## Content files are immutable at run time, so the parse and the full
## validation happen once. Callers still receive their own deep copy, which
## keeps the previous contract exactly: nobody can mutate a shared catalog.
static func load_default() -> Dictionary:
	if _default_cache.is_empty():
		_default_cache = load_path(DEFAULT_PATH)
	return _cached_copy(_default_cache)


static func reset_cache_for_tests() -> void:
	_default_cache = {}


static func _cached_copy(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	return result


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var speech_profiles := Rules.index_entries(
		catalog.get("speech_profiles", null),
		"speech_profiles",
		"speech_profile_",
		errors
	)
	var schedules := Rules.index_entries(
		catalog.get("schedules", null), "schedules", "schedule_", errors
	)
	var npcs := Rules.index_entries(catalog.get("npcs", null), "npcs", "npc_", errors)
	_validate_speech_profiles(speech_profiles, errors)
	_validate_schedules(schedules, errors)
	_validate_npcs(npcs, schedules, speech_profiles, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_speech_profiles(
	profiles: Dictionary,
	errors: Array[String]
) -> void:
	for profile_id: String in profiles:
		var profile: Dictionary = profiles[profile_id]
		var path := "speech_profiles.%s" % profile_id
		if String(profile.get("sentence_length", "")) not in SENTENCE_LENGTHS:
			errors.append("%s.sentence_length неизвестен" % path)
		Rules.validate_id_array(
			profile.get("vocabulary_ids", null),
			"%s.vocabulary_ids" % path,
			errors,
			true
		)
		Rules.validate_text(profile.get("style_notes", null), "%s.style_notes" % path, errors)
		if profile.has("phonetic_accent") or profile.has("dialect_text"):
			errors.append("%s не должен задавать фонетический акцент или диалект" % path)


static func _validate_schedules(schedules: Dictionary, errors: Array[String]) -> void:
	for schedule_id: String in schedules:
		var schedule: Dictionary = schedules[schedule_id]
		var path := "schedules.%s" % schedule_id
		var entries: Variant = schedule.get("entries", null)
		if not entries is Array or entries.is_empty():
			errors.append("%s.entries должен быть непустым массивом" % path)
			continue
		var occupied: Dictionary = {}
		for index: int in entries.size():
			var raw_entry: Variant = entries[index]
			var entry_path := "%s.entries[%d]" % [path, index]
			if not raw_entry is Dictionary:
				errors.append("%s должен быть объектом" % entry_path)
				continue
			var entry: Dictionary = raw_entry
			var location_id := String(entry.get("location_id", ""))
			if location_id not in KNOWN_LOCATION_IDS:
				errors.append("%s.location_id неизвестен: %s" % [entry_path, location_id])
			Rules.validate_int_range(
				entry.get("start_minute", null), 0, 1439, "%s.start_minute" % entry_path, errors
			)
			Rules.validate_int_range(
				entry.get("end_minute", null), 1, 1440, "%s.end_minute" % entry_path, errors
			)
			var start_minute := int(entry.get("start_minute", -1))
			var end_minute := int(entry.get("end_minute", -1))
			if start_minute >= end_minute:
				errors.append("%s должен иметь start_minute < end_minute" % entry_path)
			_validate_days(entry.get("days", null), entry_path, occupied, start_minute, end_minute, errors)


static func _validate_days(
	raw_days: Variant,
	entry_path: String,
	occupied: Dictionary,
	start_minute: int,
	end_minute: int,
	errors: Array[String]
) -> void:
	if not raw_days is Array or raw_days.is_empty():
		errors.append("%s.days должен быть непустым массивом" % entry_path)
		return
	var seen_days: Dictionary = {}
	for index: int in raw_days.size():
		var raw_day: Variant = raw_days[index]
		if typeof(raw_day) != TYPE_INT or int(raw_day) < 1 or int(raw_day) > 7:
			errors.append("%s.days[%d] должен быть днём 1..7" % [entry_path, index])
			continue
		var day := int(raw_day)
		if seen_days.has(day):
			errors.append("%s.days повторяет день %d" % [entry_path, day])
			continue
		seen_days[day] = true
		for raw_interval: Variant in occupied.get(day, []):
			var interval: Vector2i = raw_interval
			if start_minute < interval.y and end_minute > interval.x:
				errors.append("%s пересекается с другим интервалом дня %d" % [entry_path, day])
		var intervals: Array = occupied.get(day, [])
		intervals.append(Vector2i(start_minute, end_minute))
		occupied[day] = intervals


static func _validate_npcs(
	npcs: Dictionary,
	schedules: Dictionary,
	profiles: Dictionary,
	errors: Array[String]
) -> void:
	for npc_id: String in npcs:
		var npc: Dictionary = npcs[npc_id]
		var path := "npcs.%s" % npc_id
		Rules.validate_text(npc.get("display_name", null), "%s.display_name" % path, errors)
		Rules.validate_text(npc.get("role_title", null), "%s.role_title" % path, errors)
		Rules.validate_text(npc.get("goal", null), "%s.goal" % path, errors)
		var schedule_id := String(npc.get("schedule_id", ""))
		if not schedules.has(schedule_id):
			errors.append("%s.schedule_id ссылается на неизвестное расписание" % path)
		var speech_profile_id := String(npc.get("speech_profile_id", ""))
		if not profiles.has(speech_profile_id):
			errors.append("%s.speech_profile_id ссылается на неизвестный профиль" % path)
		_validate_gift_preferences(npc.get("gift_preferences", null), path, errors)
		_validate_appearance_refs(npc.get("appearance_refs", null), path, errors)


## Who takes what is a fact about the person, not about the item, so it is
## authored here. A tag cannot be both valued and refused by the same NPC.
static func _validate_gift_preferences(
	raw_preferences: Variant,
	path: String,
	errors: Array[String]
) -> void:
	if raw_preferences == null:
		return
	var preference_path := "%s.gift_preferences" % path
	if not raw_preferences is Dictionary:
		errors.append("%s должен быть объектом" % preference_path)
		return
	var preferences: Dictionary = raw_preferences
	var valued: Array = Array(preferences.get("valued_tags", []))
	var refused: Array = Array(preferences.get("refused_tags", []))
	for field: String in ["valued_tags", "refused_tags"]:
		if not preferences.get(field, []) is Array:
			errors.append("%s.%s должен быть массивом" % [preference_path, field])
			continue
		for raw_tag: Variant in Array(preferences.get(field, [])):
			if typeof(raw_tag) != TYPE_STRING or String(raw_tag).strip_edges().is_empty():
				errors.append("%s.%s содержит пустой тег" % [preference_path, field])
	for raw_tag: Variant in valued:
		if String(raw_tag) in refused:
			errors.append("%s не может ценить и отвергать тег %s" % [preference_path, String(raw_tag)])
	for field: String in ["accepted_note", "refused_note"]:
		if preferences.has(field):
			Rules.validate_text(preferences[field], "%s.%s" % [preference_path, field], errors)


static func _validate_appearance_refs(
	raw_refs: Variant,
	path: String,
	errors: Array[String]
) -> void:
	if not raw_refs is Array or raw_refs.size() < 3:
		errors.append("%s.appearance_refs должен содержать минимум три контекста" % path)
		return
	var seen: Dictionary = {}
	for index: int in raw_refs.size():
		var raw_ref: Variant = raw_refs[index]
		var ref_path := "%s.appearance_refs[%d]" % [path, index]
		if not raw_ref is Dictionary:
			errors.append("%s должен быть объектом" % ref_path)
			continue
		var kind := String(raw_ref.get("kind", ""))
		var ref_id := String(raw_ref.get("id", ""))
		if kind not in APPEARANCE_KINDS:
			errors.append("%s.kind неизвестен" % ref_path)
		if not Rules.valid_id(ref_id):
			errors.append("%s.id некорректен" % ref_path)
		var key := "%s:%s" % [kind, ref_id]
		if seen.has(key):
			errors.append("%s повторяет контекст %s" % [ref_path, key])
		seen[key] = true


static func npcs(catalog: Dictionary) -> Array:
	return Array(catalog.get("npcs", [])).duplicate(true)
