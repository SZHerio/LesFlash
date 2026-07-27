class_name ContentCatalogRules
extends RefCounted

## Structural helpers only. Domain-specific references remain in each catalog
## validator and in ContentCatalogBundle's cross-catalog pass.


static func validate_header(
	catalog: Dictionary,
	expected_catalog_id: String,
	expected_schema_version: int,
	errors: Array[String]
) -> void:
	if catalog.get("schema_version", null) != expected_schema_version:
		errors.append("schema_version должен быть равен %d" % expected_schema_version)
	if String(catalog.get("catalog_id", "")) != expected_catalog_id:
		errors.append("catalog_id должен быть равен %s" % expected_catalog_id)


static func index_entries(
	raw_entries: Variant,
	path: String,
	required_prefix: String,
	errors: Array[String],
	require_non_empty: bool = true
) -> Dictionary:
	var result: Dictionary = {}
	if not raw_entries is Array:
		errors.append("%s должен быть массивом" % path)
		return result
	if require_non_empty and raw_entries.is_empty():
		errors.append("%s не должен быть пустым" % path)
	for index: int in raw_entries.size():
		var raw_entry: Variant = raw_entries[index]
		var entry_path := "%s[%d]" % [path, index]
		if not raw_entry is Dictionary:
			errors.append("%s должен быть объектом" % entry_path)
			continue
		var entry_id := String(raw_entry.get("id", ""))
		if not valid_id(entry_id):
			errors.append("%s.id должен быть ASCII lower_snake_case" % entry_path)
			continue
		if not required_prefix.is_empty() and not entry_id.begins_with(required_prefix):
			errors.append("%s.id должен начинаться с %s" % [entry_path, required_prefix])
		if result.has(entry_id):
			errors.append("%s.id повторяет %s" % [entry_path, entry_id])
			continue
		result[entry_id] = Dictionary(raw_entry)
	return result


static func validate_text(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append("%s должен содержать текст" % path)


static func validate_id_array(
	value: Variant,
	path: String,
	errors: Array[String],
	require_non_empty: bool = false
) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		errors.append("%s должен быть массивом ID" % path)
		return result
	if require_non_empty and value.is_empty():
		errors.append("%s не должен быть пустым" % path)
	var seen: Dictionary = {}
	for index: int in value.size():
		var entry_id := String(value[index])
		if not valid_id(entry_id):
			errors.append("%s[%d] должен быть ASCII lower_snake_case" % [path, index])
			continue
		if seen.has(entry_id):
			errors.append("%s содержит повторный ID %s" % [path, entry_id])
			continue
		seen[entry_id] = true
		result.append(entry_id)
	return result


static func validate_int_range(
	value: Variant,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_INT or int(value) < minimum or int(value) > maximum:
		errors.append("%s должен быть целым числом %d..%d" % [path, minimum, maximum])


static func valid_id(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var identifier := String(value)
	if identifier.is_empty() or identifier != identifier.strip_edges():
		return false
	if identifier.begins_with("_") or identifier.ends_with("_") or "__" in identifier:
		return false
	for index: int in identifier.length():
		var code := identifier.unicode_at(index)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lower and not is_digit and code != 95:
			return false
		if index == 0 and not is_lower:
			return false
	return true


static func append_errors(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		errors.append("%s: %s" % [prefix, String(raw_error)])
