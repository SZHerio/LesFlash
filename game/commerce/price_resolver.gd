class_name PriceResolver
extends RefCounted

## Deterministic integer-only price pipeline. Every stage rounds half up.

const BASIS_POINTS := 10_000
const MAX_FACTOR_BASIS_POINTS := 100_000
const MAX_PRICE := 1_000_000_000_000
const MAX_INTERMEDIATE := 9_007_199_254_740_991
const FACTOR_ORDER := [
	"consumer_price_index_basis_points",
	"category_supply_basis_points",
	"district_basis_points",
	"store_markup_basis_points",
	"condition_quality_basis_points",
	"relationship_basis_points",
]


static func resolve(base_value: Variant, factors: Variant) -> Dictionary:
	if typeof(base_value) != TYPE_INT or int(base_value) < 0 or int(base_value) > MAX_PRICE:
		return _failure("invalid_base_value", "base price must be a non-negative bounded integer")
	if not factors is Dictionary:
		return _failure("invalid_factors", "price factors must be a dictionary")
	var current := int(base_value)
	var trace: Array = [{"stage": "base_value_1980", "input": current, "factor_basis_points": BASIS_POINTS, "output": current}]
	for factor_id: String in FACTOR_ORDER:
		if not factors.has(factor_id):
			return _failure("missing_factor", "missing price factor %s" % factor_id)
		var applied := apply_basis_points(current, factors[factor_id])
		if not bool(applied.get("ok", false)):
			applied["factor_id"] = factor_id
			return applied
		var output := int(applied["value"])
		trace.append({
			"stage": factor_id,
			"input": current,
			"factor_basis_points": int(factors[factor_id]),
			"output": output,
		})
		current = output
	return {"ok": true, "code": "ok", "unit_price": current, "trace": trace}


static func neutral_factors(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for factor_id: String in FACTOR_ORDER:
		result[factor_id] = BASIS_POINTS
	for key: Variant in overrides:
		if String(key) in FACTOR_ORDER:
			result[String(key)] = overrides[key]
	return result


static func apply_basis_points(value: Variant, factor_basis_points: Variant) -> Dictionary:
	if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > MAX_PRICE:
		return _failure("invalid_value", "price stage input must be a non-negative bounded integer")
	if (
		typeof(factor_basis_points) != TYPE_INT
		or int(factor_basis_points) < 0
		or int(factor_basis_points) > MAX_FACTOR_BASIS_POINTS
	):
		return _failure("invalid_factor", "basis-point factor must be an integer from 0 to %d" % MAX_FACTOR_BASIS_POINTS)
	var input := int(value)
	var factor := int(factor_basis_points)
	if factor > 0 and input > (MAX_INTERMEDIATE - BASIS_POINTS / 2) / factor:
		return _failure("price_overflow", "price multiplication exceeds the exact integer range")
	var numerator := input * factor + BASIS_POINTS / 2
	@warning_ignore("integer_division")
	var rounded: int = numerator / BASIS_POINTS
	if rounded > MAX_PRICE:
		return _failure("price_overflow", "resolved price exceeds the money domain")
	return {"ok": true, "code": "ok", "value": rounded}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "trace": []}
