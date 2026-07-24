class_name SearchZoneCatalog
extends RefCounted

const TemplateValidator := preload("res://game/search/search_template_validator.gd")

const DEFAULT_PATH := "res://game/search/data/underpass_service_yard_v1.json"


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось открыть шаблон поисковой зоны: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("Шаблон поисковой зоны не является JSON-объектом")
	var template: Dictionary = _normalize_json_numbers(parsed)
	var validation := TemplateValidator.validate(template)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"template": {},
			"errors": Array(validation.get("errors", [])).duplicate(),
		}
	return {"ok": true, "template": template.duplicate(true), "errors": []}


static func _normalize_json_numbers(value: Variant, depth: int = 0) -> Variant:
	if depth > 64:
		return value
	match typeof(value):
		TYPE_FLOAT:
			var number := float(value)
			return int(number) if is_finite(number) and number == floor(number) else number
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


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "template": {}, "errors": [message]}
