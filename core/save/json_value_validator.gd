class_name JsonValueValidator
extends RefCounted

## Shared guard for dictionaries persisted through Godot JSON.
##
## JSON.parse() stores numbers as doubles, so integers outside the exact
## 53-bit range are rejected. The validator also bounds recursive input to
## prevent malformed content or saves from exhausting the stack.

const MAX_DEPTH := 32
const MAX_COLLECTION_ITEMS := 100_000


static func validate(value: Variant, path: String = "value") -> Dictionary:
	var errors: Array[String] = []
	var budget := [MAX_COLLECTION_ITEMS]
	_validate_value(value, path, errors, budget, 0)
	return {"ok": errors.is_empty(), "errors": errors}


static func normalize_numbers(value: Variant) -> Variant:
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and float(value) == floor(float(value))
		and absf(float(value)) <= float(GameRules.JSON_SAFE_INTEGER_MAX)
	):
		return int(value)
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(normalize_numbers(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[key] = normalize_numbers(value[key])
		return dictionary
	return value


static func _validate_value(
	value: Variant,
	path: String,
	errors: Array[String],
	budget: Array,
	depth: int
) -> void:
	if depth > MAX_DEPTH:
		errors.append("%s exceeds maximum nesting depth" % path)
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return
		TYPE_INT:
			if abs(float(value)) > float(GameRules.JSON_SAFE_INTEGER_MAX):
				errors.append("%s contains an inexact integer" % path)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("%s contains a non-finite number" % path)
		TYPE_ARRAY:
			_consume_budget(value.size(), path, errors, budget)
			if int(budget[0]) < 0:
				return
			for index in range(value.size()):
				_validate_value(value[index], "%s[%d]" % [path, index], errors, budget, depth + 1)
		TYPE_DICTIONARY:
			_consume_budget(value.size(), path, errors, budget)
			if int(budget[0]) < 0:
				return
			for key in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string key" % path)
					continue
				_validate_value(value[key], "%s.%s" % [path, key], errors, budget, depth + 1)
		_:
			errors.append("%s contains unsupported type %s" % [path, type_string(typeof(value))])


static func _consume_budget(
	amount: int,
	path: String,
	errors: Array[String],
	budget: Array
) -> void:
	budget[0] = int(budget[0]) - amount
	if int(budget[0]) < 0:
		errors.append("%s exceeds maximum collection size" % path)
