class_name SessionSurvivalPassage
extends RefCounted

## Prepares survival-driven meter changes for one confirmed session command.
## The helper is pure: it mutates neither the live session nor its candidate.

const SurvivalTimeRulesScript := preload("res://game/survival/survival_time_rules.gd")


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
	var simulation := SurvivalTimeRulesScript.simulate(
		run_state.meters,
		survival_state,
		minutes,
		profile
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
