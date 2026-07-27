class_name EventContext
extends RefCounted

## Versioned, immutable-by-convention input for contextual encounters.
##
## v2 adds objective world state and typed social state while keeping the
## actor/source contract used by search encounters.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const JsonValidator := preload("res://core/save/json_value_validator.gd")

const LEGACY_SCHEMA_VERSION := 1
const SCHEMA_VERSION := 2
const SOURCE_FIELDS := ["kind", "id", "action_id", "object_id"]
const ACTOR_FIELDS := [
	"characteristics",
	"meters",
	"stored_polarities",
	"computed_profiles",
	"skills",
	"knowledge",
	"items",
]
const RISK_FIELDS := ["score", "noise", "trespass"]


static func build(
	run_state: RunState,
	source: Dictionary,
	world: Dictionary = {}
) -> Dictionary:
	if run_state == null:
		return {}
	var normalized_source := {
		"kind": String(source.get("kind", "")),
		"id": String(source.get("id", "")),
		"action_id": String(source.get("action_id", "")),
		"object_id": String(source.get("object_id", "")),
	}
	var context := {
		"schema_version": SCHEMA_VERSION,
		"source": normalized_source,
		"location_id": String(world.get("location_id", "")),
		"calendar": (
			run_state.calendar.current_stamp()
			if run_state.calendar != null
			else {}
		),
		"era_id": String(world.get("era_id", "late_20th_century")),
		"weather_id": String(world.get("weather_id", "dry")),
		"actor": {
			"characteristics": run_state.characteristics.duplicate(true),
			"meters": run_state.meters.duplicate(true),
			"stored_polarities": run_state.stored_polarities.duplicate(true),
			"computed_profiles": run_state.computed_profiles.duplicate(true),
			"skills": run_state.skills.duplicate(true),
			"knowledge": run_state.knowledge.duplicate(true),
			"items": _carried_item_counts(run_state.inventory),
		},
		"world": _world_copy(world),
		"relationships": _dictionary_copy(world.get("relationships", {})),
		"npc_memories": _dictionary_copy(world.get("npc_memories", world.get("memories", {}))),
		"commitments": _dictionary_copy(world.get("commitments", {})),
		"reputations": _dictionary_copy(world.get("reputations", {})),
		"history_facts": _array_copy(world.get("history_facts", [])),
		"cooldowns": _dictionary_copy(world.get("cooldowns", {})),
		"risk": _risk_copy(world.get("risk", {})),
	}
	return context if bool(validate(context).get("ok", false)) else {}


static func migrate_serialized(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": "invalid_event_context", "error": "EventContext must be a dictionary."}
	var normalized: Variant = JsonValidator.normalize_numbers(value)
	if not normalized is Dictionary:
		return {"ok": false, "code": "invalid_event_context", "error": "EventContext could not be normalized."}
	var source: Dictionary = normalized
	var version: Variant = source.get("schema_version", null)
	if typeof(version) != TYPE_INT and not (typeof(version) == TYPE_FLOAT and float(version) == floor(float(version))):
		return {"ok": false, "code": "invalid_event_context_version", "error": "EventContext schema_version must be an integer."}
	var source_version := int(version)
	if source_version not in [LEGACY_SCHEMA_VERSION, SCHEMA_VERSION]:
		return {"ok": false, "code": "unsupported_event_context_version", "error": "EventContext version is unsupported."}
	var migrated := source.duplicate(true)
	if source_version == LEGACY_SCHEMA_VERSION:
		var actor: Variant = migrated.get("actor", null)
		if not actor is Dictionary or not Dictionary(actor).get("meters", null) is Dictionary:
			return {"ok": false, "code": "invalid_legacy_event_actor", "error": "EventContext v1 actor meters are invalid."}
		var meters: Dictionary = Dictionary(actor["meters"]).duplicate(true)
		if meters.has("morale") and meters.has("mental_state"):
			return {"ok": false, "code": "ambiguous_mental_state", "error": "EventContext v1 contains both morale and mental_state."}
		if not meters.has("morale"):
			return {"ok": false, "code": "missing_legacy_morale", "error": "EventContext v1 does not contain morale."}
		meters["mental_state"] = meters["morale"]
		meters.erase("morale")
		var migrated_actor: Dictionary = Dictionary(actor).duplicate(true)
		migrated_actor["meters"] = meters
		migrated["actor"] = migrated_actor
		var legacy_relationships: Variant = migrated.get("relationships", {})
		if not legacy_relationships is Dictionary:
			return {"ok": false, "code": "invalid_legacy_relationships", "error": "EventContext v1 relationships are invalid."}
		for raw_id: Variant in Dictionary(legacy_relationships):
			if not Dictionary(legacy_relationships)[raw_id] is Dictionary:
				return {"ok": false, "code": "ambiguous_legacy_relationship", "error": "Flat EventContext v1 relationships cannot be inferred safely."}
		migrated["world"] = {"revision": 0, "facts": {}, "metrics": {}, "processes": {}}
		migrated["npc_memories"] = {}
		migrated["commitments"] = {}
		migrated["schema_version"] = SCHEMA_VERSION
	var validation := validate(migrated)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_migrated_event_context",
			"error": "Migrated EventContext failed validation.",
			"validation": validation,
		}
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"data": migrated,
		"source_version": source_version,
		"migrated": source_version != SCHEMA_VERSION,
	}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["event_context must be a dictionary"]}
	var normalized: Variant = JsonValidator.normalize_numbers(value)
	if not normalized is Dictionary:
		return {"ok": false, "errors": ["event_context could not be normalized"]}
	var context: Dictionary = normalized
	if int(context.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("event_context.schema_version is unsupported")
	_validate_source(context.get("source", null), errors)
	_validate_non_empty_string(context, "location_id", errors)
	_validate_non_empty_string(context, "era_id", errors)
	_validate_non_empty_string(context, "weather_id", errors)
	_validate_calendar(context.get("calendar", null), errors)
	_validate_actor(context.get("actor", null), errors)
	_validate_world(context.get("world", null), errors)
	_validate_relationships(context.get("relationships", null), errors)
	for field in ["npc_memories", "commitments", "reputations", "cooldowns"]:
		if not context.get(field, null) is Dictionary:
			errors.append("event_context.%s must be a dictionary" % field)
	if not context.get("history_facts", null) is Array:
		errors.append("event_context.history_facts must be an array")
	_validate_risk(context.get("risk", null), errors)
	var json_validation := JsonValidator.validate(context, "event_context")
	for error in Array(json_validation.get("errors", [])):
		errors.append(String(error))
	return {"ok": errors.is_empty(), "errors": errors}


static func _carried_item_counts(inventory: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_stack in InventoryStateScript.all_stacks(inventory):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = raw_stack
		if bool(stack.get("external", false)):
			continue
		var item_id := String(stack.get("item_id", ""))
		if item_id.is_empty():
			continue
		result[item_id] = int(result.get(item_id, 0)) + int(stack.get("quantity", 0))
	return result


static func _validate_source(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.source must be a dictionary")
		return
	var source: Dictionary = value
	for field in SOURCE_FIELDS:
		if typeof(source.get(field, null)) != TYPE_STRING:
			errors.append("event_context.source.%s must be a string" % field)
	for field in ["kind", "id"]:
		if String(source.get(field, "")).is_empty():
			errors.append("event_context.source.%s cannot be empty" % field)


static func _validate_calendar(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.calendar must be a dictionary")
		return
	var calendar: Dictionary = value
	for field in ["year", "month", "day", "minute_of_day", "elapsed_minutes"]:
		if typeof(calendar.get(field, null)) != TYPE_INT:
			errors.append("event_context.calendar.%s must be an integer" % field)


static func _validate_actor(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.actor must be a dictionary")
		return
	var actor: Dictionary = value
	for field in ACTOR_FIELDS:
		if not actor.get(field, null) is Dictionary:
			errors.append("event_context.actor.%s must be a dictionary" % field)
	var characteristics: Dictionary = actor.get("characteristics", {})
	for key in GameRules.CHARACTERISTIC_KEYS:
		if typeof(characteristics.get(key, null)) != TYPE_INT:
			errors.append("event_context.actor.characteristics.%s is missing" % key)
	var skills: Dictionary = actor.get("skills", {})
	for key in GameRules.SKILL_KEYS:
		if typeof(skills.get(key, null)) != TYPE_INT:
			errors.append("event_context.actor.skills.%s is missing" % key)
	var items: Dictionary = actor.get("items", {})
	for item_id in items:
		if typeof(item_id) != TYPE_STRING or typeof(items[item_id]) != TYPE_INT or int(items[item_id]) < 0:
			errors.append("event_context.actor.items contains an invalid count")
	var meters: Dictionary = actor.get("meters", {})
	for key in GameRules.METER_KEYS:
		if typeof(meters.get(key, null)) != TYPE_INT:
			errors.append("event_context.actor.meters.%s is missing" % key)


static func _validate_world(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.world must be a dictionary")
		return
	var world: Dictionary = value
	if typeof(world.get("revision", null)) != TYPE_INT or int(world.get("revision", -1)) < 0:
		errors.append("event_context.world.revision must be a non-negative integer")
	for field: String in ["facts", "metrics", "processes"]:
		if not world.get(field, null) is Dictionary:
			errors.append("event_context.world.%s must be a dictionary" % field)
	for raw_id: Variant in Dictionary(world.get("facts", {})):
		if typeof(Dictionary(world["facts"])[raw_id]) != TYPE_BOOL:
			errors.append("event_context.world.facts contains a non-boolean value")
	for raw_id: Variant in Dictionary(world.get("metrics", {})):
		if typeof(Dictionary(world["metrics"])[raw_id]) != TYPE_INT:
			errors.append("event_context.world.metrics contains a non-integer value")
	for raw_id: Variant in Dictionary(world.get("processes", {})):
		if typeof(Dictionary(world["processes"])[raw_id]) != TYPE_STRING:
			errors.append("event_context.world.processes contains a non-string value")


static func _validate_relationships(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.relationships must be a dictionary")
		return
	for raw_npc_id: Variant in Dictionary(value):
		var relationship: Variant = Dictionary(value)[raw_npc_id]
		if not relationship is Dictionary:
			errors.append("event_context.relationships.%s must be a dictionary" % String(raw_npc_id))
			continue
		for field: String in ["trust", "respect", "affinity", "fear"]:
			if typeof(Dictionary(relationship).get(field, null)) != TYPE_INT:
				errors.append("event_context.relationships.%s.%s must be an integer" % [String(raw_npc_id), field])


static func _validate_risk(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("event_context.risk must be a dictionary")
		return
	var risk: Dictionary = value
	for field in RISK_FIELDS:
		if typeof(risk.get(field, null)) != TYPE_INT or int(risk[field]) < 0:
			errors.append("event_context.risk.%s must be a non-negative integer" % field)
	if not risk.get("tags", null) is Array:
		errors.append("event_context.risk.tags must be an array")
		return
	for tag in Array(risk["tags"]):
		if typeof(tag) != TYPE_STRING or String(tag).is_empty():
			errors.append("event_context.risk.tags contains an invalid tag")


static func _validate_non_empty_string(
	data: Dictionary,
	field: String,
	errors: Array[String]
) -> void:
	if typeof(data.get(field, null)) != TYPE_STRING or String(data[field]).is_empty():
		errors.append("event_context.%s must be a non-empty string" % field)


static func _risk_copy(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var tags: Array = _array_copy(source.get("tags", []))
	return {
		"score": maxi(int(source.get("score", 0)), 0),
		"noise": maxi(int(source.get("noise", 0)), 0),
		"trespass": maxi(int(source.get("trespass", 0)), 0),
		"tags": tags,
	}


static func _dictionary_copy(value: Variant) -> Dictionary:
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func _world_copy(source: Dictionary) -> Dictionary:
	var raw: Variant = source.get("world", source.get("world_rules", {}))
	if raw is Dictionary and Dictionary(raw).has("rules"):
		raw = Dictionary(raw).get("rules", {})
	var rules: Dictionary = Dictionary(raw).duplicate(true) if raw is Dictionary else {}
	return {
		"revision": maxi(int(rules.get("revision", 0)), 0),
		"facts": _dictionary_copy(rules.get("facts", {})),
		"metrics": _dictionary_copy(rules.get("metrics", {})),
		"processes": _dictionary_copy(rules.get("processes", {})),
	}


static func _array_copy(value: Variant) -> Array:
	return Array(value).duplicate(true) if value is Array else []
