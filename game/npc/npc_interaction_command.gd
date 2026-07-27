class_name NpcInteractionCommand
extends RefCounted

## Rechecks and commits one player-confirmed NPC interaction through the shared
## actor/social/world/time transaction boundary.

const InteractionService := preload("res://game/npc/npc_interaction_service.gd")
const InteractionHistory := preload("res://game/npc/npc_interaction_history.gd")
const SessionTransaction := preload("res://game/session/session_command_transaction.gd")
const WorldCatalog := preload("res://game/content/catalogs/world_definition_catalog.gd")


static func execute(
	target: Object,
	npc_id: String,
	interaction_id: String,
	command_id: String
) -> Dictionary:
	if target == null or not _has_property(target, "applied_command_ids"):
		return _failure("invalid_session", "Сессия не поддерживает команды NPC")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Команда NPC должна иметь стабильный ID")
	var ledger: Variant = target.get("applied_command_ids")
	if not ledger is Dictionary:
		return _failure("invalid_session", "Журнал команд NPC недоступен")
	if ledger.has(command_id):
		return {
			"ok": true,
			"code": "already_applied",
			"error": "",
			"idempotent": true,
			"mutated": false,
			"npc_id": npc_id,
			"interaction_id": interaction_id,
		}
	var preview := InteractionService.preview(target, npc_id, interaction_id)
	if not bool(preview.get("ok", false)):
		return preview
	if not bool(preview.get("available", false)):
		return _failure(
			"interaction_blocked",
			"Это взаимодействие сейчас недоступно",
			{"blocked_reasons": Array(preview.get("reasons", [])).duplicate(true)}
		)
	var definition: Dictionary = preview.get("definition", {})
	var history: Dictionary = preview.get("history", {})
	var first_meeting := int(history.get("occurrences", 0)) == 0
	var effects: Array = Array(definition.get("effects", [])).duplicate(true)
	if first_meeting:
		effects.append_array(Array(definition.get("first_time_effects", [])).duplicate(true))
	var world_loaded := WorldCatalog.load_default()
	if not bool(world_loaded.get("ok", false)):
		return _failure("world_catalog_failed", "Каталог состояния мира недоступен")
	var run_state: RunState = target.get("run_state")
	var repeat_policy: Dictionary = definition.get("repeat_policy", {})
	var cooldown_ready_at := 0
	if String(repeat_policy.get("kind", "")) == "cooldown":
		cooldown_ready_at = (
			run_state.calendar.elapsed_minutes
			+ int(definition.get("duration_minutes", 0))
			+ int(repeat_policy.get("minutes", 0))
		)
	var transaction := SessionTransaction.execute(target, {
		"command_id": command_id,
		"source_id": interaction_id,
		"title": String(definition.get("title", interaction_id)),
		"journal_message": "%s — %s" % [npc_id, String(definition.get("title", interaction_id))],
		"journal_payload": {
			"domain": "npc_interaction",
			"npc_id": npc_id,
			"interaction_id": interaction_id,
			"civil_day_key": InteractionHistory.civil_day_key(run_state.calendar.current_stamp()),
			"cooldown_ready_at": cooldown_ready_at,
			"first_meeting": first_meeting,
		},
		"conditions": [],
		"effects": effects,
	}, {
		"world_definitions": Dictionary(world_loaded.get("catalog", {})).duplicate(true),
	})
	if not bool(transaction.get("ok", false)):
		return transaction
	var outcome := String(definition.get("outcome", ""))
	if not first_meeting and definition.has("repeat_outcome"):
		outcome = String(definition.get("repeat_outcome", outcome))
	var result := {
		"ok": true,
		"code": String(transaction.get("code", "ok")),
		"error": "",
		"idempotent": bool(transaction.get("idempotent", false)),
		"mutated": String(transaction.get("code", "ok")) != "already_applied",
		"npc_id": npc_id,
		"interaction_id": interaction_id,
		"outcome": outcome,
		"first_meeting": first_meeting,
		"transaction": transaction,
	}
	if _has_property(target, "survival_state") and target.get("survival_state") is SurvivalState:
		result["lifecycle"] = target.get("survival_state").to_dict()
	return result


static func _has_property(value: Object, name: String) -> bool:
	for raw: Variant in value.get_property_list():
		if raw is Dictionary and String(raw.get("name", "")) == name:
			return true
	return false


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error, "mutated": false}
	result.merge(extra, true)
	return result
