class_name DeterministicRng
extends RefCounted

## Deterministic random stream owned by one run.
##
## Seed and state are serialized as decimal strings. Godot's JSON parser represents
## JSON numbers as floating point values, which cannot exactly preserve every
## 64-bit RNG state.

var seed: int = GameRules.DEFAULT_RNG_SEED
var state: int:
	get:
		return _rng.state
	set(value):
		_rng.state = value

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = GameRules.DEFAULT_RNG_SEED) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	seed = seed_value
	_rng.seed = seed_value


func next_u32() -> int:
	return _rng.randi()


func next_int(minimum: int, maximum: int) -> int:
	if minimum > maximum:
		push_error("DeterministicRng.next_int minimum is greater than maximum.")
		return minimum
	return _rng.randi_range(minimum, maximum)


func next_float() -> float:
	return _rng.randf()


func next_float_range(minimum: float, maximum: float) -> float:
	if not is_finite(minimum) or not is_finite(maximum) or minimum > maximum:
		push_error("DeterministicRng.next_float_range received an invalid range.")
		return minimum
	return _rng.randf_range(minimum, maximum)


func chance(probability: float) -> bool:
	if not is_finite(probability):
		return false
	return next_float() < clampf(probability, 0.0, 1.0)


func weighted_index(weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0.0
	for weight_value in weights:
		if typeof(weight_value) != TYPE_INT and typeof(weight_value) != TYPE_FLOAT:
			return -1
		var weight := float(weight_value)
		if not is_finite(weight) or weight < 0.0:
			return -1
		total += weight
	if total <= 0.0 or not is_finite(total):
		return -1
	var cursor := next_float_range(0.0, total)
	for index in range(weights.size()):
		cursor -= float(weights[index])
		if cursor < 0.0:
			return index
	return weights.size() - 1


func pick(values: Array) -> Variant:
	if values.is_empty():
		return null
	return values[next_int(0, values.size() - 1)]


func shuffled_copy(values: Array) -> Array:
	var result := values.duplicate(true)
	for index in range(result.size() - 1, 0, -1):
		var swap_index := next_int(0, index)
		var temporary: Variant = result[index]
		result[index] = result[swap_index]
		result[swap_index] = temporary
	return result


func to_dict() -> Dictionary:
	return {
		"seed": str(seed),
		"state": str(_rng.state),
	}


static func from_dict(data: Dictionary) -> DeterministicRng:
	var parsed_seed: Variant = _parse_exact_int(data.get("seed", null))
	var parsed_state: Variant = _parse_exact_int(data.get("state", null))
	if parsed_seed == null or parsed_state == null:
		return null
	var result := DeterministicRng.new(parsed_seed)
	result.state = parsed_state
	var validation := result.validate()
	return result if validation["ok"] else null


func clone() -> DeterministicRng:
	var result := DeterministicRng.from_dict(to_dict())
	if result == null:
		push_error("DeterministicRng clone failed validation; reseeding a fallback stream.")
		return DeterministicRng.new(seed)
	return result


func validate() -> Dictionary:
	var errors: Array[String] = []
	var serialized := to_dict()
	if not String(serialized["seed"]).is_valid_int():
		errors.append("rng.seed is not a valid signed 64-bit integer")
	if not String(serialized["state"]).is_valid_int():
		errors.append("rng.state is not a valid signed 64-bit integer")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
	}


static func _parse_exact_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_STRING:
		return null
	var text := String(value)
	if not text.is_valid_int():
		return null
	return int(text)
