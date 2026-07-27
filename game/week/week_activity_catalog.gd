class_name WeekActivityCatalog
extends RefCounted

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const DEFAULT_PATH := "res://game/week/data/week_activity_profiles_v1.json"
const EFFECT_TYPES := ["change_state", "shift_polarity", "mastery"]


static func load_default() -> Dictionary:
	var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
	if file == null:
		return _failure("Каталог обычных занятий не найден")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("Каталог обычных занятий содержит неверный JSON")
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var validation := validate(catalog)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": validation["errors"]}
	return {"ok": true, "catalog": catalog.duplicate(true), "errors": []}


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(catalog.get("schema_version", 0)) != 1 or int(catalog.get("catalog_version", 0)) != 1:
		errors.append("Версия каталога занятий должна быть равна 1")
	if String(catalog.get("catalog_id", "")) != "riverside_week_activities":
		errors.append("Неизвестный catalog_id занятий")
	var profiles: Variant = catalog.get("profiles", null)
	if not profiles is Array or Array(profiles).is_empty():
		errors.append("profiles должен быть непустым массивом")
		return {"ok": false, "errors": errors}
	var seen: Dictionary = {}
	for index: int in Array(profiles).size():
		var raw: Variant = profiles[index]
		if not raw is Dictionary:
			errors.append("profiles[%d] должен быть объектом" % index)
			continue
		var profile: Dictionary = raw
		var activity_id := String(profile.get("activity_id", ""))
		if activity_id.is_empty() or seen.has(activity_id):
			errors.append("profiles[%d].activity_id пуст или повторяется" % index)
		seen[activity_id] = true
		var effects: Variant = profile.get("effects", null)
		if not effects is Array or Array(effects).is_empty():
			errors.append("%s.effects должен быть непустым массивом" % activity_id)
			continue
		for raw_effect: Variant in Array(effects):
			if not raw_effect is Dictionary or String(raw_effect.get("type", "")) not in EFFECT_TYPES:
				errors.append("%s содержит запрещённый эффект" % activity_id)
				continue
			if typeof(raw_effect.get("delta", null)) != TYPE_INT or int(raw_effect.get("delta", 0)) == 0:
				errors.append("%s содержит неверный delta" % activity_id)
	return {"ok": errors.is_empty(), "errors": errors}


static func find(catalog: Dictionary, activity_id: String) -> Dictionary:
	for raw: Variant in Array(catalog.get("profiles", [])):
		if raw is Dictionary and String(raw.get("activity_id", "")) == activity_id:
			return Dictionary(raw).duplicate(true)
	return {}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": {}, "errors": [message]}
