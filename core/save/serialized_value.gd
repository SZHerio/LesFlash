class_name SerializedValue
extends RefCounted

## Reading numbers and maps out of a save file that may be wrong about them.
##
## Anything arriving from disk is untrusted: a hand-edited save, a file written
## by an older build, a JSON parser that turned every integer into a float. These
## helpers answer the same question each time — is this value what it claims to
## be — and return null rather than guessing.
##
## Three modules had grown their own copies of this, and the copies had drifted:
## one of them accepted integers past the range JSON can represent exactly, so a
## save that RunState refused was waved through elsewhere. The strict reading is
## the one kept here.

static func parse_int_map(raw: Variant, keys: Array, minimum: int, maximum: int) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY or raw.size() != keys.size():
		return null
	var result: Dictionary = {}
	for key in keys:
		var value: Variant = parse_integral(raw.get(key, null))
		if value == null or int(value) < minimum or int(value) > maximum:
			return null
		result[key] = int(value)
	return result


static func parse_string_int_map(raw: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var result: Dictionary = {}
	for raw_key in raw:
		if typeof(raw_key) != TYPE_STRING or String(raw_key).is_empty():
			return null
		var value: Variant = parse_integral(raw[raw_key])
		if value == null or int(value) < minimum or int(value) > maximum:
			return null
		result[String(raw_key)] = int(value)
	return result


static func parse_integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var float_value := float(value)
	if not is_finite(float_value) or float_value != floor(float_value):
		return null
	if absf(float_value) > 9_007_199_254_740_991.0:
		return null
	return int(float_value)


static func normalized_stamp(raw: Dictionary) -> Dictionary:
	var result := {
		"year": int(raw["year"]),
		"month": int(raw["month"]),
		"day": int(raw["day"]),
		"minute_of_day": int(raw["minute_of_day"]),
	}
	if raw.has("elapsed_minutes") and parse_integral(raw["elapsed_minutes"]) != null:
		result["elapsed_minutes"] = int(raw["elapsed_minutes"])
	return result


static func validate_exact_int_map(
	values: Dictionary,
	keys: Array,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	if values.size() != keys.size():
		errors.append("%s must contain exactly the configured keys" % path)
	for key in keys:
		if not values.has(key) or typeof(values[key]) != TYPE_INT:
			errors.append("%s.%s must be an integer" % [path, key])
			continue
		var value: int = values[key]
		if value < minimum or value > maximum:
			errors.append("%s.%s is outside allowed range" % [path, key])


static func validate_string_int_map(
	values: Dictionary,
	minimum: int,
	maximum: int,
	path: String,
	errors: Array[String]
) -> void:
	for key in values:
		if typeof(key) != TYPE_STRING or String(key).is_empty():
			errors.append("%s keys must be non-empty strings" % path)
			continue
		if typeof(values[key]) != TYPE_INT or int(values[key]) < minimum or int(values[key]) > maximum:
			errors.append("%s.%s is outside allowed integer range" % [path, key])


static func validate_json_value(
	value: Variant,
	path: String,
	errors: Array[String],
	depth: int = 0
) -> void:
	if depth > 32:
		errors.append("%s exceeds maximum nesting depth" % path)
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return
		TYPE_INT:
			var integer_value := int(value)
			if integer_value < -GameRules.JSON_SAFE_INTEGER_MAX or integer_value > GameRules.JSON_SAFE_INTEGER_MAX:
				errors.append("%s contains an integer outside JSON's exact range" % path)
		TYPE_FLOAT:
			if not is_finite(float(value)):
				errors.append("%s contains a non-finite number" % path)
		TYPE_ARRAY:
			for index in range(value.size()):
				validate_json_value(value[index], "%s[%d]" % [path, index], errors, depth + 1)
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string dictionary key" % path)
					continue
				validate_json_value(value[key], "%s.%s" % [path, key], errors, depth + 1)
		_:
			errors.append("%s contains a non-JSON value of type %s" % [path, type_string(typeof(value))])


## Godot's JSON parser returns open-ended numeric payloads as floats. Gameplay
## effects use integer quantities, so integral values are normalized on load to
## keep journal/deferred payloads stable across a save round-trip. Fractional
## values remain floats.
static func normalize_json_numbers(value: Variant, depth: int = 0) -> Variant:
	if depth > 32:
		return null
	match typeof(value):
		TYPE_FLOAT:
			var numeric := float(value)
			if (
				is_finite(numeric)
				and numeric >= -float(GameRules.JSON_SAFE_INTEGER_MAX)
				and numeric <= float(GameRules.JSON_SAFE_INTEGER_MAX)
				and numeric == roundf(numeric)
			):
				return int(numeric)
			return numeric
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value:
				normalized_array.append(normalize_json_numbers(item, depth + 1))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary: Dictionary = {}
			for key: Variant in value:
				normalized_dictionary[key] = normalize_json_numbers(value[key], depth + 1)
			return normalized_dictionary
		_:
			return value


static func append_nested_errors(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	if bool(validation.get("ok", false)):
		return
	var nested: Variant = validation.get("errors", [])
	if typeof(nested) != TYPE_ARRAY:
		errors.append("%s validation failed" % prefix)
		return
	for error in nested:
		errors.append("%s: %s" % [prefix, String(error)])
