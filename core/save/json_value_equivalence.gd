class_name JsonValueEquivalence
extends RefCounted

## Strict comparison for an in-memory value and the same value reconstructed
## through Godot JSON. It accepts only lossless int/float normalization and is
## intentionally unsuitable for fuzzy gameplay math.

const GameRulesScript := preload("res://core/config/game_rules.gd")
const MAX_DEPTH := 64


static func are_equivalent(actual: Variant, expected: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	if _is_number(actual_type) and _is_number(expected_type):
		return _numbers_are_equivalent(actual, expected, actual_type, expected_type)
	if actual_type != expected_type:
		return false
	if actual_type == TYPE_DICTIONARY:
		var actual_dictionary: Dictionary = actual
		var expected_dictionary: Dictionary = expected
		if actual_dictionary.size() != expected_dictionary.size():
			return false
		for key: Variant in expected_dictionary:
			if (
				not actual_dictionary.has(key)
				or not are_equivalent(
					actual_dictionary[key],
					expected_dictionary[key],
					depth + 1
				)
			):
				return false
		return true
	if actual_type == TYPE_ARRAY:
		var actual_array: Array = actual
		var expected_array: Array = expected
		if actual_array.size() != expected_array.size():
			return false
		for index in expected_array.size():
			if not are_equivalent(actual_array[index], expected_array[index], depth + 1):
				return false
		return true
	return actual == expected


static func _numbers_are_equivalent(
	actual: Variant,
	expected: Variant,
	actual_type: int,
	expected_type: int
) -> bool:
	if actual_type == TYPE_INT and expected_type == TYPE_INT:
		var actual_integer: int = actual
		var expected_integer: int = expected
		return (
			_is_json_safe_integer(actual_integer)
			and _is_json_safe_integer(expected_integer)
			and actual_integer == expected_integer
		)
	if actual_type == TYPE_FLOAT and expected_type == TYPE_FLOAT:
		var actual_float: float = actual
		var expected_float: float = expected
		return (
			is_finite(actual_float)
			and is_finite(expected_float)
			and actual_float == expected_float
		)
	var integer_value: int = actual if actual_type == TYPE_INT else expected
	var float_value: float = actual if actual_type == TYPE_FLOAT else expected
	return (
		_is_json_safe_integer(integer_value)
		and is_finite(float_value)
		and float_value == floor(float_value)
		and float_value >= -float(GameRulesScript.JSON_SAFE_INTEGER_MAX)
		and float_value <= float(GameRulesScript.JSON_SAFE_INTEGER_MAX)
		and int(float_value) == integer_value
	)


static func _is_number(type_id: int) -> bool:
	return type_id == TYPE_INT or type_id == TYPE_FLOAT


static func _is_json_safe_integer(value: int) -> bool:
	return (
		value >= -GameRulesScript.JSON_SAFE_INTEGER_MAX
		and value <= GameRulesScript.JSON_SAFE_INTEGER_MAX
	)
