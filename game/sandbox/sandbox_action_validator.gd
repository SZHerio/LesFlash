class_name SandboxActionValidator
extends RefCounted

const ActionSchema := preload("res://game/sandbox/sandbox_action_schema.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "riverside_sandbox_actions"
const CATALOG_VERSION := 1
const MIN_ACTIONS := 18
## Raised from 22 when first aid and warming food were given somewhere to be
## practised. The cap exists so a place never turns into a wall of buttons; the
## per-location limit below is what actually protects the screen.
const MAX_ACTIONS := 52
## The places whose action list this catalog owns. The two districts beyond
## Riverside were added here rather than given a catalog of their own: a place
## the hero can stand in and do nothing is a worse district than none at all.
const CANONICAL_LOCATION_IDS := [
	"underpass",
	"market",
	"station_square",
	"recycling_point",
	"clinic_yard",
	"embankment",
	"bus_depot",
	"night_canteen",
	"workshop_row",
	"cathedral_steps",
	"almshouse",
	"pawn_row",
]


static func validate(catalog: Dictionary, reference_ids: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	_validate_root(catalog, errors)
	var location_ids := _validate_locations(catalog.get("location_ids", null), errors)
	var raw_actions: Variant = catalog.get("actions", null)
	if not raw_actions is Array:
		errors.append("actions must be an array")
		return _result(errors)
	var actions: Array = raw_actions
	if actions.size() < MIN_ACTIONS or actions.size() > MAX_ACTIONS:
		errors.append("actions must contain %d to %d entries" % [MIN_ACTIONS, MAX_ACTIONS])
	var action_ids: Dictionary = {}
	var actions_by_location: Dictionary = {}
	for location_id: String in CANONICAL_LOCATION_IDS:
		actions_by_location[location_id] = 0
	for index: int in actions.size():
		var path := "actions[%d]" % index
		var raw_action: Variant = actions[index]
		ActionSchema.validate_action(raw_action, path, errors)
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		_validate_action_links(action, location_ids, path, errors)
		var action_id := String(action.get("action_id", ""))
		if not action_id.is_empty():
			if action_ids.has(action_id):
				errors.append("%s.action_id repeats %s" % [path, action_id])
			action_ids[action_id] = true
		var location_id := String(action.get("location_id", ""))
		if actions_by_location.has(location_id):
			actions_by_location[location_id] = int(actions_by_location[location_id]) + 1
		if _contains_npc_reference(action):
			errors.append("%s must not embed an NPC reference in M3F.2" % path)
		if not reference_ids.is_empty():
			_validate_references(action, reference_ids, path, errors)
	for location_id: String in CANONICAL_LOCATION_IDS:
		if int(actions_by_location.get(location_id, 0)) < 2:
			errors.append("location %s must expose at least two actions" % location_id)
	return _result(errors)


static func _validate_root(catalog: Dictionary, errors: Array[String]) -> void:
	var required := ["schema_version", "catalog_id", "catalog_version", "location_ids", "actions"]
	for key: String in required:
		if not catalog.has(key):
			errors.append("%s is required" % key)
	for raw_key: Variant in catalog:
		var key := String(raw_key)
		if key not in required:
			errors.append("%s is not part of catalog schema v1" % key)
	if typeof(catalog.get("schema_version", null)) != TYPE_INT or int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if String(catalog.get("catalog_id", "")) != CATALOG_ID:
		errors.append("catalog_id must be %s" % CATALOG_ID)
	if typeof(catalog.get("catalog_version", null)) != TYPE_INT or int(catalog.get("catalog_version", 0)) != CATALOG_VERSION:
		errors.append("catalog_version must be %d" % CATALOG_VERSION)


static func _validate_locations(value: Variant, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not value is Array:
		errors.append("location_ids must be an array")
		return result
	var location_ids: Array = value
	if location_ids != CANONICAL_LOCATION_IDS:
		errors.append("location_ids must equal the canonical city locations in stable order")
	for index: int in location_ids.size():
		if typeof(location_ids[index]) != TYPE_STRING:
			errors.append("location_ids[%d] must be a string" % index)
			continue
		var location_id := String(location_ids[index])
		if result.has(location_id):
			errors.append("location_ids repeats %s" % location_id)
		result[location_id] = true
	return result


static func _validate_action_links(
	action: Dictionary,
	location_ids: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var location_id := String(action.get("location_id", ""))
	if not location_ids.has(location_id) or location_id not in CANONICAL_LOCATION_IDS:
		errors.append("%s.location_id is not canonical" % path)
	var intent_value: Variant = action.get("intent", null)
	if not intent_value is Dictionary:
		return
	var intent: Dictionary = intent_value
	var payload_value: Variant = intent.get("payload", null)
	if not payload_value is Dictionary:
		return
	var payload: Dictionary = payload_value
	if String(intent.get("type", "")) == "travel":
		var destination := String(payload.get("destination_location_id", ""))
		if destination not in CANONICAL_LOCATION_IDS:
			errors.append("%s.intent.payload.destination_location_id is not canonical" % path)
		elif destination == location_id:
			errors.append("%s travel destination must differ from its location" % path)


static func _validate_references(
	action: Dictionary,
	reference_ids: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	for request: Dictionary in ActionSchema.reference_requests(action):
		var kind := String(request.get("kind", ""))
		var reference_id := String(request.get("id", ""))
		if not reference_ids.has(kind):
			errors.append("%s cannot validate %s because its reference set is missing" % [path, kind])
		elif not _reference_exists(reference_ids[kind], reference_id):
			errors.append("%s references unknown %s ID %s" % [path, kind, reference_id])


static func _reference_exists(values: Variant, reference_id: String) -> bool:
	if values is Dictionary:
		return values.has(reference_id)
	if values is Array or values is PackedStringArray:
		return reference_id in values
	return false


static func _contains_npc_reference(value: Variant) -> bool:
	if value is Dictionary:
		for raw_key: Variant in value:
			var key := String(raw_key).to_lower()
			if key.contains("npc") or _contains_npc_reference(value[raw_key]):
				return true
	elif value is Array:
		for nested: Variant in value:
			if _contains_npc_reference(nested):
				return true
	elif typeof(value) == TYPE_STRING:
		return String(value).begins_with("npc_")
	return false


static func _result(errors: Array[String]) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}
