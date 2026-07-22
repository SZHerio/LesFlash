class_name RunState
extends RefCounted

## Complete mutable state of one M1 run.
##
## Content should not mutate these fields directly. Rule/effect systems are
## expected to work on a clone and commit through replace_from(), which keeps the
## original RunState object identity while making a decision atomic.

var characteristics: Dictionary = GameRules.default_characteristics()
var meters: Dictionary = GameRules.default_meters()
var money: int = 0
var inventory: Dictionary = {}

var stored_polarities: Dictionary = GameRules.default_stored_polarities()
var computed_profiles: Dictionary = GameRules.default_computed_profiles()

var skills: Dictionary = GameRules.default_skills()
var mastery_points: int = 0
var knowledge: Dictionary = {}

var calendar: GameCalendar = GameCalendar.new()
var birth_date: Dictionary = {}

var journal: Array = []
var deferred_consequences: Array = []
var rng: DeterministicRng = DeterministicRng.new()

var _next_journal_sequence: int = 0


var age_years: int:
	get:
		return get_age_years()


func _init(
	initial_characteristics: Dictionary = {},
	rng_seed: int = GameRules.DEFAULT_RNG_SEED,
	calendar_config: Dictionary = {},
	start_stamp: Dictionary = {}
) -> void:
	calendar = GameCalendar.new(calendar_config, start_stamp)
	rng = DeterministicRng.new(rng_seed)
	birth_date = _birth_date_for_age(GameRules.START_AGE_YEARS)
	if not initial_characteristics.is_empty():
		set_characteristics(initial_characteristics)


func set_characteristics(values: Dictionary) -> bool:
	if not GameRules.characteristics_use_budget(values):
		return false
	characteristics = values.duplicate(true)
	return true


func get_characteristic(key: String) -> int:
	return int(characteristics.get(key, 0))


func set_characteristic(key: String, value: int) -> bool:
	if not GameRules.is_known_characteristic(key):
		return false
	var candidate := characteristics.duplicate(true)
	candidate[key] = value
	return set_characteristics(candidate)


func change_characteristic(key: String, delta: int) -> bool:
	return set_characteristic(key, get_characteristic(key) + delta)


func redistribute_characteristic(from_key: String, to_key: String, points: int) -> bool:
	if points < 0 or from_key == to_key:
		return false
	if not GameRules.is_known_characteristic(from_key) or not GameRules.is_known_characteristic(to_key):
		return false
	var candidate := characteristics.duplicate(true)
	candidate[from_key] = int(candidate[from_key]) - points
	candidate[to_key] = int(candidate[to_key]) + points
	return set_characteristics(candidate)


func get_meter(key: String) -> int:
	return int(meters.get(key, 0))


func set_meter(key: String, value: int) -> bool:
	if not GameRules.is_known_meter(key):
		return false
	meters[key] = GameRules.clamp_meter(value)
	return true


func change_meter(key: String, delta: int) -> int:
	if not GameRules.is_known_meter(key):
		return 0
	var previous := get_meter(key)
	set_meter(key, previous + delta)
	return get_meter(key) - previous


func set_money(value: int) -> bool:
	if value < GameRules.MONEY_MIN or value > GameRules.MONEY_MAX:
		return false
	money = value
	return true


func change_money(delta: int) -> bool:
	if delta > 0 and money > GameRules.MONEY_MAX - delta:
		return false
	if delta < 0 and money < GameRules.MONEY_MIN - delta:
		return false
	return set_money(money + delta)


func get_item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	var current := get_item_count(item_id)
	if current > GameRules.INVENTORY_QUANTITY_MAX - quantity:
		return false
	inventory[item_id] = current + quantity
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	var current := get_item_count(item_id)
	if current < quantity:
		return false
	var remaining := current - quantity
	if remaining == 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = remaining
	return true


func get_polarity(key: String) -> int:
	if GameRules.is_stored_polarity(key):
		return int(stored_polarities.get(key, 0))
	if GameRules.is_computed_profile(key):
		var profile: Dictionary = computed_profiles.get(key, {})
		return int(profile.get("value", 0)) if bool(profile.get("formed", false)) else 0
	return 0


func set_polarity(key: String, value: int) -> bool:
	if not GameRules.is_stored_polarity(key):
		return false
	stored_polarities[key] = GameRules.clamp_polarity(value)
	return true


func shift_polarity(key: String, delta: int) -> int:
	if not GameRules.is_stored_polarity(key):
		return 0
	var previous := int(stored_polarities[key])
	set_polarity(key, previous + delta)
	return int(stored_polarities[key]) - previous


func get_computed_profile(key: String) -> Dictionary:
	if not GameRules.is_computed_profile(key):
		return {}
	return Dictionary(computed_profiles[key]).duplicate(true)


func set_computed_profile(
	key: String,
	value: int,
	evidence: int,
	formed_override: Variant = null
) -> bool:
	if not GameRules.is_computed_profile(key) or evidence < 0 or evidence > GameRules.MASTERY_POINTS_MAX:
		return false
	var formed := evidence >= GameRules.PROFILE_FORMATION_EVIDENCE
	if formed_override != null:
		if typeof(formed_override) != TYPE_BOOL:
			return false
		formed = formed_override
	if formed and evidence < GameRules.PROFILE_FORMATION_EVIDENCE:
		return false
	computed_profiles[key] = {
		"value": GameRules.clamp_polarity(value) if formed else 0,
		"formed": formed,
		"evidence": evidence,
	}
	return true


func get_skill_rank(key: String) -> int:
	return int(skills.get(key, 0))


func set_skill_rank(key: String, rank: int) -> bool:
	if not GameRules.is_known_skill(key):
		return false
	if rank < GameRules.SKILL_MIN_RANK or rank > GameRules.SKILL_MAX_RANK:
		return false
	skills[key] = rank
	return true


func add_mastery_points(amount: int) -> bool:
	if amount < 0 or mastery_points > GameRules.MASTERY_POINTS_MAX - amount:
		return false
	mastery_points += amount
	return true


func spend_mastery_points(amount: int) -> bool:
	if amount < 0 or amount > mastery_points:
		return false
	mastery_points -= amount
	return true


func has_knowledge(tag: String, minimum_level: int = GameRules.KNOWLEDGE_LEVEL_MIN) -> bool:
	return get_knowledge_level(tag) >= minimum_level


func get_knowledge_level(tag: String) -> int:
	return int(knowledge.get(tag, 0))


func set_knowledge_level(tag: String, level: int = GameRules.KNOWLEDGE_LEVEL_MIN) -> bool:
	if tag.is_empty() or level < GameRules.KNOWLEDGE_LEVEL_MIN or level > GameRules.KNOWLEDGE_LEVEL_MAX:
		return false
	knowledge[tag] = level
	return true


func remove_knowledge(tag: String) -> bool:
	return knowledge.erase(tag)


func get_age_years() -> int:
	if birth_date.is_empty() or calendar == null:
		return 0
	var result := calendar.year - int(birth_date.get("year", calendar.year))
	var birth_month := int(birth_date.get("month", calendar.month))
	var birth_day := int(birth_date.get("day", calendar.day))
	if calendar.month < birth_month or (calendar.month == birth_month and calendar.day < birth_day):
		result -= 1
	return maxi(result, 0)


func advance_time(minutes: int, reason: String = "", payload: Dictionary = {}) -> bool:
	if minutes < 0 or calendar == null:
		return false
	var payload_errors: Array[String] = []
	_validate_json_value(payload, "time_payload", payload_errors)
	if not payload_errors.is_empty():
		return false
	if not calendar.advance_minutes(minutes):
		return false
	var journal_payload := payload.duplicate(true)
	journal_payload["minutes"] = minutes
	var message := reason if not reason.is_empty() else "time_advanced"
	return add_journal_entry("time", message, journal_payload)


func add_journal_entry(
	entry_type: String,
	message: String,
	payload: Dictionary = {},
	entry_id: String = ""
) -> bool:
	if entry_type.is_empty() or calendar == null:
		return false
	var payload_errors: Array[String] = []
	_validate_json_value(payload, "journal.payload", payload_errors)
	if not payload_errors.is_empty():
		return false
	var canonical_payload: Dictionary = _normalize_json_numbers(payload)
	var resolved_id := entry_id
	if resolved_id.is_empty():
		resolved_id = "%s:%d" % [entry_type, _next_journal_sequence]
	journal.append({
		"sequence": _next_journal_sequence,
		"id": resolved_id,
		"at": calendar.current_stamp(),
		"type": entry_type,
		"message": message,
		"payload": canonical_payload,
	})
	_next_journal_sequence += 1
	return true


func schedule_consequence(
	consequence_id: String,
	due: Dictionary,
	effect_id: String,
	payload: Dictionary = {},
	source_id: String = ""
) -> bool:
	if consequence_id.is_empty() or effect_id.is_empty() or calendar == null:
		return false
	if not calendar.is_valid_stamp(due, false):
		return false
	for existing in deferred_consequences:
		if String(existing.get("id", "")) == consequence_id:
			return false
	var payload_errors: Array[String] = []
	_validate_json_value(payload, "deferred.payload", payload_errors)
	if not payload_errors.is_empty():
		return false
	var canonical_payload: Dictionary = _normalize_json_numbers(payload)
	deferred_consequences.append({
		"id": consequence_id,
		"due": _normalized_stamp(due),
		"effect_id": effect_id,
		"payload": canonical_payload,
		"source_id": source_id,
	})
	return true


func schedule_consequence_after(
	consequence_id: String,
	minutes_from_now: int,
	effect_id: String,
	payload: Dictionary = {},
	source_id: String = ""
) -> bool:
	if minutes_from_now < 0 or calendar == null:
		return false
	var due := calendar.future_stamp(minutes_from_now)
	if due.is_empty():
		return false
	return schedule_consequence(consequence_id, due, effect_id, payload, source_id)


func cancel_consequence(consequence_id: String) -> bool:
	for index in range(deferred_consequences.size()):
		if String(deferred_consequences[index].get("id", "")) == consequence_id:
			deferred_consequences.remove_at(index)
			return true
	return false


func take_due_consequences() -> Array:
	var due: Array = []
	var pending: Array = []
	for consequence in deferred_consequences:
		if calendar.is_stamp_due(consequence.get("due", {})):
			due.append(Dictionary(consequence).duplicate(true))
		else:
			pending.append(consequence)
	deferred_consequences = pending
	return due


func to_dict() -> Dictionary:
	return {
		"save_version": GameRules.SAVE_VERSION,
		"characteristics": characteristics.duplicate(true),
		"meters": meters.duplicate(true),
		"money": money,
		"inventory": inventory.duplicate(true),
		"stored_polarities": stored_polarities.duplicate(true),
		"computed_profiles": computed_profiles.duplicate(true),
		"skills": skills.duplicate(true),
		"mastery_points": mastery_points,
		"knowledge": knowledge.duplicate(true),
		"calendar": calendar.to_dict(),
		"birth_date": birth_date.duplicate(true),
		"journal": journal.duplicate(true),
		"deferred_consequences": deferred_consequences.duplicate(true),
		"next_journal_sequence": _next_journal_sequence,
		"rng": rng.to_dict(),
	}


static func migrate_serialized(data: Dictionary) -> Dictionary:
	var source_version: Variant = _parse_integral(data.get("save_version", null))
	if source_version == null:
		return {
			"ok": false,
			"code": "invalid_run_state_version",
			"error": "RunState save_version must be an integer.",
		}
	if int(source_version) not in [GameRules.LEGACY_SAVE_VERSION, GameRules.SAVE_VERSION]:
		return {
			"ok": false,
			"code": "unsupported_run_state_version",
			"error": "RunState save version is unsupported.",
			"actual": int(source_version),
		}
	var migrated := data.duplicate(true)
	migrated["save_version"] = GameRules.SAVE_VERSION
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"data": migrated,
		"migrated": int(source_version) != GameRules.SAVE_VERSION,
		"source_version": int(source_version),
	}


static func from_dict(data: Dictionary) -> RunState:
	var migration := migrate_serialized(data)
	if not bool(migration.get("ok", false)):
		return null
	var source: Dictionary = migration["data"]

	var parsed_characteristics: Variant = _parse_int_map(
		source.get("characteristics", null),
		GameRules.CHARACTERISTIC_KEYS,
		GameRules.CHARACTERISTIC_MIN,
		GameRules.CHARACTERISTIC_MAX
	)
	var parsed_meters: Variant = _parse_int_map(
		source.get("meters", null),
		GameRules.METER_KEYS,
		GameRules.METER_MIN,
		GameRules.METER_MAX
	)
	var parsed_polarities: Variant = _parse_int_map(
		source.get("stored_polarities", null),
		GameRules.STORED_POLARITY_KEYS,
		GameRules.POLARITY_MIN,
		GameRules.POLARITY_MAX
	)
	var parsed_skills: Variant = _parse_int_map(
		source.get("skills", null),
		GameRules.SKILL_KEYS,
		GameRules.SKILL_MIN_RANK,
		GameRules.SKILL_MAX_RANK
	)
	if parsed_characteristics == null or parsed_meters == null or parsed_polarities == null or parsed_skills == null:
		return null
	if not GameRules.characteristics_use_budget(parsed_characteristics):
		return null

	var parsed_money: Variant = _parse_integral(source.get("money", null))
	var parsed_mastery: Variant = _parse_integral(source.get("mastery_points", null))
	var parsed_sequence: Variant = _parse_integral(source.get("next_journal_sequence", null))
	if parsed_money == null or int(parsed_money) < GameRules.MONEY_MIN or int(parsed_money) > GameRules.MONEY_MAX:
		return null
	if parsed_mastery == null or int(parsed_mastery) < GameRules.MASTERY_POINTS_MIN or int(parsed_mastery) > GameRules.MASTERY_POINTS_MAX:
		return null
	if parsed_sequence == null or int(parsed_sequence) < 0:
		return null

	var parsed_inventory: Variant = _parse_string_int_map(
		source.get("inventory", null),
		GameRules.INVENTORY_QUANTITY_MIN,
		GameRules.INVENTORY_QUANTITY_MAX
	)
	var parsed_knowledge: Variant = _parse_string_int_map(
		source.get("knowledge", null),
		GameRules.KNOWLEDGE_LEVEL_MIN,
		GameRules.KNOWLEDGE_LEVEL_MAX
	)
	var parsed_profiles: Variant = _parse_computed_profiles(source.get("computed_profiles", null))
	if parsed_inventory == null or parsed_knowledge == null or parsed_profiles == null:
		return null

	if typeof(source.get("calendar", null)) != TYPE_DICTIONARY or typeof(source.get("rng", null)) != TYPE_DICTIONARY:
		return null
	var parsed_calendar := GameCalendar.from_dict(source["calendar"])
	var parsed_rng := DeterministicRng.from_dict(source["rng"])
	if parsed_calendar == null or parsed_rng == null:
		return null

	var parsed_birth_date: Variant = _parse_birth_date(source.get("birth_date", null), parsed_calendar)
	if parsed_birth_date == null:
		return null

	if typeof(source.get("journal", null)) != TYPE_ARRAY or typeof(source.get("deferred_consequences", null)) != TYPE_ARRAY:
		return null
	var result := RunState.new()
	result.characteristics = parsed_characteristics
	result.meters = parsed_meters
	result.money = int(parsed_money)
	result.inventory = parsed_inventory
	result.stored_polarities = parsed_polarities
	result.computed_profiles = parsed_profiles
	result.skills = parsed_skills
	result.mastery_points = int(parsed_mastery)
	result.knowledge = parsed_knowledge
	result.calendar = parsed_calendar
	result.birth_date = parsed_birth_date
	result.rng = parsed_rng
	result._next_journal_sequence = int(parsed_sequence)
	if not result._load_journal(source["journal"]):
		return null
	if not result._load_deferred(source["deferred_consequences"]):
		return null
	var validation := result.validate()
	return result if validation["ok"] else null


func load_from_dict(data: Dictionary) -> bool:
	var parsed := RunState.from_dict(data)
	return false if parsed == null else replace_from(parsed)


func clone() -> RunState:
	# A malformed run must never turn into fresh defaults during a transaction.
	# ActionTransaction treats null as a hard failure and leaves the run intact.
	return RunState.from_dict(to_dict())


func replace_from(other: RunState) -> bool:
	if other == null:
		return false
	var validation := other.validate()
	if not validation["ok"]:
		return false
	characteristics = other.characteristics.duplicate(true)
	meters = other.meters.duplicate(true)
	money = other.money
	inventory = other.inventory.duplicate(true)
	stored_polarities = other.stored_polarities.duplicate(true)
	computed_profiles = other.computed_profiles.duplicate(true)
	skills = other.skills.duplicate(true)
	mastery_points = other.mastery_points
	knowledge = other.knowledge.duplicate(true)
	calendar = other.calendar.clone()
	birth_date = other.birth_date.duplicate(true)
	journal = other.journal.duplicate(true)
	deferred_consequences = other.deferred_consequences.duplicate(true)
	_next_journal_sequence = other._next_journal_sequence
	rng = other.rng.clone()
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	_validate_exact_int_map(
		characteristics,
		GameRules.CHARACTERISTIC_KEYS,
		GameRules.CHARACTERISTIC_MIN,
		GameRules.CHARACTERISTIC_MAX,
		"characteristics",
		errors
	)
	if not GameRules.characteristics_use_budget(characteristics):
		errors.append("characteristics must total %d points" % GameRules.CHARACTERISTIC_BUDGET)
	_validate_exact_int_map(meters, GameRules.METER_KEYS, GameRules.METER_MIN, GameRules.METER_MAX, "meters", errors)
	_validate_exact_int_map(
		stored_polarities,
		GameRules.STORED_POLARITY_KEYS,
		GameRules.POLARITY_MIN,
		GameRules.POLARITY_MAX,
		"stored_polarities",
		errors
	)
	_validate_exact_int_map(skills, GameRules.SKILL_KEYS, GameRules.SKILL_MIN_RANK, GameRules.SKILL_MAX_RANK, "skills", errors)
	_validate_computed_profiles(errors)

	if money < GameRules.MONEY_MIN or money > GameRules.MONEY_MAX:
		errors.append("money is outside allowed range")
	if mastery_points < GameRules.MASTERY_POINTS_MIN or mastery_points > GameRules.MASTERY_POINTS_MAX:
		errors.append("mastery_points is outside allowed range")
	_validate_string_int_map(
		inventory,
		GameRules.INVENTORY_QUANTITY_MIN,
		GameRules.INVENTORY_QUANTITY_MAX,
		"inventory",
		errors
	)
	_validate_string_int_map(
		knowledge,
		GameRules.KNOWLEDGE_LEVEL_MIN,
		GameRules.KNOWLEDGE_LEVEL_MAX,
		"knowledge",
		errors
	)

	if calendar == null:
		errors.append("calendar is null")
	else:
		_append_nested_errors("calendar", calendar.validate(), errors)
		if _parse_birth_date(birth_date, calendar) == null:
			errors.append("birth_date is invalid for the configured calendar")
		elif get_age_years() < GameRules.START_AGE_YEARS:
			errors.append("age cannot be lower than the starting age")
	if rng == null:
		errors.append("rng is null")
	else:
		_append_nested_errors("rng", rng.validate(), errors)
	if _next_journal_sequence < 0:
		errors.append("next_journal_sequence cannot be negative")
	_validate_journal(errors)
	_validate_deferred(errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
	}


func _load_journal(raw_entries: Array) -> bool:
	var parsed: Array = []
	for raw_entry in raw_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = raw_entry
		var sequence: Variant = _parse_integral(entry.get("sequence", null))
		if sequence == null or int(sequence) < 0:
			return false
		if typeof(entry.get("id", null)) != TYPE_STRING:
			return false
		if typeof(entry.get("type", null)) != TYPE_STRING or String(entry["type"]).is_empty():
			return false
		if typeof(entry.get("message", null)) != TYPE_STRING:
			return false
		if typeof(entry.get("at", null)) != TYPE_DICTIONARY or not calendar.is_valid_stamp(entry["at"], false):
			return false
		if typeof(entry.get("payload", null)) != TYPE_DICTIONARY:
			return false
		var payload_errors: Array[String] = []
		_validate_json_value(entry["payload"], "journal.payload", payload_errors)
		if not payload_errors.is_empty():
			return false
		parsed.append({
			"sequence": int(sequence),
			"id": String(entry["id"]),
			"at": _normalized_stamp(entry["at"]),
			"type": String(entry["type"]),
			"message": String(entry["message"]),
			"payload": _normalize_json_numbers(entry["payload"]),
		})
	journal = parsed
	return true


func _load_deferred(raw_consequences: Array) -> bool:
	var parsed: Array = []
	var seen_ids: Dictionary = {}
	for raw_consequence in raw_consequences:
		if typeof(raw_consequence) != TYPE_DICTIONARY:
			return false
		var consequence: Dictionary = raw_consequence
		for key in ["id", "effect_id", "source_id"]:
			if typeof(consequence.get(key, null)) != TYPE_STRING:
				return false
		var consequence_id := String(consequence["id"])
		if consequence_id.is_empty() or String(consequence["effect_id"]).is_empty() or seen_ids.has(consequence_id):
			return false
		if typeof(consequence.get("due", null)) != TYPE_DICTIONARY or not calendar.is_valid_stamp(consequence["due"], false):
			return false
		if typeof(consequence.get("payload", null)) != TYPE_DICTIONARY:
			return false
		var payload_errors: Array[String] = []
		_validate_json_value(consequence["payload"], "deferred.payload", payload_errors)
		if not payload_errors.is_empty():
			return false
		seen_ids[consequence_id] = true
		parsed.append({
			"id": consequence_id,
			"due": _normalized_stamp(consequence["due"]),
			"effect_id": String(consequence["effect_id"]),
			"payload": _normalize_json_numbers(consequence["payload"]),
			"source_id": String(consequence["source_id"]),
		})
	deferred_consequences = parsed
	return true


func _validate_computed_profiles(errors: Array[String]) -> void:
	if computed_profiles.size() != GameRules.COMPUTED_PROFILE_KEYS.size():
		errors.append("computed_profiles must contain exactly the configured profiles")
	for key in GameRules.COMPUTED_PROFILE_KEYS:
		if typeof(computed_profiles.get(key, null)) != TYPE_DICTIONARY:
			errors.append("computed_profiles.%s must be a dictionary" % key)
			continue
		var profile: Dictionary = computed_profiles[key]
		if profile.size() != 3 or not profile.has("value") or not profile.has("formed") or not profile.has("evidence"):
			errors.append("computed_profiles.%s has an invalid shape" % key)
			continue
		if typeof(profile["value"]) != TYPE_INT or int(profile["value"]) < GameRules.POLARITY_MIN or int(profile["value"]) > GameRules.POLARITY_MAX:
			errors.append("computed_profiles.%s.value is outside allowed range" % key)
		if typeof(profile["formed"]) != TYPE_BOOL:
			errors.append("computed_profiles.%s.formed must be boolean" % key)
		if (
			typeof(profile["evidence"]) != TYPE_INT
			or int(profile["evidence"]) < 0
			or int(profile["evidence"]) > GameRules.MASTERY_POINTS_MAX
		):
			errors.append("computed_profiles.%s.evidence is outside allowed integer range" % key)
		elif bool(profile["formed"]) and int(profile["evidence"]) < GameRules.PROFILE_FORMATION_EVIDENCE:
			errors.append("computed_profiles.%s is formed without enough evidence" % key)
		if typeof(profile["formed"]) == TYPE_BOOL and not bool(profile["formed"]) and int(profile.get("value", 0)) != 0:
			errors.append("computed_profiles.%s must be centered until formed" % key)


func _validate_journal(errors: Array[String]) -> void:
	var previous_sequence := -1
	for index in range(journal.size()):
		var entry: Variant = journal[index]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("journal[%d] must be a dictionary" % index)
			continue
		var sequence: Variant = entry.get("sequence", null)
		if typeof(sequence) != TYPE_INT or int(sequence) <= previous_sequence:
			errors.append("journal[%d].sequence must be strictly increasing" % index)
		else:
			previous_sequence = int(sequence)
		if typeof(entry.get("id", null)) != TYPE_STRING:
			errors.append("journal[%d].id must be a string" % index)
		if typeof(entry.get("type", null)) != TYPE_STRING or String(entry.get("type", "")).is_empty():
			errors.append("journal[%d].type must be a non-empty string" % index)
		if typeof(entry.get("message", null)) != TYPE_STRING:
			errors.append("journal[%d].message must be a string" % index)
		if calendar != null and (typeof(entry.get("at", null)) != TYPE_DICTIONARY or not calendar.is_valid_stamp(entry.get("at", {}), false)):
			errors.append("journal[%d].at is not a valid calendar stamp" % index)
		_validate_json_value(entry.get("payload", null), "journal[%d].payload" % index, errors)
	if previous_sequence >= _next_journal_sequence:
		errors.append("next_journal_sequence must be greater than every journal sequence")


func _validate_deferred(errors: Array[String]) -> void:
	var seen_ids: Dictionary = {}
	for index in range(deferred_consequences.size()):
		var consequence: Variant = deferred_consequences[index]
		if typeof(consequence) != TYPE_DICTIONARY:
			errors.append("deferred_consequences[%d] must be a dictionary" % index)
			continue
		var consequence_id := String(consequence.get("id", ""))
		if consequence_id.is_empty() or seen_ids.has(consequence_id):
			errors.append("deferred_consequences[%d].id is empty or duplicated" % index)
		else:
			seen_ids[consequence_id] = true
		if typeof(consequence.get("effect_id", null)) != TYPE_STRING or String(consequence.get("effect_id", "")).is_empty():
			errors.append("deferred_consequences[%d].effect_id must be a non-empty string" % index)
		if typeof(consequence.get("source_id", null)) != TYPE_STRING:
			errors.append("deferred_consequences[%d].source_id must be a string" % index)
		if calendar != null and (typeof(consequence.get("due", null)) != TYPE_DICTIONARY or not calendar.is_valid_stamp(consequence.get("due", {}), false)):
			errors.append("deferred_consequences[%d].due is not a valid calendar stamp" % index)
		_validate_json_value(consequence.get("payload", null), "deferred_consequences[%d].payload" % index, errors)


func _birth_date_for_age(age: int) -> Dictionary:
	var birth_year := calendar.year - age
	return {
		"year": birth_year,
		"month": calendar.month,
		"day": mini(calendar.day, calendar.days_in_month(birth_year, calendar.month)),
	}


static func _parse_birth_date(raw: Variant, target_calendar: GameCalendar) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY or target_calendar == null:
		return null
	var result: Dictionary = {}
	for key in ["year", "month", "day"]:
		var value: Variant = _parse_integral(raw.get(key, null))
		if value == null:
			return null
		result[key] = int(value)
	var stamp := result.duplicate(true)
	stamp["minute_of_day"] = 0
	if not target_calendar.is_valid_stamp(stamp, false):
		return null
	return result


static func _parse_computed_profiles(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY or raw.size() != GameRules.COMPUTED_PROFILE_KEYS.size():
		return null
	var result: Dictionary = {}
	for key in GameRules.COMPUTED_PROFILE_KEYS:
		if typeof(raw.get(key, null)) != TYPE_DICTIONARY:
			return null
		var source: Dictionary = raw[key]
		if source.size() != 3 or typeof(source.get("formed", null)) != TYPE_BOOL:
			return null
		var value: Variant = _parse_integral(source.get("value", null))
		var evidence: Variant = _parse_integral(source.get("evidence", null))
		if value == null or evidence == null:
			return null
		var formed: bool = source["formed"]
		if (
			int(value) < GameRules.POLARITY_MIN
			or int(value) > GameRules.POLARITY_MAX
			or int(evidence) < 0
			or int(evidence) > GameRules.MASTERY_POINTS_MAX
		):
			return null
		if formed and int(evidence) < GameRules.PROFILE_FORMATION_EVIDENCE:
			return null
		if not formed and int(value) != 0:
			return null
		result[key] = {
			"value": int(value),
			"formed": formed,
			"evidence": int(evidence),
		}
	return result


static func _parse_int_map(raw: Variant, keys: Array, minimum: int, maximum: int) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY or raw.size() != keys.size():
		return null
	var result: Dictionary = {}
	for key in keys:
		var value: Variant = _parse_integral(raw.get(key, null))
		if value == null or int(value) < minimum or int(value) > maximum:
			return null
		result[key] = int(value)
	return result


static func _parse_string_int_map(raw: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var result: Dictionary = {}
	for raw_key in raw:
		if typeof(raw_key) != TYPE_STRING or String(raw_key).is_empty():
			return null
		var value: Variant = _parse_integral(raw[raw_key])
		if value == null or int(value) < minimum or int(value) > maximum:
			return null
		result[String(raw_key)] = int(value)
	return result


static func _parse_integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var float_value := float(value)
	if not is_finite(float_value) or float_value != floor(float_value):
		return null
	if absf(float_value) > 9_007_199_254_740_991.0:
		return null
	return int(float_value)


static func _normalized_stamp(raw: Dictionary) -> Dictionary:
	var result := {
		"year": int(raw["year"]),
		"month": int(raw["month"]),
		"day": int(raw["day"]),
		"minute_of_day": int(raw["minute_of_day"]),
	}
	if raw.has("elapsed_minutes") and _parse_integral(raw["elapsed_minutes"]) != null:
		result["elapsed_minutes"] = int(raw["elapsed_minutes"])
	return result


static func _validate_exact_int_map(
	values: Dictionary,
	keys: Array,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	if values.size() != keys.size():
		errors.append("%s must contain exactly the configured keys" % path)
	for key in keys:
		if not values.has(key) or typeof(values[key]) != TYPE_INT:
			errors.append("%s.%s must be an integer" % [path, key])
			continue
		var value: int = values[key]
		if value < minimum or value > maximum:
			errors.append("%s.%s is outside allowed range" % [path, key])


static func _validate_string_int_map(
	values: Dictionary,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	for key in values:
		if typeof(key) != TYPE_STRING or String(key).is_empty():
			errors.append("%s keys must be non-empty strings" % path)
			continue
		if typeof(values[key]) != TYPE_INT or int(values[key]) < minimum or int(values[key]) > maximum:
			errors.append("%s.%s is outside allowed integer range" % [path, key])


static func _validate_json_value(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int = 0
) -> void:
	if depth > 32:
		errors.append("%s exceeds maximum nesting depth" % path)
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return
		TYPE_INT:
			var integer_value := int(value)
			if integer_value < -GameRules.JSON_SAFE_INTEGER_MAX or integer_value > GameRules.JSON_SAFE_INTEGER_MAX:
				errors.append("%s contains an integer outside JSON's exact range" % path)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("%s contains a non-finite number" % path)
		TYPE_ARRAY:
			for index in range(value.size()):
				_validate_json_value(value[index], "%s[%d]" % [path, index], errors, depth + 1)
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string dictionary key" % path)
					continue
				_validate_json_value(value[key], "%s.%s" % [path, key], errors, depth + 1)
		_:
			errors.append("%s contains a non-JSON value of type %s" % [path, type_string(typeof(value))])


## Godot's JSON parser returns open-ended numeric payloads as floats. Gameplay
## effects use integer quantities, so integral values are normalized on load to
## keep journal/deferred payloads stable across a save round-trip. Fractional
## values remain floats.
static func _normalize_json_numbers(value: Variant, depth: int = 0) -> Variant:
	if depth > 32:
		return null
	match typeof(value):
		TYPE_FLOAT:
			var numeric := float(value)
			if (
				is_finite(numeric)
				and numeric >= -float(GameRules.JSON_SAFE_INTEGER_MAX)
				and numeric <= float(GameRules.JSON_SAFE_INTEGER_MAX)
				and numeric == roundf(numeric)
			):
				return int(numeric)
			return numeric
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value:
				normalized_array.append(_normalize_json_numbers(item, depth + 1))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary: Dictionary = {}
			for key: Variant in value:
				normalized_dictionary[key] = _normalize_json_numbers(value[key], depth + 1)
			return normalized_dictionary
		_:
			return value


static func _append_nested_errors(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	if bool(validation.get("ok", false)):
		return
	var nested: Variant = validation.get("errors", [])
	if typeof(nested) != TYPE_ARRAY:
		errors.append("%s validation failed" % prefix)
		return
	for error in nested:
		errors.append("%s: %s" % [prefix, String(error)])
