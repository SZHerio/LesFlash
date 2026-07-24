class_name SearchTemplateValidator
extends RefCounted

const GraphValidator := preload("res://game/search/search_graph_validator.gd")
const ContentValidator := preload("res://game/search/search_content_validator.gd")

const SCHEMA_VERSION := 1


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["Шаблон поисковой зоны должен быть объектом"]}
	var template: Dictionary = value
	if template.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("Ожидалась версия схемы поисковой зоны %d" % SCHEMA_VERSION)
	if not _positive_integer(template.get("template_version", null)):
		errors.append("template_version должен быть положительным целым числом")
	for field: String in ["id", "location_id", "title", "description"]:
		if typeof(template.get(field, null)) != TYPE_STRING or String(template[field]).strip_edges().is_empty():
			errors.append("%s должен быть непустой строкой" % field)

	_append_errors(GraphValidator.validate(template), errors)
	_append_errors(ContentValidator.validate(template, GraphValidator.node_ids(template)), errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _append_errors(validation: Dictionary, errors: Array[String]) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append(String(raw_error))


static func _positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0
