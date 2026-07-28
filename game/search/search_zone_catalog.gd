class_name SearchZoneCatalog
extends RefCounted

const TemplateValidator := preload("res://game/search/search_template_validator.gd")

## Every authored search map. M4 adds the second one, so the catalog stops being
## a single file with a default and becomes a set keyed by the place it belongs
## to.
const ZONE_PATHS := [
	"res://game/search/data/underpass_service_yard_v1.json",
	"res://game/search/data/freight_yard_sidings_v1.json",
]
const DEFAULT_PATH := "res://game/search/data/underpass_service_yard_v1.json"


## The zone that belongs to a place, or an empty result when nothing is
## searchable there.
static func load_for_location(location_id: String) -> Dictionary:
	for path: String in ZONE_PATHS:
		var loaded := load_path(path)
		if not bool(loaded.get("ok", false)):
			continue
		if String(Dictionary(loaded["template"]).get("location_id", "")) == location_id:
			return loaded
	return {"ok": false, "template": {}, "errors": []}


static func load_by_id(zone_id: String) -> Dictionary:
	for path: String in ZONE_PATHS:
		var loaded := load_path(path)
		if bool(loaded.get("ok", false)) and String(Dictionary(loaded["template"]).get("id", "")) == zone_id:
			return loaded
	return {"ok": false, "template": {}, "errors": []}


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось открыть шаблон поисковой зоны: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("Шаблон поисковой зоны не является JSON-объектом")
	var template: Dictionary = SerializedValue.normalize_json_numbers(parsed)
	var validation := TemplateValidator.validate(template)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"template": {},
			"errors": Array(validation.get("errors", [])).duplicate(),
		}
	return {"ok": true, "template": template.duplicate(true), "errors": []}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "template": {}, "errors": [message]}
