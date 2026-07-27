class_name CommerceValidationRules
extends RefCounted

## Shared pure scalar/collection checks for commerce catalog schemas.


static func expect_range(value: Variant, minimum: int, maximum: int, path: String, errors: Array[String]) -> void:
	if not value is Array or value.size() != 2:
		errors.append("%s must be a two-integer range" % path)
		return
	if not is_int_in_range(value[0], minimum, maximum) or not is_int_in_range(value[1], minimum, maximum):
		errors.append("%s values must be integers from %d to %d" % [path, minimum, maximum])
		return
	if int(value[0]) > int(value[1]):
		errors.append("%s minimum exceeds maximum" % path)


static func expect_id_array(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("%s must be an array" % path)
		return
	var seen: Dictionary = {}
	for index in range(value.size()):
		var identifier := expect_id(value[index], "%s[%d]" % [path, index], errors)
		if not identifier.is_empty() and seen.has(identifier):
			errors.append("%s repeats %s" % [path, identifier])
		seen[identifier] = true


static func expect_id(value: Variant, path: String, errors: Array[String]) -> String:
	if typeof(value) != TYPE_STRING:
		errors.append("%s must be a lower_snake_case string" % path)
		return ""
	var value_text := String(value)
	if value_text.is_empty() or value_text[0] == "_" or value_text[-1] == "_":
		errors.append("%s must be a lower_snake_case string" % path)
		return ""
	for character: String in value_text:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			errors.append("%s must be a lower_snake_case string" % path)
			return ""
	return value_text


static func expect_text(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append("%s must be non-empty text" % path)


static func expect_int(
	value: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	if not is_int_in_range(value.get(key, null), minimum, maximum):
		errors.append("%s.%s must be integer %d" % [path, key, minimum] if minimum == maximum else "%s.%s is out of range" % [path, key])


static func expect_positive_int(value: Dictionary, key: String, path: String, errors: Array[String]) -> void:
	if not is_positive_int(value.get(key, null)):
		errors.append("%s.%s must be a positive integer" % [path, key])


static func is_positive_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0


static func is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func result(errors: Array) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}
