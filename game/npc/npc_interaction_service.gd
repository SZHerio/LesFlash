class_name NpcInteractionService
extends RefCounted

## Pure read boundary for NPC presence, authored conditions and repeat limits.

const InteractionCatalog := preload("res://game/npc/npc_interaction_catalog.gd")
const NpcCatalog := preload("res://game/content/catalogs/npc_catalog.gd")
const ScheduleResolver := preload("res://game/npc/npc_schedule_resolver.gd")
const InteractionHistory := preload("res://game/npc/npc_interaction_history.gd")
const EventContextScript := preload("res://game/events/event_context.gd")
const EventConditions := preload("res://game/events/event_condition_evaluator.gd")
const CheckResolverScript := preload("res://core/rules/check_resolver.gd")
const WorldReadModelScript := preload("res://core/world/world_read_model.gd")

const ACTOR_CONDITION_KINDS := [
	"stat", "state", "money", "item", "polarity", "skill", "knowledge",
]


static func location_actions(
	session: Object,
	include_blocked: bool = false
) -> Array[Dictionary]:
	var setup := _setup(session)
	if not bool(setup.get("ok", false)):
		return []
	var result: Array[Dictionary] = []
	var stamp: Dictionary = session.get("run_state").calendar.current_stamp()
	var location_id := _location_id(session)
	for npc: Dictionary in ScheduleResolver.present_npcs(setup["npcs"], stamp, location_id):
		var npc_id := String(npc.get("id", ""))
		var model := npc_model(session, npc_id, include_blocked)
		if not bool(model.get("ok", false)):
			continue
		result.append({
			"id": "npc_meeting_%s" % npc_id,
			"kind": "npc",
			"category_id": "talk",
			"category_icon_id": "action_talk",
			"title": "Поговорить — %s" % String(npc.get("display_name", "")),
			"description": String(npc.get("role_title", "")),
			"available": true,
			"reasons": [],
			"intent": {"type": "open_npc", "payload": {"npc_id": npc_id}},
			"confirmation_required": false,
			"interaction_count": Array(model.get("interactions", [])).size(),
		})
	return result


static func npc_model(
	session: Object,
	npc_id: String,
	include_blocked: bool = false
) -> Dictionary:
	var setup := _setup(session)
	if not bool(setup.get("ok", false)):
		return setup
	var npc := _find(setup["npcs"].get("npcs", []), npc_id)
	if npc.is_empty():
		return _failure("unknown_npc", "Персонаж не найден")
	var presence := ScheduleResolver.presence(
		setup["npcs"], npc_id, session.get("run_state").calendar.current_stamp(), _location_id(session)
	)
	if not bool(presence.get("present", false)):
		return _failure("npc_unavailable", String(presence.get("message", "Персонажа здесь нет")), {"presence": presence})
	var models: Array[Dictionary] = []
	for definition: Dictionary in InteractionCatalog.interactions_for_npc(setup["interactions"], npc_id):
		var evaluated := _preview_loaded(session, npc, definition, setup["npcs"])
		if bool(evaluated.get("available", false)) or include_blocked:
			models.append(_interaction_model(evaluated))
	var social: SocialState = session.get("social_state")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"npc_id": npc_id,
		"display_name": String(npc.get("display_name", "")),
		"role_title": String(npc.get("role_title", "")),
		"goal": String(npc.get("goal", "")),
		"speech_profile_id": String(npc.get("speech_profile_id", "")),
		"location_id": _location_id(session),
		"presence": presence,
		"relationship": social.relationship(npc_id),
		"interactions": models,
	}


static func preview(
	session: Object,
	npc_id: String,
	interaction_id: String
) -> Dictionary:
	var setup := _setup(session)
	if not bool(setup.get("ok", false)):
		return setup
	var npc := _find(setup["npcs"].get("npcs", []), npc_id)
	var definition := InteractionCatalog.find_interaction(setup["interactions"], interaction_id)
	if npc.is_empty():
		return _failure("unknown_npc", "Персонаж не найден")
	if definition.is_empty() or String(definition.get("npc_id", "")) != npc_id:
		return _failure("unknown_interaction", "Взаимодействие персонажа не найдено")
	var presence := ScheduleResolver.presence(
		setup["npcs"], npc_id, session.get("run_state").calendar.current_stamp(), _location_id(session)
	)
	if not bool(presence.get("present", false)):
		return _failure("npc_unavailable", String(presence.get("message", "Персонажа здесь нет")), {"presence": presence})
	return _preview_loaded(session, npc, definition, setup["npcs"])


static func _preview_loaded(
	session: Object,
	npc: Dictionary,
	definition: Dictionary,
	npc_catalog: Dictionary
) -> Dictionary:
	var context := _context(session, String(npc.get("id", "")), String(definition.get("id", "")), npc_catalog)
	if context.is_empty():
		return _failure("context_failed", "Не удалось подготовить контекст взаимодействия")
	var condition_result := _evaluate_conditions(
		session.get("run_state"), context, Array(definition.get("conditions", []))
	)
	var repeat := InteractionHistory.repeat_evaluation(session.get("run_state"), definition)
	var reasons: Array = Array(condition_result.get("reasons", [])).duplicate(true)
	if not bool(repeat.get("allowed", false)):
		reasons.append({
			"code": String(repeat.get("code", "repeat_blocked")),
			"message": String(repeat.get("message", "Взаимодействие пока нельзя повторить")),
			"kind": "repeat",
		})
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"npc_id": String(npc.get("id", "")),
		"interaction_id": String(definition.get("id", "")),
		"available": reasons.is_empty(),
		"reasons": reasons,
		"checks": Array(condition_result.get("checks", [])).duplicate(true),
		"repeat": repeat,
		"history": Dictionary(repeat.get("history", {})).duplicate(true),
		"definition": definition.duplicate(true),
	}


static func _evaluate_conditions(
	run_state: RunState,
	context: Dictionary,
	conditions: Array
) -> Dictionary:
	var checks: Array = []
	var reasons: Array = []
	for index: int in conditions.size():
		var raw: Variant = conditions[index]
		var check: Dictionary
		if not raw is Dictionary:
			check = {"passed": false, "code": "invalid_condition", "message": "Условие должно быть объектом"}
		elif String(raw.get("kind", "")) in ACTOR_CONDITION_KINDS:
			check = CheckResolverScript.evaluate(run_state, raw)
		else:
			check = EventConditions.evaluate(context, raw)
		check["index"] = index
		checks.append(check)
		if not bool(check.get("passed", false)):
			reasons.append(check.duplicate(true))
	return {"allowed": reasons.is_empty(), "checks": checks, "reasons": reasons}


static func _context(session: Object, npc_id: String, interaction_id: String, npc_catalog: Dictionary) -> Dictionary:
	var run_state: RunState = session.get("run_state")
	var social: SocialState = session.get("social_state")
	var relationships := social.relationships.duplicate(true)
	for raw: Variant in npc_catalog.get("npcs", []):
		if raw is Dictionary:
			var known_id := String(raw.get("id", ""))
			if not relationships.has(known_id):
				relationships[known_id] = SocialState.neutral_relationship()
	var world: WorldState = session.get("world_state")
	return EventContextScript.build(run_state, {
		"kind": "npc_interaction",
		"id": npc_id,
		"action_id": interaction_id,
		"object_id": npc_id,
	}, {
		"location_id": _location_id(session),
		"era_id": "veldara_1980",
		"weather_id": "dry",
		"world": WorldReadModelScript.rules_projection(world),
		"relationships": relationships,
		"npc_memories": social.memories,
		"commitments": social.commitments,
		"reputations": social.reputations,
	})


static func _interaction_model(preview_result: Dictionary) -> Dictionary:
	var definition: Dictionary = preview_result.get("definition", {})
	var history: Dictionary = preview_result.get("history", {})
	return {
		"id": String(definition.get("id", "")),
		"npc_id": String(definition.get("npc_id", "")),
		"title": String(definition.get("title", "")),
		"description": String(definition.get("description", "")),
		"duration_minutes": int(definition.get("duration_minutes", 0)),
		"available": bool(preview_result.get("available", false)),
		"reasons": Array(preview_result.get("reasons", [])).duplicate(true),
		"repeat_kind": String(Dictionary(definition.get("repeat_policy", {})).get("kind", "")),
		"first_meeting": int(history.get("occurrences", 0)) == 0,
		"outcome_preview": String(definition.get("outcome", "")),
	}


static func _setup(session: Object) -> Dictionary:
	if session == null or not _has_property(session, "run_state") or not _has_property(session, "world_state") or not _has_property(session, "social_state"):
		return _failure("invalid_session", "Сессия не поддерживает взаимодействия с NPC")
	if not session.get("run_state") is RunState or not session.get("world_state") is WorldState or not session.get("social_state") is SocialState:
		return _failure("invalid_session", "Состояние NPC-системы недоступно")
	var npcs := NpcCatalog.load_default()
	var interactions := InteractionCatalog.load_default()
	if not bool(npcs.get("ok", false)) or not bool(interactions.get("ok", false)):
		return _failure("catalog_failed", "Каталог взаимодействий с NPC недоступен")
	return {"ok": true, "npcs": npcs["catalog"], "interactions": interactions["catalog"]}


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		if _has_property(session, field):
			return String(session.get(field))
	return ""


static func _find(entries: Variant, identifier: String) -> Dictionary:
	for raw: Variant in Array(entries):
		if raw is Dictionary and String(raw.get("id", "")) == identifier:
			return Dictionary(raw).duplicate(true)
	return {}


static func _has_property(value: Object, name: String) -> bool:
	for raw: Variant in value.get_property_list():
		if raw is Dictionary and String(raw.get("name", "")) == name:
			return true
	return false


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(extra, true)
	return result
