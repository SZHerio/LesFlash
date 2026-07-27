class_name SearchCommandService
extends RefCounted

const SessionTransaction := preload(
	"res://game/search/search_session_transaction.gd"
)
const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const InteractionTransaction := preload(
	"res://game/search/search_interaction_transaction.gd"
)
const LootTransaction := preload("res://game/search/search_loot_transaction.gd")
const QuickSearch := preload("res://game/search/search_quick_search.gd")


static func preview_interaction(
	session: Object,
	object_id: String,
	approach_id: String
) -> Dictionary:
	var active_result := SessionTransaction.require_active(session)
	if not bool(active_result.get("ok", false)):
		return active_result
	return InteractionResolver.preview(
		session.get("run_state"),
		active_result["snapshot"],
		object_id,
		approach_id,
		true
	)


static func confirm_interaction(
	session: Object,
	object_id: String,
	approach_id: String,
	command_id: String
) -> Dictionary:
	var prepared := prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var encounter_guard := SessionTransaction.require_no_pending_encounter(
		prepared["snapshot"]
	)
	if not bool(encounter_guard.get("ok", false)):
		return encounter_guard
	var applied := InteractionTransaction.apply(
		prepared["candidate"],
		prepared["snapshot"],
		object_id,
		approach_id,
		true,
		command_id
	)
	if not bool(applied.get("ok", false)):
		return applied
	return commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(applied["snapshot"], command_id),
		_result_details(applied)
	)


static func pick_up(
	session: Object,
	stack_id: String,
	target_container_id: String,
	command_id: String
) -> Dictionary:
	var prepared := prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var picked := LootTransaction.pick_up(
		prepared["candidate"].get("run_state"),
		prepared["snapshot"],
		stack_id,
		target_container_id
	)
	if not bool(picked.get("ok", false)):
		return picked
	return commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(picked["snapshot"], command_id),
		_result_details(picked)
	)


static func replace(
	session: Object,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String,
	command_id: String
) -> Dictionary:
	var prepared := prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var replaced := LootTransaction.replace(
		prepared["candidate"].get("run_state"),
		prepared["snapshot"],
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	if not bool(replaced.get("ok", false)):
		return replaced
	return commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(replaced["snapshot"], command_id),
		_result_details(replaced)
	)


static func quick_search(session: Object, command_id: String) -> Dictionary:
	var prepared := prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var encounter_guard := SessionTransaction.require_no_pending_encounter(
		prepared["snapshot"]
	)
	if not bool(encounter_guard.get("ok", false)):
		return encounter_guard
	var searched := QuickSearch.execute(
		prepared["candidate"],
		prepared["snapshot"]
	)
	if not bool(searched.get("ok", false)):
		return searched
	return commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(searched["snapshot"], command_id),
		_result_details(searched)
	)


static func prepare_mutation(
	session: Object,
	command_id: String
) -> Dictionary:
	var command_check := SessionTransaction.validate_command_id(command_id)
	if not bool(command_check.get("ok", false)):
		return command_check
	var active_result := SessionTransaction.require_active(session)
	if not bool(active_result.get("ok", false)):
		return active_result
	var snapshot: Dictionary = active_result["snapshot"]
	if SessionTransaction.was_applied(snapshot, command_id):
		var duplicate := SessionTransaction.duplicate_result(snapshot)
		duplicate["duplicate"] = true
		return duplicate
	var clone_result := SessionTransaction.clone_session(session)
	if not bool(clone_result.get("ok", false)):
		return clone_result
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"duplicate": false,
		"candidate": clone_result["candidate"],
		"snapshot": snapshot.duplicate(true),
	}


static func commit_active(
	target: Object,
	candidate: Object,
	snapshot: Dictionary,
	details: Dictionary = {}
) -> Dictionary:
	var activity := SessionTransaction.active_search(candidate)
	if activity.is_empty():
		return SessionTransaction.failure(
			"search_not_active",
			"Поисковая зона закрылась до фиксации команды."
		)
	activity["snapshot"] = snapshot.duplicate(true)
	var zones := SessionTransaction.zone_states(candidate)
	zones[String(activity.get("id", ""))] = snapshot.duplicate(true)
	var state_result := SessionTransaction.replace_search_state(
		candidate,
		activity,
		zones
	)
	if not bool(state_result.get("ok", false)):
		return state_result
	var commit := SessionTransaction.commit(target, candidate)
	if not bool(commit.get("ok", false)):
		return commit
	details["snapshot"] = snapshot.duplicate(true)
	return _success(details)


static func _result_details(result: Dictionary) -> Dictionary:
	var details := result.duplicate(true)
	details.erase("ok")
	details.erase("code")
	details.erase("error")
	details.erase("snapshot")
	return details


static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": "", "idempotent": false}
	result.merge(details, true)
	return result
