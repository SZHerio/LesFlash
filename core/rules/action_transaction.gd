class_name ActionTransaction
extends RefCounted

## Atomic action pipeline.
##
## Expected RunState contract:
## - clone() -> RunState
## - validate() -> {ok: bool, errors: Array} (bool/Array are also accepted)
## - to_dict() -> Dictionary
## - replace_from(other) -> bool is preferred for an identity-preserving commit;
##   load_from_dict(Dictionary) -> bool or compatible public properties are
##   supported as fallbacks.
## - add_journal_entry(type, message, payload, id) -> bool is preferred.
##
## Conditions always run against the original state. Effects and the journal
## entry are written only to a clone. Therefore any blocked condition, invalid
## effect or validation error leaves the original RunState unchanged.


static func execute(
		run_state: Object,
		action: Dictionary,
		context: Dictionary = {}
	) -> ActionResult:
	if run_state == null:
		return ActionResult.failed(&"missing_state", "Состояние игры отсутствует")

	var raw_conditions: Variant = action.get("conditions", action.get("requirements", []))
	if not raw_conditions is Array:
		return ActionResult.failed(&"invalid_conditions", "Условия действия должны быть массивом")
	var conditions: Array = raw_conditions
	var checks := CheckResolver.evaluate_all(run_state, conditions, context)
	if not bool(checks["allowed"]):
		var reasons: Array[Dictionary] = []
		for reason: Variant in checks["reasons"]:
			if reason is Dictionary:
				reasons.append(reason)
		return ActionResult.blocked(reasons)

	var raw_effects: Variant = action.get("effects", [])
	if not raw_effects is Array:
		return ActionResult.failed(&"invalid_effects", "Эффекты действия должны быть массивом")
	var effects: Array = raw_effects
	if not run_state.has_method("clone"):
		return ActionResult.failed(&"clone_not_supported", "RunState не реализует clone()")
	if not run_state.has_method("to_dict"):
		return ActionResult.failed(&"serialization_not_supported", "RunState не реализует to_dict()")

	var original_snapshot: Variant = run_state.call("to_dict")
	if not original_snapshot is Dictionary:
		return ActionResult.failed(&"serialization_failed", "to_dict() должен вернуть словарь")
	var working_state: Variant = run_state.call("clone")
	if working_state == null or not (working_state is Object):
		return ActionResult.failed(&"clone_failed", "Не удалось клонировать RunState")

	var action_context := context.duplicate(true)
	var action_id := String(action.get("id", action.get("action_id", context.get("action_id", "action"))))
	var option_id := String(action.get("option_id", context.get("option_id", "")))
	action_context["action_id"] = action_id
	action_context["option_id"] = option_id
	var time_before := RuleStateAccess.time_snapshot(run_state)
	var applied := EffectApplier.apply_all(working_state, effects, action_context)
	if not bool(applied["ok"]):
		return ActionResult.failed(
			StringName(applied.get("code", "effect_failed")),
			String(applied.get("message", "Не удалось применить эффект")),
			int(applied.get("failed_index", -1)),
			_typed_dictionary_array(applied.get("changes", []))
		)

	var validation_errors := RuleStateAccess.validation_errors(working_state)
	if not validation_errors.is_empty():
		return ActionResult.failed(
			&"state_validation_failed",
			"Пакет эффектов создал недопустимое состояние: %s" % "; ".join(PackedStringArray(validation_errors)),
			-1,
			_typed_dictionary_array(applied["changes"])
		)

	var changes := _typed_dictionary_array(applied["changes"])
	var time_after := RuleStateAccess.time_snapshot(working_state)
	var journal_result := _append_action_journal(
		working_state,
		action,
		action_context,
		time_before,
		time_after,
		changes
	)
	if not bool(journal_result["ok"]):
		return ActionResult.failed(
			StringName(journal_result.get("code", "journal_failed")),
			String(journal_result.get("message", "Не удалось записать журнал")),
			-1,
			changes
		)

	validation_errors = RuleStateAccess.validation_errors(working_state)
	if not validation_errors.is_empty():
		return ActionResult.failed(
			&"journal_validation_failed",
			"Запись журнала создала недопустимое состояние: %s" % "; ".join(PackedStringArray(validation_errors)),
			-1,
			changes
		)

	var commit := _commit(run_state, working_state, original_snapshot)
	if not bool(commit["ok"]):
		return ActionResult.failed(
			StringName(commit.get("code", "commit_failed")),
			String(commit.get("message", "Не удалось зафиксировать действие")),
			-1,
			changes
		)
	return ActionResult.succeeded(changes, journal_result["entry"])


static func execute_parts(
		run_state: Object,
		action_id: StringName,
		option_id: StringName,
		conditions: Array,
		effects: Array,
		context: Dictionary = {}
	) -> ActionResult:
	return execute(run_state, {
		"id": String(action_id),
		"option_id": String(option_id),
		"conditions": conditions.duplicate(true),
		"effects": effects.duplicate(true),
	}, context)


static func _append_action_journal(
		working_state: Object,
		action: Dictionary,
		context: Dictionary,
		time_before: Dictionary,
		time_after: Dictionary,
		changes: Array[Dictionary]
	) -> Dictionary:
	var action_id := String(context.get("action_id", "action"))
	var option_id := String(context.get("option_id", ""))
	var title := String(action.get("title", action.get("label", action_id)))
	var option_title := String(action.get("option_title", action.get("option_label", option_id)))
	var message := String(action.get("journal_message", ""))
	if message.is_empty():
		if not option_title.is_empty():
			message = "%s — %s" % [title, option_title]
		else:
			message = title

	var total_minutes := 0
	for change: Dictionary in changes:
		if String(change.get("effect_type", "")) == "advance_time":
			total_minutes += int(change.get("delta", 0))
	var payload := {
		"action_id": action_id,
		"option_id": option_id,
		"time": {
			"before": time_before.duplicate(true),
			"after": time_after.duplicate(true),
			"advanced_minutes": total_minutes,
		},
		"changes": changes.duplicate(true),
	}
	var extra_payload: Variant = action.get("journal_payload", {})
	if extra_payload is Dictionary:
		for key: Variant in extra_payload:
			if key not in payload:
				payload[key] = _duplicate_variant(extra_payload[key])

	var journal_info := _find_journal(working_state)
	var journal_size := int(journal_info.get("size", 0))
	var entry_id := String(action.get("journal_id", ""))
	if entry_id.is_empty():
		entry_id = _generated_journal_id(action_id, option_id, time_after, journal_size)

	if working_state.has_method("add_journal_entry"):
		var added: Variant = working_state.call(
			"add_journal_entry",
			"action",
			message,
			payload,
			entry_id
		)
		if added is bool and not added:
			return {
				"ok": false,
				"code": "journal_append_failed",
				"message": "RunState отклонил запись журнала",
				"entry": {},
			}
		var updated_info := _find_journal(working_state)
		var updated_journal: Variant = updated_info.get("value", [])
		if updated_journal is Array and not updated_journal.is_empty():
			var entry: Variant = updated_journal.back()
			if entry is Dictionary:
				return {"ok": true, "code": "ok", "message": "", "entry": entry.duplicate(true)}
		return {
			"ok": false,
			"code": "journal_entry_missing",
			"message": "RunState сообщил об успехе, но запись не появилась в журнале",
			"entry": {},
		}

	if not bool(journal_info.get("found", false)):
		return {
			"ok": false,
			"code": "journal_not_supported",
			"message": "RunState не содержит журнал",
			"entry": {},
		}
	var fallback_entry := {
		"sequence": journal_size + 1,
		"id": entry_id,
		"at": time_after.duplicate(true),
		"type": "action",
		"message": message,
		"payload": payload,
	}
	var journal: Array = journal_info["value"]
	journal.append(fallback_entry)
	working_state.set(StringName(journal_info["name"]), journal)
	return {"ok": true, "code": "ok", "message": "", "entry": fallback_entry.duplicate(true)}


static func _find_journal(run_state: Object) -> Dictionary:
	for candidate: String in RuleStateAccess.JOURNAL_CONTAINERS:
		var property_name := StringName(candidate)
		if not RuleStateAccess.has_property(run_state, property_name):
			continue
		var value: Variant = run_state.get(property_name)
		if value is Array:
			return {
				"found": true,
				"name": candidate,
				"value": value,
				"size": value.size(),
			}
	return {"found": false, "name": "", "value": [], "size": 0}


static func _commit(
		target: Object,
		working_state: Object,
		original_snapshot: Dictionary
	) -> Dictionary:
	var committed := false
	if target.has_method("replace_from"):
		var replace_result: Variant = target.call("replace_from", working_state)
		committed = not (replace_result is bool) or bool(replace_result)
	elif target.has_method("load_from_dict") and working_state.has_method("to_dict"):
		var serialized: Variant = working_state.call("to_dict")
		if serialized is Dictionary:
			var load_result: Variant = target.call("load_from_dict", serialized)
			committed = not (load_result is bool) or bool(load_result)
	else:
		committed = _copy_public_properties(target, working_state)

	if not committed:
		_restore_snapshot(target, original_snapshot)
		return {
			"ok": false,
			"code": "commit_failed",
			"message": "RunState отклонил фиксацию транзакции",
		}
	var validation_errors := RuleStateAccess.validation_errors(target)
	if not validation_errors.is_empty():
		_restore_snapshot(target, original_snapshot)
		return {
			"ok": false,
			"code": "committed_state_invalid",
			"message": "Зафиксированное состояние не прошло проверку: %s" % "; ".join(PackedStringArray(validation_errors)),
		}
	if target.has_method("to_dict") and working_state.has_method("to_dict"):
		var target_data: Variant = target.call("to_dict")
		var working_data: Variant = working_state.call("to_dict")
		if target_data is Dictionary and working_data is Dictionary and target_data != working_data:
			_restore_snapshot(target, original_snapshot)
			return {
				"ok": false,
				"code": "commit_mismatch",
				"message": "RunState после фиксации отличается от проверенной копии",
			}
	return {"ok": true, "code": "ok", "message": ""}


static func _restore_snapshot(target: Object, snapshot: Dictionary) -> bool:
	if target.has_method("load_from_dict"):
		var restored: Variant = target.call("load_from_dict", snapshot)
		return not (restored is bool) or bool(restored)
	return false


static func _copy_public_properties(target: Object, source: Object) -> bool:
	# Compatibility fallback. Production RunState should expose replace_from(),
	# because it can guarantee an atomic identity-preserving commit itself.
	var copied_any := false
	for property: Dictionary in source.get_property_list():
		var property_name := StringName(property.get("name", ""))
		if property_name == &"script" or String(property_name).begins_with("_"):
			continue
		if not RuleStateAccess.has_property(target, property_name):
			continue
		var value: Variant = source.get(property_name)
		target.set(property_name, _clone_variant(value))
		copied_any = true
	return copied_any


static func _clone_variant(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	if value is Object and value != null and value.has_method("clone"):
		return value.call("clone")
	return value


static func _duplicate_variant(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _typed_dictionary_array(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Array:
		for item: Variant in raw:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result


static func _generated_journal_id(
		action_id: String,
		option_id: String,
		time_after: Dictionary,
		journal_size: int
	) -> String:
	return "action:%s:%s:%s:%s" % [
		action_id,
		option_id,
		int(time_after.get("elapsed_minutes", 0)),
		journal_size,
	]
