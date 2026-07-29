class_name SandboxActionSchema
extends RefCounted

## Scalar schema for one location-first sandbox action. It describes navigation
## intents and confirmed decisions, but never executes effects or mutates a run.

const CATEGORY_ICONS := {
	"observe": "action_observe",
	"search": "action_search",
	"work": "action_work",
	"trade": "action_trade",
	"food": "action_food",
	"rest": "action_rest",
	"study": "action_study",
	"shelter": "action_shelter",
	"travel": "transport_walk",
}
const REPEAT_POLICIES := ["repeatable", "once_per_day", "once_per_run"]
const CONFIRMATION_MODES := ["none", "required"]
const CHARACTERISTIC_IDS := ["strength", "charisma", "intelligence", "luck"]
const METER_IDS := ["health", "hunger", "energy", "tension", "mental_state"]
const TRAVEL_MODE_IDS := ["walk", "bus", "tram"]
const INTENT_PAYLOAD_KEYS := {
	"inspect": ["knowledge_id"],
	"enter_search": ["zone_id"],
	"open_store": ["store_id"],
	"consume_item": ["item_id", "quantity"],
	"perform_activity": ["activity_id"],
	"travel": ["destination_location_id", "mode_id"],
	"open_recycling_sale": ["organization_id"],
	"open_job": ["job_id"],
	"open_shelter": ["location_id"],
}


static func validate_action(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s must be an object" % path)
		return
	var action: Dictionary = value
	var confirmation := String(action.get("confirmation", ""))
	var required_keys := [
		"action_id", "location_id", "category_id", "icon_id", "title", "description",
		"repeat_policy", "confirmation", "intent", "requirements",
	]
	var optional_keys: Array = ["duration"] if confirmation == "required" else []
	_expect_exact_keys(action, required_keys, optional_keys, path, errors)

	var action_id := _expect_id(action.get("action_id", null), "%s.action_id" % path, errors)
	if not action_id.is_empty() and not action_id.begins_with("action_"):
		errors.append("%s.action_id must start with action_" % path)
	_expect_id(action.get("location_id", null), "%s.location_id" % path, errors)
	var category_id := _expect_id(action.get("category_id", null), "%s.category_id" % path, errors)
	var icon_id := _expect_id(action.get("icon_id", null), "%s.icon_id" % path, errors)
	if not CATEGORY_ICONS.has(category_id):
		errors.append("%s.category_id is unknown" % path)
	elif icon_id != String(CATEGORY_ICONS[category_id]):
		errors.append("%s.icon_id does not match category_id" % path)
	_expect_russian_text(action.get("title", null), "%s.title" % path, errors)
	_expect_russian_text(action.get("description", null), "%s.description" % path, errors)

	var repeat_policy := String(action.get("repeat_policy", ""))
	if repeat_policy not in REPEAT_POLICIES:
		errors.append("%s.repeat_policy is unknown" % path)
	if confirmation not in CONFIRMATION_MODES:
		errors.append("%s.confirmation must be none or required" % path)
	if confirmation == "none" and action.has("duration"):
		errors.append("%s.duration is forbidden without confirmation" % path)
	elif confirmation == "required":
		_validate_duration(action.get("duration", null), "%s.duration" % path, errors)

	_validate_intent(action.get("intent", null), action, "%s.intent" % path, errors)
	_validate_requirements(action.get("requirements", null), "%s.requirements" % path, errors)


static func reference_requests(action: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var intent_value: Variant = action.get("intent", null)
	if intent_value is Dictionary:
		var intent: Dictionary = intent_value
		var payload_value: Variant = intent.get("payload", null)
		if payload_value is Dictionary:
			var payload: Dictionary = payload_value
			match String(intent.get("type", "")):
				"inspect":
					_append_reference(result, "knowledge_ids", payload.get("knowledge_id", null))
				"enter_search":
					_append_reference(result, "search_zone_ids", payload.get("zone_id", null))
				"open_store":
					_append_reference(result, "store_ids", payload.get("store_id", null))
				"consume_item":
					_append_reference(result, "item_ids", payload.get("item_id", null))
				"open_recycling_sale":
					_append_reference(result, "organization_ids", payload.get("organization_id", null))
				"open_job":
					_append_reference(result, "job_ids", payload.get("job_id", null))
	for requirement_value: Variant in action.get("requirements", []):
		if not requirement_value is Dictionary:
			continue
		var requirement: Dictionary = requirement_value
		match String(requirement.get("type", "")):
			"inventory_item_min":
				_append_reference(result, "item_ids", requirement.get("item_id", null))
			"knowledge_level_min":
				_append_reference(result, "knowledge_ids", requirement.get("knowledge_id", null))
	return result


static func _validate_intent(
	value: Variant,
	action: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("%s must be an object" % path)
		return
	var intent: Dictionary = value
	_expect_exact_keys(intent, ["type", "payload"], [], path, errors)
	var intent_type := _expect_id(intent.get("type", null), "%s.type" % path, errors)
	if not INTENT_PAYLOAD_KEYS.has(intent_type):
		errors.append("%s.type is unknown" % path)
		return
	var payload_value: Variant = intent.get("payload", null)
	if not payload_value is Dictionary:
		errors.append("%s.payload must be an object" % path)
		return
	var payload: Dictionary = payload_value
	_expect_exact_keys(payload, INTENT_PAYLOAD_KEYS[intent_type], [], "%s.payload" % path, errors)
	for raw_key: Variant in INTENT_PAYLOAD_KEYS[intent_type]:
		var key := String(raw_key)
		if key != "quantity":
			_expect_id(payload.get(key, null), "%s.payload.%s" % [path, key], errors)
	if intent_type == "consume_item":
		_expect_int(payload.get("quantity", null), 1, 999, "%s.payload.quantity" % path, errors)
	elif intent_type == "perform_activity" and not String(payload.get("activity_id", "")).begins_with("activity_"):
		errors.append("%s.payload.activity_id must start with activity_" % path)
	elif intent_type == "open_recycling_sale" and not String(payload.get("organization_id", "")).begins_with("org_"):
		errors.append("%s.payload.organization_id must start with org_" % path)
	elif intent_type == "open_job" and not String(payload.get("job_id", "")).begins_with("job_"):
		errors.append("%s.payload.job_id must start with job_" % path)
	elif intent_type == "travel" and String(payload.get("mode_id", "")) not in TRAVEL_MODE_IDS:
		errors.append("%s.payload.mode_id is unknown" % path)
	elif intent_type == "open_shelter" and String(payload.get("location_id", "")) != String(action.get("location_id", "")):
		errors.append("%s.payload.location_id must match the action location" % path)


static func _validate_duration(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s is required for a confirmed action" % path)
		return
	var duration: Dictionary = value
	_expect_exact_keys(duration, ["kind", "minutes"], [], path, errors)
	if String(duration.get("kind", "")) != "fixed":
		errors.append("%s.kind must be fixed" % path)
	_expect_int(duration.get("minutes", null), 1, 1440, "%s.minutes" % path, errors)


static func _validate_requirements(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("%s must be an array" % path)
		return
	if value.size() > 8:
		errors.append("%s may contain at most eight requirements" % path)
	for index: int in value.size():
		_validate_requirement(value[index], "%s[%d]" % [path, index], errors)


static func _validate_requirement(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s must be an object" % path)
		return
	var requirement: Dictionary = value
	var requirement_type := String(requirement.get("type", ""))
	var keys: Array
	match requirement_type:
		"characteristic_min":
			keys = ["type", "characteristic_id", "value", "blocked_reason"]
		"meter_min", "meter_max":
			keys = ["type", "meter_id", "value", "blocked_reason"]
		"inventory_item_min":
			keys = ["type", "item_id", "quantity", "blocked_reason"]
		"knowledge_level_min":
			keys = ["type", "knowledge_id", "value", "blocked_reason"]
		"time_window":
			keys = ["type", "start_minute", "end_minute", "blocked_reason"]
		# Work that exists only in one part of the year. Snow is not cleared in
		# July, and a warming station open all summer is not a warming station.
		"season":
			keys = ["type", "season_ids", "blocked_reason"]
		# Как героя читают, не спрашивая. Не «обаяние 7», а то, пустят ли его
		# внутрь в том, в чём он пришёл.
		"appearance_min":
			keys = ["type", "band_id", "blocked_reason"]
		# Что о нём знают. Одна сторона открывает то, что закрывает другая, —
		# поэтому требование называет и сторону, и то, сколько её нужно.
		"standing_min":
			keys = ["type", "side", "value", "blocked_reason"]
		_:
			errors.append("%s.type is unknown" % path)
			return
	_expect_exact_keys(requirement, keys, [], path, errors)
	_expect_russian_text(requirement.get("blocked_reason", null), "%s.blocked_reason" % path, errors)
	match requirement_type:
		"characteristic_min":
			var characteristic_id := _expect_id(requirement.get("characteristic_id", null), "%s.characteristic_id" % path, errors)
			if characteristic_id not in CHARACTERISTIC_IDS:
				errors.append("%s.characteristic_id is unknown" % path)
			_expect_int(requirement.get("value", null), 1, 10, "%s.value" % path, errors)
		"meter_min", "meter_max":
			var meter_id := _expect_id(requirement.get("meter_id", null), "%s.meter_id" % path, errors)
			if meter_id not in METER_IDS:
				errors.append("%s.meter_id is unknown" % path)
			_expect_int(requirement.get("value", null), 0, 100, "%s.value" % path, errors)
		"inventory_item_min":
			_expect_id(requirement.get("item_id", null), "%s.item_id" % path, errors)
			_expect_int(requirement.get("quantity", null), 1, 999, "%s.quantity" % path, errors)
		"standing_min":
			if String(requirement.get("side", "")) not in ["reliable", "feared"]:
				errors.append("%s.side must be reliable or feared" % path)
			_expect_int(requirement.get("value", null), 1, 40, "%s.value" % path, errors)
		"appearance_min":
			if String(requirement.get("band_id", "")) not in AppearanceRules.ORDER:
				errors.append("%s.band_id is unknown" % path)
			elif String(requirement.get("band_id", "")) == AppearanceRules.DERELICT:
				# Худшая полоса — это все, поэтому такое требование ничего не значит.
				errors.append("%s.band_id gates nothing: everyone is at least that" % path)
		"season":
			var raw_seasons: Variant = requirement.get("season_ids", null)
			if not raw_seasons is Array or Array(raw_seasons).is_empty():
				errors.append("%s.season_ids must be a non-empty array" % path)
			else:
				for raw_season: Variant in Array(raw_seasons):
					if String(raw_season) not in Season.ORDER:
						errors.append("%s.season_ids contains an unknown season" % path)
				if Array(raw_seasons).size() >= Season.ORDER.size():
					errors.append("%s.season_ids covers the whole year and gates nothing" % path)
		"knowledge_level_min":
			_expect_id(requirement.get("knowledge_id", null), "%s.knowledge_id" % path, errors)
			_expect_int(requirement.get("value", null), 1, 3, "%s.value" % path, errors)
		"time_window":
			_expect_int(requirement.get("start_minute", null), 0, 1439, "%s.start_minute" % path, errors)
			_expect_int(requirement.get("end_minute", null), 1, 1440, "%s.end_minute" % path, errors)
			if requirement.get("start_minute", null) == requirement.get("end_minute", null):
				errors.append("%s cannot describe an empty time window" % path)


static func _expect_exact_keys(
	value: Dictionary,
	required: Array,
	optional: Array,
	path: String,
	errors: Array[String]
) -> void:
	for raw_key: Variant in required:
		var key := String(raw_key)
		if not value.has(key):
			errors.append("%s.%s is required" % [path, key])
	for raw_key: Variant in value:
		var key := String(raw_key)
		if key not in required and key not in optional:
			errors.append("%s.%s is not part of schema v1" % [path, key])


static func _expect_id(value: Variant, path: String, errors: Array[String]) -> String:
	if typeof(value) != TYPE_STRING or not _valid_id(String(value)):
		errors.append("%s must be a lower_snake_case ID" % path)
		return ""
	return String(value)


static func _valid_id(value: String) -> bool:
	if value.is_empty() or value.begins_with("_") or value.ends_with("_"):
		return false
	for character: String in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true


static func _expect_russian_text(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append("%s must be non-empty Russian text" % path)
		return
	var text := String(value)
	for index: int in text.length():
		var codepoint := text.unicode_at(index)
		if codepoint >= 0x0400 and codepoint <= 0x04FF:
			return
	errors.append("%s must contain Cyrillic text" % path)


static func _expect_int(
	value: Variant,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_INT or int(value) < minimum or int(value) > maximum:
		errors.append("%s must be an integer from %d to %d" % [path, minimum, maximum])


static func _append_reference(result: Array[Dictionary], kind: String, value: Variant) -> void:
	if typeof(value) == TYPE_STRING and not String(value).is_empty():
		result.append({"kind": kind, "id": String(value)})
