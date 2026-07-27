class_name SessionCommandTransaction
extends RefCounted

## One atomic gateway for actor, social and objective-world effects.
##
## The live session is never touched until a complete cloned candidate passes
## validation. UI navigation and read-model construction must not call this.

const ActorTransaction := preload("res://core/rules/action_transaction.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")
const SocialMutationScript := preload("res://core/social/social_mutation.gd")

const WORLD_EFFECTS := [
	"set_world_fact",
	"change_world_metric",
	"advance_world_process",
	"schedule_world_mutation",
	"cancel_world_mutation",
	"replace_stock",
]
const SOCIAL_EFFECTS := [
	"change_relationship",
	"add_npc_memory",
	"change_reputation",
	"create_commitment",
	"resolve_commitment",
]


static func execute(
	target: Object,
	command: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var contract_error := _validate_target(target)
	if not contract_error.is_empty():
		return _failure("invalid_session_target", contract_error)
	var command_id := String(command.get("command_id", "")).strip_edges()
	if command_id.is_empty():
		return _failure("missing_command_id", "Команда должна иметь стабильный command_id")
	var ledger: Dictionary = target.get("applied_command_ids")
	if ledger.has(command_id):
		return {
			"ok": true,
			"code": "already_applied",
			"error": "",
			"idempotent": true,
			"command_id": command_id,
			"changes": [],
		}
	var candidate: Variant = target.call("clone")
	if candidate == null or not candidate is Object:
		return _failure("session_clone_failed", "Не удалось создать копию игровой сессии")
	var effects_value: Variant = command.get("effects", [])
	if not effects_value is Array:
		return _failure("invalid_effects", "Эффекты команды должны быть массивом")
	var split := _split_effects(effects_value)
	if not bool(split.get("ok", false)):
		return split

	var actor_action := command.duplicate(true)
	actor_action["id"] = String(command.get("source_id", command.get("id", command_id)))
	actor_action["effects"] = split["actor"]
	var actor_result: ActionResult = ActorTransaction.execute(
		candidate.get("run_state"),
		actor_action,
		context
	)
	if not actor_result.success:
		var actor_failure := actor_result.to_dict()
		actor_failure["ok"] = false
		actor_failure["error"] = actor_result.message
		return actor_failure

	var source_id := String(actor_action["id"])
	var at: Dictionary = candidate.get("run_state").calendar.current_stamp()
	var all_changes: Array = actor_result.changes.duplicate(true)
	if not Array(split["social"]).is_empty():
		var social_result := SocialMutationScript.apply(candidate.get("social_state"), {
			"schema_version": SocialMutationScript.SCHEMA_VERSION,
			"source_id": source_id,
			"at": at,
			"operations": split["social"],
		})
		if not bool(social_result.get("ok", false)):
			return _failure("social_effect_failed", String(social_result.get("error", "Социальный эффект не применился")), {"cause": social_result})
		all_changes.append_array(Array(social_result.get("changes", [])).duplicate(true))
	if not Array(split["world"]).is_empty():
		var world_result := WorldMutationScript.apply(
			candidate.get("world_state"),
			{
				"schema_version": WorldMutationScript.SCHEMA_VERSION,
				"source_id": source_id,
				"at": at,
				"operations": split["world"],
			},
			Dictionary(context.get("world_definitions", {}))
		)
		if not bool(world_result.get("ok", false)):
			return _failure("world_effect_failed", String(world_result.get("error", "Мировой эффект не применился")), {"cause": world_result})
		all_changes.append_array(Array(world_result.get("changes", [])).duplicate(true))
	var due_result := {"ok": true, "changes": [], "applied": 0}
	if _advanced_minutes(actor_result.changes) > 0:
		due_result = WorldMutationScript.apply_due(
			candidate.get("world_state"),
			at,
			Dictionary(context.get("world_definitions", {}))
		)
		if not bool(due_result.get("ok", false)):
			return _failure("due_world_effect_failed", String(due_result.get("error", "Отложенное изменение мира не применилось")), {"cause": due_result})
		all_changes.append_array(Array(due_result.get("changes", [])).duplicate(true))

	var candidate_ledger: Dictionary = candidate.get("applied_command_ids")
	candidate_ledger[command_id] = {
		"source_id": source_id,
		"applied_at": at.duplicate(true),
	}
	candidate.set("applied_command_ids", candidate_ledger)
	_append_combined_changes(candidate.get("run_state"), command_id, all_changes)
	var validation: Dictionary = candidate.call("validate")
	if not bool(validation.get("ok", false)):
		return _failure("session_validation_failed", "Команда создала недопустимую сессию", {"validation": validation})
	var committed: Variant = target.call("replace_from", candidate)
	if committed is bool and not bool(committed):
		return _failure("session_commit_failed", "Сессия отклонила атомарную фиксацию")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"command_id": command_id,
		"changes": all_changes,
		"actor_transaction": actor_result.to_dict(),
		"due_world_mutations": int(due_result.get("applied", 0)),
	}


static func _validate_target(target: Object) -> String:
	if target == null:
		return "Игровая сессия отсутствует"
	for method: String in ["clone", "replace_from", "validate"]:
		if not target.has_method(method):
			return "Сессия не реализует %s()" % method
	var properties: Dictionary = {}
	for property: Dictionary in target.get_property_list():
		properties[String(property.get("name", ""))] = true
	for property: String in ["run_state", "world_state", "social_state", "applied_command_ids"]:
		if not properties.has(property):
			return "Сессия не содержит %s" % property
	if not target.get("applied_command_ids") is Dictionary:
		return "applied_command_ids должен быть словарём"
	return ""


static func _split_effects(effects: Array) -> Dictionary:
	var actor: Array = []
	var social: Array = []
	var world: Array = []
	for index: int in effects.size():
		var raw_effect: Variant = effects[index]
		if not raw_effect is Dictionary:
			return _failure("invalid_effect", "Эффект %d должен быть объектом" % index)
		var effect: Dictionary = Dictionary(raw_effect).duplicate(true)
		var effect_type := String(effect.get("type", effect.get("kind", ""))).strip_edges().to_lower().replace("-", "_")
		if effect_type in WORLD_EFFECTS:
			world.append(effect)
		elif effect_type in SOCIAL_EFFECTS:
			social.append(effect)
		else:
			actor.append(effect)
	return {"ok": true, "actor": actor, "social": social, "world": world}


static func _append_combined_changes(
	run_state: RunState,
	command_id: String,
	changes: Array
) -> void:
	if run_state == null:
		return
	for index: int in range(run_state.journal.size() - 1, -1, -1):
		var raw_entry: Variant = run_state.journal[index]
		if not raw_entry is Dictionary or String(raw_entry.get("type", "")) != "action":
			continue
		var entry: Dictionary = Dictionary(raw_entry).duplicate(true)
		var payload: Dictionary = Dictionary(entry.get("payload", {})).duplicate(true)
		payload["session_command_id"] = command_id
		payload["session_changes"] = changes.duplicate(true)
		entry["payload"] = payload
		run_state.journal[index] = entry
		return


static func _advanced_minutes(changes: Array) -> int:
	var total := 0
	for raw_change: Variant in changes:
		if raw_change is Dictionary and String(raw_change.get("effect_type", "")) == "advance_time":
			total += maxi(int(raw_change.get("delta", 0)), 0)
	return total


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
