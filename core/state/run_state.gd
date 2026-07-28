class_name RunState
extends RefCounted

## Complete mutable state of one M1 run.
##
## Content should not mutate these fields directly. Rule/effect systems are
## expected to work on a clone and commit through replace_from(), which keeps the
## original RunState object identity while making a decision atomic.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")

var characteristics: Dictionary = GameRules.default_characteristics()
var meters: Dictionary = GameRules.default_meters()
var money: int = 0
var inventory: Dictionary = InventoryStateScript.fresh()

var stored_polarities: Dictionary = GameRules.default_stored_polarities()
var computed_profiles: Dictionary = GameRules.default_computed_profiles()

var skills: Dictionary = GameRules.default_skills()
## skill_id -> distinct practice source ids. The rank above is derived from
## this, never set directly by content.
var skill_practice: Dictionary = GameRules.default_skill_practice()
## qualification_id -> elapsed minute it was granted. A skill says what the hero
## can do; this says what he is allowed to do, and the two are not the same.
var qualifications: Dictionary = {}
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
	return InventoryStateScript.item_count(inventory, item_id)


func add_item(
	item_id: String,
	quantity: int = 1,
	preferred_container: String = ""
) -> bool:
	var result := InventoryStateScript.add_item(
		inventory,
		item_id,
		quantity,
		100,
		preferred_container,
		get_characteristic("strength")
	)
	if not bool(result.get("ok", false)):
		return false
	inventory = result["inventory"]
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	var result := InventoryStateScript.remove_item(inventory, item_id, quantity)
	if not bool(result.get("ok", false)):
		return false
	inventory = result["inventory"]
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


## Records one confirmed use of a skill. Returns the rank after recording, so a
## caller can tell whether the practice mattered.
##
## Repetition is deliberately worthless: a source already recorded changes
## nothing. What raises a rank is having done different things with the skill.
## Records a granted qualification. Papers are never taken back here: losing one
## is an event with its own consequences, not bookkeeping.
func grant_qualification(qualification_id: String) -> bool:
	if qualification_id.strip_edges().is_empty() or qualifications.has(qualification_id):
		return false
	qualifications[qualification_id] = int(calendar.elapsed_minutes)
	return true


func holds_qualification(qualification_id: String) -> bool:
	return qualifications.has(qualification_id)


func record_practice(skill_id: String, source_id: String) -> int:
	if not GameRules.is_known_skill(skill_id) or source_id.strip_edges().is_empty():
		return get_skill_rank(skill_id)
	if not skill_practice.has(skill_id):
		skill_practice[skill_id] = []
	var sources: Array = skill_practice[skill_id]
	if not sources.has(source_id) and sources.size() < GameRules.SKILL_PRACTICE_SOURCES_MAX:
		sources.append(source_id)
	var earned := GameRules.rank_for_practice(sources.size())
	if earned > get_skill_rank(skill_id):
		set_skill_rank(skill_id, earned)
	return get_skill_rank(skill_id)


func practice_sources(skill_id: String) -> int:
	return Array(skill_practice.get(skill_id, [])).size()


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
	SerializedValue.validate_json_value(payload, "time_payload", payload_errors)
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
	SerializedValue.validate_json_value(payload, "journal.payload", payload_errors)
	if not payload_errors.is_empty():
		return false
	var canonical_payload: Dictionary = SerializedValue.normalize_json_numbers(payload)
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
	SerializedValue.validate_json_value(payload, "deferred.payload", payload_errors)
	if not payload_errors.is_empty():
		return false
	var canonical_payload: Dictionary = SerializedValue.normalize_json_numbers(payload)
	deferred_consequences.append({
		"id": consequence_id,
		"due": SerializedValue.normalized_stamp(due),
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
		"skill_practice": skill_practice.duplicate(true),
		"qualifications": qualifications.duplicate(true),
		"mastery_points": mastery_points,
		"knowledge": knowledge.duplicate(true),
		"calendar": calendar.to_dict(),
		"birth_date": birth_date.duplicate(true),
		"journal": journal.duplicate(true),
		"deferred_consequences": deferred_consequences.duplicate(true),
		"next_journal_sequence": _next_journal_sequence,
		"rng": rng.to_dict(),
	}



static func from_dict(data: Dictionary) -> RunState:
	var migration := RunStateMigration.migrate(data)
	if not bool(migration.get("ok", false)):
		return null
	var source: Dictionary = migration["data"]

	var parsed_characteristics: Variant = SerializedValue.parse_int_map(
		source.get("characteristics", null),
		GameRules.CHARACTERISTIC_KEYS,
		GameRules.CHARACTERISTIC_MIN,
		GameRules.CHARACTERISTIC_MAX
	)
	var parsed_meters: Variant = SerializedValue.parse_int_map(
		source.get("meters", null),
		GameRules.METER_KEYS,
		GameRules.METER_MIN,
		GameRules.METER_MAX
	)
	var parsed_qualifications: Variant = _parse_qualifications(source.get("qualifications", null))
	if parsed_qualifications == null:
		return null
	var parsed_practice: Variant = _parse_practice(data.get("skill_practice", null))
	if parsed_practice == null:
		return null
	var parsed_polarities: Variant = SerializedValue.parse_int_map(
		source.get("stored_polarities", null),
		GameRules.STORED_POLARITY_KEYS,
		GameRules.POLARITY_MIN,
		GameRules.POLARITY_MAX
	)
	var parsed_skills: Variant = SerializedValue.parse_int_map(
		source.get("skills", null),
		GameRules.SKILL_KEYS,
		GameRules.SKILL_MIN_RANK,
		GameRules.SKILL_MAX_RANK
	)
	if parsed_characteristics == null or parsed_meters == null or parsed_polarities == null or parsed_skills == null:
		return null
	if not GameRules.characteristics_use_budget(parsed_characteristics):
		return null

	var parsed_money: Variant = SerializedValue.parse_integral(source.get("money", null))
	var parsed_mastery: Variant = SerializedValue.parse_integral(source.get("mastery_points", null))
	var parsed_sequence: Variant = SerializedValue.parse_integral(source.get("next_journal_sequence", null))
	if parsed_money == null or int(parsed_money) < GameRules.MONEY_MIN or int(parsed_money) > GameRules.MONEY_MAX:
		return null
	if parsed_mastery == null or int(parsed_mastery) < GameRules.MASTERY_POINTS_MIN or int(parsed_mastery) > GameRules.MASTERY_POINTS_MAX:
		return null
	if parsed_sequence == null or int(parsed_sequence) < 0:
		return null

	var parsed_inventory: Variant = (
		InventoryStateScript.normalize_serialized(Dictionary(source["inventory"]))
		if source.get("inventory", null) is Dictionary
		else null
	)
	var parsed_knowledge: Variant = SerializedValue.parse_string_int_map(
		source.get("knowledge", null),
		GameRules.KNOWLEDGE_LEVEL_MIN,
		GameRules.KNOWLEDGE_LEVEL_MAX
	)
	var parsed_profiles: Variant = _parse_computed_profiles(source.get("computed_profiles", null))
	if (
		parsed_inventory == null
		or not bool(InventoryStateScript.validate(parsed_inventory).get("ok", false))
		or parsed_knowledge == null
		or parsed_profiles == null
	):
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
	result.skill_practice = Dictionary(parsed_practice)
	result.qualifications = Dictionary(parsed_qualifications)
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
	skill_practice = other.skill_practice.duplicate(true)
	qualifications = other.qualifications.duplicate(true)
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
	SerializedValue.validate_exact_int_map(
		characteristics,
		GameRules.CHARACTERISTIC_KEYS,
		GameRules.CHARACTERISTIC_MIN,
		GameRules.CHARACTERISTIC_MAX,
		"characteristics",
		errors
	)
	if not GameRules.characteristics_use_budget(characteristics):
		errors.append("characteristics must total %d points" % GameRules.CHARACTERISTIC_BUDGET)
	SerializedValue.validate_exact_int_map(meters, GameRules.METER_KEYS, GameRules.METER_MIN, GameRules.METER_MAX, "meters", errors)
	SerializedValue.validate_exact_int_map(
		stored_polarities,
		GameRules.STORED_POLARITY_KEYS,
		GameRules.POLARITY_MIN,
		GameRules.POLARITY_MAX,
		"stored_polarities",
		errors
	)
	SerializedValue.validate_exact_int_map(skills, GameRules.SKILL_KEYS, GameRules.SKILL_MIN_RANK, GameRules.SKILL_MAX_RANK, "skills", errors)
	_validate_computed_profiles(errors)

	if money < GameRules.MONEY_MIN or money > GameRules.MONEY_MAX:
		errors.append("money is outside allowed range")
	if mastery_points < GameRules.MASTERY_POINTS_MIN or mastery_points > GameRules.MASTERY_POINTS_MAX:
		errors.append("mastery_points is outside allowed range")
	SerializedValue.append_nested_errors("inventory", InventoryStateScript.validate(inventory), errors)
	SerializedValue.validate_string_int_map(
		knowledge,
		GameRules.KNOWLEDGE_LEVEL_MIN,
		GameRules.KNOWLEDGE_LEVEL_MAX,
		"knowledge",
		errors
	)

	if calendar == null:
		errors.append("calendar is null")
	else:
		SerializedValue.append_nested_errors("calendar", calendar.validate(), errors)
		if _parse_birth_date(birth_date, calendar) == null:
			errors.append("birth_date is invalid for the configured calendar")
		elif get_age_years() < GameRules.START_AGE_YEARS:
			errors.append("age cannot be lower than the starting age")
	if rng == null:
		errors.append("rng is null")
	else:
		SerializedValue.append_nested_errors("rng", rng.validate(), errors)
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
		var sequence: Variant = SerializedValue.parse_integral(entry.get("sequence", null))
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
		SerializedValue.validate_json_value(entry["payload"], "journal.payload", payload_errors)
		if not payload_errors.is_empty():
			return false
		parsed.append({
			"sequence": int(sequence),
			"id": String(entry["id"]),
			"at": SerializedValue.normalized_stamp(entry["at"]),
			"type": String(entry["type"]),
			"message": String(entry["message"]),
			"payload": SerializedValue.normalize_json_numbers(entry["payload"]),
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
		SerializedValue.validate_json_value(consequence["payload"], "deferred.payload", payload_errors)
		if not payload_errors.is_empty():
			return false
		seen_ids[consequence_id] = true
		parsed.append({
			"id": consequence_id,
			"due": SerializedValue.normalized_stamp(consequence["due"]),
			"effect_id": String(consequence["effect_id"]),
			"payload": SerializedValue.normalize_json_numbers(consequence["payload"]),
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
		SerializedValue.validate_json_value(entry.get("payload", null), "journal[%d].payload" % index, errors)
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
		SerializedValue.validate_json_value(consequence.get("payload", null), "deferred_consequences[%d].payload" % index, errors)


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
		var value: Variant = SerializedValue.parse_integral(raw.get(key, null))
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
		var value: Variant = SerializedValue.parse_integral(source.get("value", null))
		var evidence: Variant = SerializedValue.parse_integral(source.get("evidence", null))
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


## skill_id -> array of unique, non-empty source ids.
## qualification_id -> elapsed minute, non-negative.
static func _parse_qualifications(value: Variant) -> Variant:
	if value == null:
		return {}
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for raw_key: Variant in Dictionary(value):
		var qualification_id := String(raw_key).strip_edges()
		if qualification_id.is_empty() or not qualification_id.begins_with("qual_"):
			return null
		var granted: Variant = SerializedValue.parse_integral(Dictionary(value)[raw_key])
		if granted == null or int(granted) < 0:
			return null
		result[qualification_id] = int(granted)
	return result


static func _parse_practice(value: Variant) -> Variant:
	if value == null:
		return GameRules.default_skill_practice()
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for key: String in GameRules.SKILL_KEYS:
		result[key] = []
	for raw_key: Variant in Dictionary(value):
		var skill_id := String(raw_key)
		if not GameRules.is_known_skill(skill_id):
			return null
		var raw_sources: Variant = Dictionary(value)[raw_key]
		if not raw_sources is Array:
			return null
		var sources: Array = []
		for raw_source: Variant in Array(raw_sources):
			var source_id := String(raw_source).strip_edges()
			if source_id.is_empty() or sources.has(source_id):
				return null
			sources.append(source_id)
		if sources.size() > GameRules.SKILL_PRACTICE_SOURCES_MAX:
			return null
		result[skill_id] = sources
	return result
