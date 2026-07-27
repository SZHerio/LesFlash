class_name SurvivalTimeRules
extends RefCounted

## Pure fixed-point need progression. One simulation minute is the canonical
## integration step, so chunking a confirmed interval cannot change its result.

const SurvivalStateScript := preload("res://game/survival/survival_state.gd")

const PROFILE_KEYS := [
	"hunger_units_per_minute",
	"energy_drain_units_per_minute",
	"health_extra_damage_units_per_minute",
	"mental_extra_damage_units_per_minute",
]
const DEFAULT_PROFILE := {
	"hunger_units_per_minute": 3,
	"energy_drain_units_per_minute": 2,
	"health_extra_damage_units_per_minute": 0,
	"mental_extra_damage_units_per_minute": 0,
}
const MAX_RATE_UNITS_PER_MINUTE := 600
const REQUIRED_METERS := ["health", "hunger", "energy", "tension", "mental_state"]


static func simulate(
	meters: Dictionary,
	survival_state: SurvivalState,
	requested_minutes: int,
	profile_overrides: Dictionary = {}
) -> Dictionary:
	var input_error := _validate_inputs(meters, survival_state, requested_minutes)
	if not input_error.is_empty():
		return _failure("invalid_input", input_error)
	var profile_result := normalize_profile(profile_overrides)
	if not bool(profile_result.get("ok", false)):
		return profile_result

	var candidate_state := survival_state.clone()
	var candidate_meters := meters.duplicate(true)
	var profile: Dictionary = profile_result["profile"]
	var initial_meters := meters.duplicate(true)
	var limit := mini(requested_minutes, candidate_state.minutes_until_week_complete())
	var consumed := 0

	if int(candidate_meters["health"]) <= 0:
		candidate_state.mark_dead("health_depleted")
	else:
		for _minute: int in range(limit):
			_apply_fixed(candidate_meters, candidate_state, "hunger", int(profile["hunger_units_per_minute"]), 1)
			_apply_fixed(candidate_meters, candidate_state, "energy", int(profile["energy_drain_units_per_minute"]), -1)
			var health_units := int(profile["health_extra_damage_units_per_minute"])
			health_units += _deprivation_health_units(candidate_meters)
			var mental_units := int(profile["mental_extra_damage_units_per_minute"])
			mental_units += _deprivation_mental_units(candidate_meters)
			_apply_fixed(candidate_meters, candidate_state, "health", health_units, -1)
			_apply_fixed(candidate_meters, candidate_state, "mental_state", mental_units, -1)
			candidate_state.processed_elapsed_minutes += 1
			consumed += 1
			if int(candidate_meters["health"]) <= 0:
				candidate_state.mark_dead("deprivation")
				break
			if candidate_state.processed_elapsed_minutes == candidate_state.week_end_elapsed_minutes():
				candidate_state.mark_week_complete()
				break

	var deltas: Dictionary = {}
	for key: String in ["health", "hunger", "energy", "mental_state"]:
		deltas[key] = int(candidate_meters[key]) - int(initial_meters[key])
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"requested_minutes": requested_minutes,
		"consumed_minutes": consumed,
		"unconsumed_minutes": requested_minutes - consumed,
		"meters": candidate_meters,
		"meter_deltas": deltas,
		"survival_state": candidate_state,
		"profile": profile,
		"status": candidate_state.status,
	}


static func normalize_profile(overrides: Dictionary = {}) -> Dictionary:
	for raw_key: Variant in overrides:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in PROFILE_KEYS:
			return _failure("invalid_profile", "Неизвестное поле профиля нагрузки: %s" % str(raw_key))
		if typeof(overrides[raw_key]) != TYPE_INT:
			return _failure("invalid_profile", "%s должен быть целым числом" % String(raw_key))
		if int(overrides[raw_key]) < 0 or int(overrides[raw_key]) > MAX_RATE_UNITS_PER_MINUTE:
			return _failure("invalid_profile", "%s находится вне допустимого диапазона" % String(raw_key))
	var result := DEFAULT_PROFILE.duplicate(true)
	result.merge(overrides, true)
	return {"ok": true, "code": "ok", "error": "", "profile": result}


static func _apply_fixed(
	meters: Dictionary,
	state: SurvivalState,
	meter_id: String,
	units: int,
	direction: int
) -> void:
	var total := int(state.remainders[meter_id]) + units
	@warning_ignore("integer_division")
	var points := total / SurvivalStateScript.FIXED_DENOMINATOR
	state.remainders[meter_id] = total % SurvivalStateScript.FIXED_DENOMINATOR
	if points > 0:
		meters[meter_id] = clampi(int(meters[meter_id]) + points * direction, 0, 100)


static func _deprivation_health_units(meters: Dictionary) -> int:
	var units := 0
	var hunger := int(meters["hunger"])
	var energy := int(meters["energy"])
	if hunger >= 90:
		units += 4
	elif hunger >= 75:
		units += 2
	if energy <= 10:
		units += 3
	elif energy <= 25:
		units += 1
	return units


static func _deprivation_mental_units(meters: Dictionary) -> int:
	var units := 0
	if int(meters["hunger"]) >= 75:
		units += 2
	if int(meters["energy"]) <= 20:
		units += 2
	if int(meters["tension"]) >= 70:
		units += 2
	return units


static func _validate_inputs(meters: Dictionary, survival_state: SurvivalState, minutes: int) -> String:
	if survival_state == null or not bool(survival_state.validate().get("ok", false)):
		return "SurvivalState повреждён"
	if survival_state.status != SurvivalStateScript.STATUS_ACTIVE:
		return "Жизненный цикл уже завершён"
	if minutes <= 0:
		return "Подтверждённый промежуток должен быть положительным"
	for key: String in REQUIRED_METERS:
		if not meters.has(key) or typeof(meters[key]) != TYPE_INT:
			return "Показатель %s должен быть целым числом" % key
		if int(meters[key]) < 0 or int(meters[key]) > 100:
			return "Показатель %s находится вне диапазона" % key
	return ""


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
