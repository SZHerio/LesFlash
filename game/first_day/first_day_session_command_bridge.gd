class_name FirstDaySessionCommandBridge
extends RefCounted

## Compatibility bridge that lets the legacy first-day aggregate participate in
## the shared M3F session transaction without making it own the new gateway.

const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const WorldDefinitionCatalogScript := preload("res://game/content/catalogs/world_definition_catalog.gd")


static func execute(
	target: Object,
	action: Dictionary,
	context: Dictionary,
	completes_day: bool,
	deadline_minutes: int
) -> ActionResult:
	if target.call("is_search_active"):
		return ActionResult.failed(
			&"search_active",
			"Сначала завершите или покиньте текущий поиск"
		)
	var candidate: Variant = target.call("clone")
	if candidate == null:
		return ActionResult.failed(
			&"clone_failed",
			"Не удалось подготовить безопасную копию сессии"
		)
	var world_catalog := WorldDefinitionCatalogScript.load_default()
	if not bool(world_catalog.get("ok", false)):
		return ActionResult.failed(
			&"world_catalog_failed",
			"Каталог состояния мира недоступен"
		)
	var run_state: RunState = target.get("run_state")
	var command := action.duplicate(true)
	command["command_id"] = "legacy:%s:%s:%d:%d" % [
		String(action.get("id", "action")),
		String(action.get("option_id", "")),
		run_state.calendar.elapsed_minutes,
		int(target.get("flow_revision")),
	]
	command["source_id"] = String(action.get("id", command["command_id"]))
	command["effects"] = _time_effect_first(Array(action.get("effects", [])).duplicate(true))
	var session_context := context.duplicate(true)
	session_context["world_definitions"] = Dictionary(
		world_catalog.get("catalog", {})
	).duplicate(true)
	var transaction := SessionTransactionScript.execute(
		candidate,
		command,
		session_context
	)
	if not bool(transaction.get("ok", false)):
		return _transaction_failure(transaction)
	if completes_day and int(candidate.run_state.calendar.elapsed_minutes) != deadline_minutes:
		return ActionResult.failed(
			&"first_day_deadline",
			"Старый сценарий первого дня должен завершаться ровно на его границе"
		)
	var due_result: Dictionary = target.call(
		"_resolve_due_consequences",
		candidate.run_state,
		context
	)
	if not bool(due_result.get("ok", false)):
		return ActionResult.failed(
			&"deferred_resolution_failed",
			String(due_result.get("message", "Не удалось применить отложенное последствие")),
			int(due_result.get("failed_effect_index", -1)),
			_typed_dictionary_array(due_result.get("changes", []))
		)
	if not bool(target.call("replace_from", candidate)):
		return ActionResult.failed(
			&"commit_failed",
			"Не удалось зафиксировать действие и его последствия"
		)
	var combined_changes: Array[Dictionary] = []
	combined_changes.append_array(
		_typed_dictionary_array(transaction.get("changes", []))
	)
	combined_changes.append_array(
		_typed_dictionary_array(due_result.get("changes", []))
	)
	var actor_transaction: Dictionary = Dictionary(
		transaction.get("actor_transaction", {})
	)
	return ActionResult.succeeded(
		combined_changes,
		Dictionary(actor_transaction.get("journal_entry", {})).duplicate(true)
	)


static func _transaction_failure(transaction: Dictionary) -> ActionResult:
	var code := String(transaction.get("code", "transaction_failed"))
	if code == "blocked":
		return ActionResult.blocked(
			_typed_dictionary_array(transaction.get("blocked_reasons", []))
		)
	return ActionResult.failed(
		StringName(code),
		String(transaction.get("error", transaction.get("message", "Действие не выполнено"))),
		int(transaction.get("failed_effect_index", -1)),
		_typed_dictionary_array(transaction.get("changes", []))
	)


static func _time_effect_first(effects: Array) -> Array:
	var timed: Array = []
	var others: Array = []
	for raw_effect: Variant in effects:
		if (
			raw_effect is Dictionary
			and String(
				raw_effect.get("type", raw_effect.get("kind", ""))
			).strip_edges().to_lower().replace("-", "_") == "advance_time"
		):
			timed.append(Dictionary(raw_effect).duplicate(true))
		else:
			others.append(
				raw_effect.duplicate(true)
				if raw_effect is Dictionary or raw_effect is Array
				else raw_effect
			)
	timed.append_array(others)
	return timed


static func _typed_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append(Dictionary(entry).duplicate(true))
	return result
