class_name SearchInteractionTransaction
extends RefCounted

const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const LootTransaction := preload("res://game/search/search_loot_transaction.gd")
const RiskResolver := preload("res://game/search/search_risk_resolver.gd")

const QUICK_SEARCH_RESOLVED_REQUIRED := 6


static func apply(
	session: Object,
	snapshot: Dictionary,
	object_id: String,
	approach_id: String,
	require_proximity: bool = true
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
	if (
		before_resolved < QUICK_SEARCH_RESOLVED_REQUIRED
		and before_resolved + 1 >= QUICK_SEARCH_RESOLVED_REQUIRED
		and run_state.get_skill_rank("search") < 1
	):
		effects.append({"type": "unlock_skill", "id": "search", "rank": 1})
	var transaction := ActionTransaction.execute(
		run_state,
		{
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
	if not transaction.success:
		return _failure(
			String(transaction.code),
			transaction.message,
			{"transaction": transaction.to_dict()}
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
		String(session.get("location")),
		int(costs["noise"]),
		int(costs["trespass"])
	)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": risk_result["snapshot"],
		"transaction": transaction.to_dict(),
		"ground_items": Array(loot_result.get("ground_items", [])).duplicate(true),
		"encounter": Dictionary(risk_result.get("encounter", {})).duplicate(true),
		"preview": preview,
	}


static func _failure(
	code: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
