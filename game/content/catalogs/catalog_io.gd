class_name ContentCatalogIo
extends RefCounted

## Read-only JSON loader shared by the M3F.1 definition catalogs.

const JsonValidator := preload("res://core/save/json_value_validator.gd")


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Каталог не найден: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Каталог не удалось открыть: %s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(
			"Некорректный JSON в %s, строка %d: %s" % [
				path,
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
	if not parser.data is Dictionary:
		return _failure("Корень каталога должен быть JSON-объектом: %s" % path)
	var catalog: Dictionary = JsonValidator.normalize_numbers(parser.data)
	var json_validation := JsonValidator.validate(catalog, path)
	if not bool(json_validation.get("ok", false)):
		return {
			"ok": false,
			"catalog": {},
			"errors": Array(json_validation.get("errors", [])).duplicate(),
		}
	return {"ok": true, "catalog": catalog.duplicate(true), "errors": []}


static func validated_result(parsed: Dictionary, validation: Dictionary) -> Dictionary:
	if not bool(parsed.get("ok", false)):
		return {
			"ok": false,
			"catalog": {},
			"errors": Array(parsed.get("errors", [])).duplicate(),
		}
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"catalog": {},
			"errors": Array(validation.get("errors", [])).duplicate(),
		}
	return {
		"ok": true,
		"catalog": Dictionary(parsed.get("catalog", {})).duplicate(true),
		"errors": [],
	}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": {}, "errors": [message]}
