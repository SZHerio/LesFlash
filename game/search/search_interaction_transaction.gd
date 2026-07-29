class_name SearchInteractionTransaction
extends RefCounted

const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const SkillCatalogScript := preload("res://game/skills/skill_catalog.gd")
const LootTransaction := preload("res://game/search/search_loot_transaction.gd")
const RiskResolver := preload("res://game/search/search_risk_resolver.gd")
const SessionCommandTransaction := preload(
	"res://game/session/session_command_transaction.gd"
)

const QUICK_SEARCH_RESOLVED_REQUIRED := 6


static func apply(
	session: Object,
	snapshot: Dictionary,
	object_id: String,
	approach_id: String,
	require_proximity: bool = true,
	command_id: String = ""
) -> Dictionary:
	var run_state: RunState = session.get("run_state")
	var preview := InteractionResolver.preview(
		run_state,
		snapshot,
		object_id,
		approach_id,
		require_proximity
	)
	if not bool(preview.get("ok", false)):
		return preview
	if not bool(preview.get("allowed", false)):
		return _failure(
			"interaction_blocked",
			"Этот способ сейчас недоступен.",
			{"blocked_reasons": Array(preview.get("blocked_reasons", [])).duplicate(true)}
		)
	var object: Dictionary = preview["object"]
	var approach: Dictionary = preview["approach"]
	var costs: Dictionary = preview["costs"]
	var before_resolved := InteractionResolver.exhausted_count(snapshot)
	var effects: Array = [
		{
			"type": "advance_time",
			"minutes": int(costs["minutes"]),
			"reason": "Поиск: %s" % String(approach.get("title", approach_id)),
		},
	]
	if int(costs["energy"]) > 0:
		effects.append({
			"type": "change_state",
			"id": "energy",
			"delta": -int(costs["energy"]),
		})
	# This used to hand the hero search rank 1 outright once he had opened enough
	# things. That was the only place in the game where a rank was granted rather
	# than earned, and it contradicted the rule everything else follows: a rank
	# comes from having done several *different* things with the skill. Now the
	# approach teaches whatever the skill catalog says it teaches, and rank 1
	# arrives when three different approaches have been worked — which the quick
	# sweep still gates on, only honestly.
	# Как он это сделал — попросил или пролез. Ось была написана в зонах поиска с
	# самого начала и до сих пор ничего не копила.
	var manner := _manner_of(approach_id)
	if not manner.is_empty():
		effects.append({"type": "standing", "id": manner, "weight": 1})
	var taught := SkillCatalogScript.skill_taught_by(
		_skill_catalog(),
		"%s:%s" % [object_id, approach_id]
	)
	if not taught.is_empty():
		effects.append({
			"type": "practice_skill",
			"id": taught,
			"source_id": "%s:%s" % [object_id, approach_id],
		})
	var session_command_id := command_id.strip_edges()
	if session_command_id.is_empty():
		session_command_id = _derived_command_id(
			snapshot,
			object_id,
			approach_id
		)
	var transaction := SessionCommandTransaction.execute(
		session,
		{
			"command_id": session_command_id,
			"source_id": "search:%s:%s" % [object_id, approach_id],
			"id": "search:%s:%s" % [object_id, approach_id],
			"title": String(approach.get("title", approach_id)),
			"conditions": Array(preview.get("conditions", [])).duplicate(true),
			"effects": effects,
			"journal_message": "Поиск — %s" % String(
				approach.get("title", approach_id)
			),
			"journal_payload": {
				"search_zone_id": String(snapshot.get("template_id", "")),
				"search_object_id": object_id,
				"search_approach_id": approach_id,
				"resolved_loot": Array(object.get("contents", [])).duplicate(true),
			},
		},
		{
			"source": "search",
			"object_id": object_id,
			"action_id": approach_id,
		}
	)
	if not bool(transaction.get("ok", false)):
		return _failure(
			String(transaction.get("code", "search_transaction_failed")),
			String(transaction.get("error", transaction.get("message", "Поиск не выполнен."))),
			{"transaction": _actor_transaction(transaction)}
		)
	# SessionCommandTransaction publishes a cloned aggregate. Never retain the
	# pre-commit RunState reference: a valid session implementation may replace
	# that object instead of mutating it in place.
	run_state = session.get("run_state")
	if run_state == null:
		return _failure(
			"missing_run_state_after_commit",
			"После решения поиска состояние героя недоступно."
		)
	object["state"] = "exhausted"
	object["revealed"] = true
	object["interacted"] = true
	var loot_result := LootTransaction.materialize_object(
		run_state,
		snapshot,
		object,
		String(snapshot.get("template_id", "search"))
	)
	if not bool(loot_result.get("ok", false)):
		return loot_result
	object = loot_result["object"]
	var updated := InteractionResolver.replace_object(
		loot_result["snapshot"],
		object
	)
	var risk_result := RiskResolver.apply(
		session,
		updated,
		{"action_id": approach_id, "object_id": object_id},
		_location_id(session),
		int(costs["noise"]),
		int(costs["trespass"])
	)
	if not bool(risk_result.get("ok", false)):
		return risk_result
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": risk_result["snapshot"],
		"transaction": _actor_transaction(transaction),
		"ground_items": Array(loot_result.get("ground_items", [])).duplicate(true),
		"encounter": Dictionary(risk_result.get("encounter", {})).duplicate(true),
		"preview": preview,
	}


static func _derived_command_id(
	snapshot: Dictionary,
	object_id: String,
	approach_id: String
) -> String:
	return "search_interaction:%s:%d:%s:%s" % [
		String(snapshot.get("template_id", "zone")),
		int(snapshot.get("visit_index", 1)),
		object_id,
		approach_id,
	]


static func _actor_transaction(transaction: Dictionary) -> Dictionary:
	var actor: Variant = transaction.get("actor_transaction", transaction)
	return Dictionary(actor).duplicate(true) if actor is Dictionary else {}


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		for raw_property: Variant in session.get_property_list():
			if raw_property is Dictionary and String(raw_property.get("name", "")) == field:
				return String(session.get(field))
	return ""


static func _failure(
	code: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result


## The catalog is a static file; reading it once per interaction is cheap enough,
## and holding it would mean a stale copy after a content reload.
static func _skill_catalog() -> Dictionary:
	var loaded := SkillCatalogScript.load_default()
	return Dictionary(loaded.get("catalog", {})) if bool(loaded.get("ok", false)) else {}


## По названию подхода видно, как человек себя повёл. Спросил разрешения,
## разговорился, подождал — надёжный. Отжал, пролез, взял без спроса — опасный.
## Остальное не говорит о нём ничего.
static func _manner_of(approach_id: String) -> String:
	const RELIABLE := ["ask_permission", "offer_help", "talk_your_way_in", "share_a_smoke",
		"open_safely", "work_quietly", "study_lock", "read_the_ground"]
	const FEARED := ["force_hinge", "force_the_latch", "slip_through", "find_blind_spot",
		"pick_it_open", "pull_boards", "lift_grate"]
	if approach_id in RELIABLE:
		return "reliable"
	if approach_id in FEARED:
		return "feared"
	return ""
