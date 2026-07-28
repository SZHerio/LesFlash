class_name LocationActionCatalog
extends RefCounted

## Loads and validates the versioned, data-only catalog of ordinary location
## actions. The catalog contains no executable callbacks and can later move to a
## content pipeline without changing the service contract.

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "res://game/location/data/location_actions_v1.json"
const DistrictContentScript := preload("res://game/district/district_content.gd")
const CATEGORY_ICON_IDS := {
	"observe": &"action_observe",
	"search": &"action_search",
	"talk": &"action_talk",
	"work": &"action_work",
	"trade": &"action_trade",
	"food": &"action_food",
	"rest": &"action_rest",
	"study": &"action_study",
	"shelter": &"action_shelter",
}


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось открыть каталог локальных действий: %s" % path)
	var parsed: Variant = SerializedValue.normalize_json_numbers(JSON.parse_string(file.get_as_text()))
	if not parsed is Dictionary:
		return _failure("Каталог локальных действий не является JSON-объектом")
	var catalog: Dictionary = parsed
	var validation := validate(catalog)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"catalog": {},
			"errors": Array(validation.get("errors", [])).duplicate(),
		}
	return {
		"ok": true,
		"catalog": catalog.duplicate(true),
		"errors": [],
	}


static func category_icon_id(category_id: String) -> StringName:
	return StringName(CATEGORY_ICON_IDS.get(category_id, &""))


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("Ожидалась версия каталога %d" % SCHEMA_VERSION)
	var raw_locations: Variant = catalog.get("location_ids", [])
	if not raw_locations is Array or raw_locations.is_empty():
		errors.append("location_ids должен быть непустым массивом")
	var location_ids: Array = raw_locations if raw_locations is Array else []
	var seen_locations: Dictionary = {}
	for raw_location: Variant in location_ids:
		var location_id := String(raw_location).strip_edges()
		if location_id.is_empty() or seen_locations.has(location_id):
			errors.append("Некорректный или повторный location_id: %s" % location_id)
		seen_locations[location_id] = true

	var raw_actions: Variant = catalog.get("actions", [])
	if not raw_actions is Array or raw_actions.is_empty():
		errors.append("actions должен быть непустым массивом")
		return {"ok": errors.is_empty(), "errors": errors}
	var seen_actions: Dictionary = {}
	var actions_per_location: Dictionary = {}
	for index: int in raw_actions.size():
		var raw_action: Variant = raw_actions[index]
		if not raw_action is Dictionary:
			errors.append("actions[%d] должен быть объектом" % index)
			continue
		var action: Dictionary = raw_action
		var prefix := "actions[%d]" % index
		var action_id := String(action.get("id", "")).strip_edges()
		var location_id := String(action.get("location_id", "")).strip_edges()
		var category_id := String(action.get("category_id", "")).strip_edges()
		if action_id.is_empty() or seen_actions.has(action_id):
			errors.append("%s: пустой или повторный id «%s»" % [prefix, action_id])
		else:
			seen_actions[action_id] = true
		if not seen_locations.has(location_id):
			errors.append("%s: неизвестная локация «%s»" % [prefix, location_id])
		else:
			actions_per_location[location_id] = int(actions_per_location.get(location_id, 0)) + 1
		if not CATEGORY_ICON_IDS.has(category_id):
			errors.append("%s: неизвестная категория действия «%s»" % [prefix, category_id])
		for field: String in ["title", "description", "outcome"]:
			if String(action.get(field, "")).strip_edges().is_empty():
				errors.append("%s: поле %s не заполнено" % [prefix, field])
		var duration := int(action.get("duration_minutes", 0))
		if duration <= 0:
			errors.append("%s: duration_minutes должен быть положительным" % prefix)
		_append_semantic_errors(
			DistrictContentValidator.validate_condition_packet(
				action.get("conditions", []),
				"%s.conditions" % prefix
			),
			errors
		)
		_validate_time_windows(action.get("time_windows", []), prefix, errors)
		_append_semantic_errors(
			DistrictContentValidator.validate_effect_packet(
				action.get("effects", []),
				"%s.effects" % prefix
			),
			errors
		)
		_validate_effects(action.get("effects", []), duration, prefix, errors)
	for raw_location: Variant in location_ids:
		var location_id := String(raw_location)
		if int(actions_per_location.get(location_id, 0)) == 0:
			errors.append("Для локации «%s» нет локальных действий" % location_id)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_effects(
		raw_effects: Variant,
		duration_minutes: int,
		prefix: String,
		errors: Array[String]
	) -> void:
	if not raw_effects is Array or raw_effects.is_empty():
		errors.append("%s.effects должен быть непустым массивом" % prefix)
		return
	var time_effects := 0
	for effect_index: int in raw_effects.size():
		var raw_effect: Variant = raw_effects[effect_index]
		if not raw_effect is Dictionary:
			errors.append("%s.effects[%d] должен быть объектом" % [prefix, effect_index])
			continue
		var effect_type := String(raw_effect.get("type", "")).strip_edges()
		if effect_type == "advance_time":
			time_effects += 1
			if int(raw_effect.get("minutes", -1)) != duration_minutes:
				errors.append("%s: длительность карточки и эффекта времени расходятся" % prefix)
	if time_effects != 1:
		errors.append("%s: подтверждённое действие должно содержать ровно один advance_time" % prefix)


static func _validate_time_windows(
		raw_windows: Variant,
		prefix: String,
		errors: Array[String]
	) -> void:
	if not raw_windows is Array:
		errors.append("%s.time_windows должен быть массивом" % prefix)
		return
	for window_index: int in raw_windows.size():
		var raw_window: Variant = raw_windows[window_index]
		if not raw_window is Dictionary:
			errors.append("%s.time_windows[%d] должен быть объектом" % [prefix, window_index])
			continue
		var start := int(raw_window.get("start_minute", -1))
		var end := int(raw_window.get("end_minute", -1))
		if start < 0 or start >= 1440 or end <= 0 or end > 1440 or start == end:
			errors.append("%s.time_windows[%d] имеет недопустимые границы" % [prefix, window_index])


static func _append_semantic_errors(validation: Dictionary, errors: Array[String]) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append(String(raw_error))


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"catalog": {},
		"errors": [message],
	}
