class_name InventoryMetadata
extends RefCounted

## JSON-safe metadata contract shared by runtime inventory commands and saves.
## Metadata is deliberately bounded because it is content-owned, recursively
## serialized data rather than an executable extension point.

const MAX_DEPTH := 32
const NORMALIZE_MAX_DEPTH := MAX_DEPTH + 16
const JSON_SAFE_INTEGER_MAX := 9_007_199_254_740_991
const FIRST_UNSAFE_INTEGER_FLOAT := 9_007_199_254_740_992.0


static func validate(value: Variant, path: String = "metadata") -> Dictionary:
	var errors: Array[String] = []
	_validate_value(value, path, errors, 0)
	return {"ok": errors.is_empty(), "errors": errors}


static func normalize(value: Variant) -> Variant:
	return _normalize_value(value, 0)


static func exactly_equal(left: Dictionary, right: Dictionary) -> bool:
	return left == right


static func _validate_value(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int
) -> void:
	if depth > MAX_DEPTH:
		errors.append("%s exceeds maximum nesting depth %d" % [path, MAX_DEPTH])
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return
		TYPE_INT:
			var integer_value := int(value)
			if (
				integer_value < -JSON_SAFE_INTEGER_MAX
				or integer_value > JSON_SAFE_INTEGER_MAX
			):
				errors.append("%s contains an integer outside JSON's exact range" % path)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("%s contains a non-finite number" % path)
		TYPE_ARRAY:
			for index in range(value.size()):
				_validate_value(
					value[index],
					"%s[%d]" % [path, index],
					errors,
					depth + 1
				)
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string dictionary key" % path)
					continue
				_validate_value(
					value[key],
					"%s.%s" % [path, String(key)],
					errors,
					depth + 1
				)
		_:
			errors.append(
				"%s contains a non-JSON value of type %s"
				% [path, type_string(typeof(value))]
			)


static func _normalize_value(value: Variant, depth: int) -> Variant:
	if depth > NORMALIZE_MAX_DEPTH:
		return value
	match typeof(value):
		TYPE_FLOAT:
			var numeric := float(value)
			if (
				is_finite(numeric)
				and numeric > -FIRST_UNSAFE_INTEGER_FLOAT
				and numeric < FIRST_UNSAFE_INTEGER_FLOAT
				and numeric == floor(numeric)
			):
				return int(numeric)
			return numeric
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value:
				normalized_array.append(_normalize_value(item, depth + 1))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary: Dictionary = {}
			for key: Variant in value:
				normalized_dictionary[key] = _normalize_value(value[key], depth + 1)
			return normalized_dictionary
		_:
			return value
