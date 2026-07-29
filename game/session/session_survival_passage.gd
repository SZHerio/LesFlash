class_name SessionSurvivalPassage
extends RefCounted

## Prepares survival-driven meter changes for one confirmed session command.
## The helper is pure: it mutates neither the live session nor its candidate.

const SurvivalTimeRulesScript := preload("res://game/survival/survival_time_rules.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")
const AgingRulesScript := preload("res://game/aging/aging_rules.gd")

## Boots and a coat do not create energy; they stop the day from taking as much
## of it. The relief is one fixed-point unit at most, so the drain never reaches
## zero and no outfit makes the week free.
const STAMINA_PER_DRAIN_UNIT := 30
const MAX_DRAIN_RELIEF_UNITS := 1


static func prepare(
	session: Object,
	actor_effects: Array,
	passage_id: String,
	profile: Dictionary
) -> Dictionary:
	if not _has_property(session, "survival_state"):
		return {"ok": true, "active": false, "effects": actor_effects.duplicate(true)}
	var minutes := 0
	var first_time_index := -1
	for index: int in actor_effects.size():
		var raw_effect: Variant = actor_effects[index]
		if not raw_effect is Dictionary:
			continue
		var effect_type := String(
			raw_effect.get("type", raw_effect.get("kind", ""))
		).strip_edges().to_lower().replace("-", "_")
		if effect_type != "advance_time":
			continue
		if first_time_index < 0:
			first_time_index = index
		minutes += int(raw_effect.get("minutes", raw_effect.get("amount", 0)))
	if minutes <= 0:
		return {"ok": true, "active": false, "effects": actor_effects.duplicate(true)}
	if first_time_index > 0:
		return _failure(
			"time_effect_order",
			"Продвижение времени должно быть первым эффектом подтверждённой команды"
		)
	var run_state: RunState = session.get("run_state")
	var survival_state: SurvivalState = session.get("survival_state")
	if survival_state == null or survival_state.has_applied(passage_id):
		return _failure(
			"invalid_survival_state",
			"Состояние выживания не готово к этой команде"
		)
	if run_state.calendar.elapsed_minutes != survival_state.processed_elapsed_minutes:
		return _failure(
			"time_desynchronized",
			"Календарь и потребности рассинхронизированы"
		)
	# The years are in the body before they are anywhere else: the same stretch of
	# time takes more out of an older man and less out of a young one. This is
	# the only place it has to be said, because every confirmed command that
	# spends time comes through here.
	var aged_profile := profile.duplicate(true)
	var stamina := AgingRulesScript.stamina_basis_points(run_state)
	if stamina != 10_000 and aged_profile.has("energy_drain_units_per_minute"):
		aged_profile["energy_drain_units_per_minute"] = maxi(
			int(round(float(int(aged_profile["energy_drain_units_per_minute"])) * 10_000.0 / float(stamina))),
			1
		)
	var simulation := SurvivalTimeRulesScript.simulate(
		run_state.meters,
		survival_state,
		minutes,
		_with_equipment(aged_profile, run_state)
	)
	if not bool(simulation.get("ok", false)):
		return simulation
	return {
		"ok": true,
		"active": true,
		"effects": _replace_time_effect(actor_effects, simulation),
		"survival_state": simulation["survival_state"],
		"requested_minutes": minutes,
		"consumed_minutes": int(simulation.get("consumed_minutes", 0)),
		"status": String(simulation.get("status", "active")),
	}


## Worn equipment is passive, so it applies to every confirmed interval rather
## than to a list of commands somebody remembered to annotate.
static func _with_equipment(profile: Dictionary, run_state: RunState) -> Dictionary:
	var result := profile.duplicate(true)
	var stamina := EquipmentRulesScript.modifier(run_state.inventory, "travel_stamina")
	if stamina <= 0:
		return result
	@warning_ignore("integer_division")
	var relief: int = mini(stamina / STAMINA_PER_DRAIN_UNIT, MAX_DRAIN_RELIEF_UNITS)
	if relief <= 0:
		return result
	var drain := int(result.get(
		"energy_drain_units_per_minute",
		SurvivalTimeRulesScript.DEFAULT_PROFILE["energy_drain_units_per_minute"]
	))
	result["energy_drain_units_per_minute"] = maxi(drain - relief, 1)
	return result


static func _replace_time_effect(actor_effects: Array, simulation: Dictionary) -> Array:
	var effects: Array = []
	var inserted := false
	for raw_effect: Variant in actor_effects:
		var is_time := (
			raw_effect is Dictionary
			and String(
				raw_effect.get("type", raw_effect.get("kind", ""))
			).strip_edges().to_lower().replace("-", "_") == "advance_time"
		)
		if not is_time:
			effects.append(
				Dictionary(raw_effect).duplicate(true) if raw_effect is Dictionary else raw_effect
			)
			continue
		if inserted:
			continue
		inserted = true
		var time_effect: Dictionary = Dictionary(raw_effect).duplicate(true)
		time_effect["minutes"] = int(simulation.get("consumed_minutes", 0))
		effects.append(time_effect)
		for meter_id: String in ["health", "hunger", "energy", "mental_state"]:
			var delta := int(
				Dictionary(simulation.get("meter_deltas", {})).get(meter_id, 0)
			)
			if delta != 0:
				effects.append({"type": "change_state", "id": meter_id, "delta": delta})
	return effects


static func _has_property(value: Object, name: String) -> bool:
	for raw_property: Variant in value.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == name:
			return true
	return false


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
