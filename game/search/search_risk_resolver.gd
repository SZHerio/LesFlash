class_name SearchRiskResolver
extends RefCounted

## Turns accumulated search risk into a concrete, answerable encounter.
##
## An encounter is queued only when a real card can be drawn for the current
## context. A risk spike that matches no authored card therefore leaves the
## player free to keep searching instead of facing an unanswerable prompt.

const EventContextScript := preload("res://game/events/event_context.gd")
const SelectorScript := preload("res://game/events/search_encounter_selector.gd")
const WorldReadModelScript := preload("res://core/world/world_read_model.gd")
const EventHistoryScript := preload("res://game/events/event_history.gd")

const ENCOUNTER_THRESHOLD := 35

## A resolved encounter discharges most of the accumulated attention. Risk stays
## meaningful afterwards: it can climb back to the threshold and trigger again.
const RELIEF_DIVISOR := 2


static func apply(
	session: Object,
	snapshot: Dictionary,
	source: Dictionary,
	location_id: String,
	noise_delta: int,
	trespass_delta: int,
	repeated_delta: int = 0
) -> Dictionary:
	if session == null:
		return {"ok": false, "code": "missing_session", "error": "Игровая сессия отсутствует", "snapshot": snapshot.duplicate(true), "encounter": {}}
	var run_state: Variant = session.get("run_state")
	if not run_state is RunState:
		return {"ok": false, "code": "missing_run_state", "error": "Состояние героя отсутствует", "snapshot": snapshot.duplicate(true), "encounter": {}}
	var result := snapshot.duplicate(true)
	var before: Dictionary = Dictionary(result.get("risk", {})).duplicate(true)
	var before_score := score(before)
	var after := {
		"noise": maxi(int(before.get("noise", 0)) + noise_delta, 0),
		"trespass": maxi(int(before.get("trespass", 0)) + trespass_delta, 0),
		"repeated_attempts": maxi(
			int(before.get("repeated_attempts", 0)) + repeated_delta,
			0
		),
	}
	after["score"] = score(after)
	result["risk"] = after
	var encounter: Dictionary = {}
	if (
		before_score < ENCOUNTER_THRESHOLD
		and int(after["score"]) >= ENCOUNTER_THRESHOLD
		and Dictionary(result.get("pending_encounter", {})).is_empty()
	):
		encounter = _build_encounter(session, run_state, result, source, location_id, after)
		if not encounter.is_empty():
			result["pending_encounter"] = encounter
	return {
		"ok": true,
		"snapshot": result,
		"risk_before": before_score,
		"risk_after": int(after["score"]),
		"encounter": encounter.duplicate(true),
	}


## Applied after an encounter is answered, so the risk meter keeps describing a
## live situation instead of staying pinned above the threshold forever.
static func relieve(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	var risk: Dictionary = Dictionary(result.get("risk", {})).duplicate(true)
	var relieved := {
		"noise": int(risk.get("noise", 0)) / RELIEF_DIVISOR,
		"trespass": int(risk.get("trespass", 0)) / RELIEF_DIVISOR,
		"repeated_attempts": int(risk.get("repeated_attempts", 0)) / RELIEF_DIVISOR,
	}
	relieved["score"] = score(relieved)
	result["risk"] = relieved
	return result


static func score(risk: Dictionary) -> int:
	return clampi(
		int(risk.get("noise", 0)) * 4
		+ int(risk.get("trespass", 0)) * 5
		+ int(risk.get("repeated_attempts", 0)) * 3,
		0,
		100
	)


static func _build_encounter(
	session: Object,
	run_state: RunState,
	snapshot: Dictionary,
	source: Dictionary,
	location_id: String,
	risk: Dictionary
) -> Dictionary:
	var tags: Array = []
	if int(risk["noise"]) > 0:
		tags.append("noise")
	if int(risk["trespass"]) > 0:
		tags.append("trespass")
	if int(risk["repeated_attempts"]) > 0:
		tags.append("repeated_attempts")
	var world_context := _session_context(session)
	world_context.merge({
		"location_id": location_id,
		"weather_id": String(Dictionary(snapshot.get("generation_context", {})).get("weather", "dry")),
		"cooldowns": Dictionary(snapshot.get("encounter_cooldowns", {})).duplicate(true),
		"history_facts": EventHistoryScript.facts(run_state, Array(snapshot.get("encounter_history", []))),
		"risk": {
			"score": int(risk["score"]),
			"noise": int(risk["noise"]),
			"trespass": int(risk["trespass"]),
			"tags": tags,
		},
	}, true)
	var context := EventContextScript.build(
		run_state,
		{
			"kind": "search",
			"id": String(snapshot.get("template_id", "search")),
			"action_id": String(source.get("action_id", "")),
			"object_id": String(source.get("object_id", "")),
		},
		world_context
	)
	if context.is_empty():
		return {}
	var encounter_id := "search_attention:%s:%d:%s:%s" % [
		String(snapshot.get("template_id", "zone")),
		int(snapshot.get("visit_index", 1)),
		String(source.get("object_id", "object")),
		String(source.get("action_id", "action")),
	]
	var selected := SelectorScript.select(
		SelectorScript.zone_seed(snapshot),
		encounter_id,
		context
	)
	if selected.is_empty():
		return {}
	return {
		"id": encounter_id,
		"kind": "search_attention",
		"status": "pending",
		"threshold": ENCOUNTER_THRESHOLD,
		"card_id": String(selected["card_id"]),
		"tone": String(selected.get("tone", "neutral")),
		"cooldown_minutes": int(selected.get("cooldown_minutes", 0)),
		"context": context,
	}


static func _session_context(session: Object) -> Dictionary:
	var result: Dictionary = {}
	if session == null:
		return result
	var world: Variant = session.get("world_state")
	if world is WorldState:
		result["world"] = WorldReadModelScript.rules_projection(world)
	var social: Variant = session.get("social_state")
	if social is SocialState:
		result["relationships"] = social.relationships.duplicate(true)
		result["reputations"] = social.reputations.duplicate(true)
		result["npc_memories"] = social.memories.duplicate(true)
		result["commitments"] = social.commitments.duplicate(true)
	return result
