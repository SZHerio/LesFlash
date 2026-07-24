class_name SearchSessionState
extends RefCounted

## Validation boundary for search state persisted by FirstDaySession.
## Search snapshots are accepted only when the matching authored template is
## available and the snapshot validator accepts that exact template version.

const GameSessionScript := preload("res://app/session/game_session.gd")
const ZoneCatalog := preload("res://game/search/search_zone_catalog.gd")
const SnapshotValidator := preload("res://game/search/search_snapshot_validator.gd")

const SEARCH_KIND := "search"


static func empty_activity() -> Dictionary:
	return GameSessionScript.empty_activity()


static func normalize_activity(value: Variant) -> Dictionary:
	var normalized := GameSessionScript.normalize_activity(value)
	if normalized.is_empty():
		return {}
	var kind := String(normalized.get("kind", ""))
	if kind not in [GameSessionScript.NO_ACTIVITY_KIND, SEARCH_KIND]:
		return {}
	normalized["snapshot"] = _normalize_json_numbers(normalized["snapshot"])
	return normalized


static func validate(activity: Variant, zone_states: Variant) -> Dictionary:
	var errors: Array[String] = []
	var normalized := normalize_activity(activity)
	if normalized.is_empty():
		errors.append("active_activity has an invalid search-session shape")
	if not zone_states is Dictionary:
		errors.append("search_zone_states must be a dictionary")
		return {"ok": false, "errors": errors}
	for raw_zone_id: Variant in Dictionary(zone_states):
		if typeof(raw_zone_id) != TYPE_STRING or String(raw_zone_id).strip_edges().is_empty():
			errors.append("search_zone_states contains an invalid key")
	var normalized_zones := normalized_zone_states(zone_states)

	var templates := _load_templates(errors)
	if not normalized.is_empty() and String(normalized["kind"]) == SEARCH_KIND:
		_validate_snapshot(
			String(normalized["id"]),
			normalized["snapshot"],
			"active_activity.snapshot",
			templates,
			errors
		)
		var active_id := String(normalized["id"])
		if not normalized_zones.has(active_id):
			errors.append("active search is missing from search_zone_states")
		elif normalized_zones[active_id] != normalized["snapshot"]:
			errors.append("active search snapshot disagrees with its archived zone state")

	for raw_zone_id: Variant in normalized_zones:
		_validate_snapshot(
			String(raw_zone_id),
			normalized_zones[raw_zone_id],
			"search_zone_states.%s" % String(raw_zone_id),
			templates,
			errors
		)
	return {"ok": errors.is_empty(), "errors": errors}


static func normalized_zone_states(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys := value.keys()
	keys.sort()
	for raw_key: Variant in keys:
		var raw_value: Variant = value[raw_key]
		result[String(raw_key)] = (
			_normalize_json_numbers(Dictionary(raw_value).duplicate(true))
			if raw_value is Dictionary
			else raw_value
		)
	return result


static func _normalize_json_numbers(value: Variant, depth: int = 0) -> Variant:
	if depth > 64:
		return value
	if (
		value is float
		and is_finite(float(value))
		and value == floor(value)
		and absf(float(value)) <= float(GameRules.JSON_SAFE_INTEGER_MAX)
	):
		return int(value)
	if value is Array:
		var array: Array = []
		for item: Variant in value:
			array.append(_normalize_json_numbers(item, depth + 1))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value:
			dictionary[key] = _normalize_json_numbers(value[key], depth + 1)
		return dictionary
	return value


static func _load_templates(errors: Array[String]) -> Dictionary:
	var loaded := ZoneCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		for raw_error: Variant in Array(loaded.get("errors", [])):
			errors.append("search template catalog: %s" % String(raw_error))
		return {}
	var template: Dictionary = loaded["template"]
	return {String(template.get("id", "")): template}


static func _validate_snapshot(
	zone_id: String,
	value: Variant,
	path: String,
	templates: Dictionary,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("%s must be a dictionary" % path)
		return
	var snapshot: Dictionary = value
	var template_id := String(snapshot.get("template_id", ""))
	if zone_id != template_id:
		errors.append("%s template_id does not match zone id" % path)
		return
	if not templates.has(template_id):
		errors.append("%s references an unavailable template" % path)
		return
	var validation := SnapshotValidator.validate(snapshot, templates[template_id])
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append("%s: %s" % [path, String(raw_error)])
