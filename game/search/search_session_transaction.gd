class_name SearchSessionTransaction
extends RefCounted

## Shared atomic boundary for search commands. A command always edits a full
## RunSession clone and publishes it only after session validation.


static func active_search(session: Object) -> Dictionary:
	if session == null:
		return {}
	var activity: Variant = (
		session.call("get_active_activity")
		if session.has_method("get_active_activity")
		else session.get("active_activity")
	)
	if not activity is Dictionary:
		return {}
	var normalized: Dictionary = activity
	if String(normalized.get("kind", "")) != "search":
		return {}
	if String(normalized.get("id", "")).is_empty():
		return {}
	if not normalized.get("snapshot", null) is Dictionary:
		return {}
	return normalized.duplicate(true)


static func require_active(session: Object) -> Dictionary:
	var activity := active_search(session)
	if activity.is_empty():
		return failure(
			"search_not_active",
			"Поисковая зона сейчас не открыта."
		)
	var snapshot: Dictionary = activity["snapshot"]
	if String(snapshot.get("template_id", "")) != String(activity.get("id", "")):
		return failure(
			"search_activity_mismatch",
			"Активная поисковая зона не совпадает со своим snapshot."
		)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"activity": activity,
		"snapshot": snapshot.duplicate(true),
	}


static func clone_session(session: Object) -> Dictionary:
	if session == null or not session.has_method("clone"):
		return failure("invalid_session", "Сессия не поддерживает атомарные команды.")
	var candidate: Variant = session.call("clone")
	if candidate == null or not candidate is Object:
		return failure("session_clone_failed", "Не удалось создать копию сессии.")
	return {"ok": true, "code": "ok", "error": "", "candidate": candidate}


static func replace_search_state(
	candidate: Object,
	activity: Dictionary,
	zone_states: Dictionary
) -> Dictionary:
	if candidate == null or not candidate.has_method("replace_search_state"):
		return failure(
			"search_state_not_supported",
			"Сессия не поддерживает состояние поисковой зоны."
		)
	var result: Variant = candidate.call(
		"replace_search_state",
		activity.duplicate(true),
		zone_states.duplicate(true)
	)
	if result is Dictionary:
		if not bool(result.get("ok", false)):
			return result.duplicate(true)
	elif result is bool and not bool(result):
		return failure("search_state_rejected", "Сессия отклонила состояние поиска.")
	return {"ok": true, "code": "ok", "error": ""}


static func commit(target: Object, candidate: Object) -> Dictionary:
	if target == null or candidate == null:
		return failure("invalid_session", "Сессия отсутствует.")
	var validation := _validation(candidate)
	if not bool(validation.get("ok", false)):
		return failure(
			"session_validation_failed",
			"Команда поиска создала некорректную сессию.",
			{"validation": validation}
		)
	if not target.has_method("replace_from"):
		return failure("session_commit_not_supported", "Сессия не поддерживает фиксацию.")
	var committed: Variant = target.call("replace_from", candidate)
	if committed is bool and not bool(committed):
		return failure("session_commit_failed", "Не удалось зафиксировать команду поиска.")
	var committed_validation := _validation(target)
	if not bool(committed_validation.get("ok", false)):
		return failure(
			"committed_session_invalid",
			"Зафиксированная сессия не прошла проверку.",
			{"validation": committed_validation}
		)
	return {"ok": true, "code": "ok", "error": ""}


static func validate_command_id(command_id: String) -> Dictionary:
	if command_id.strip_edges().is_empty():
		return failure(
			"missing_command_id",
			"Для изменяющей команды требуется непустой command_id."
		)
	return {"ok": true, "code": "ok", "error": ""}


static func was_applied(snapshot: Dictionary, command_id: String) -> bool:
	return command_id in Array(snapshot.get("applied_command_ids", []))


static func mark_applied(snapshot: Dictionary, command_id: String) -> Dictionary:
	var result := snapshot.duplicate(true)
	var ids: Array = Array(result.get("applied_command_ids", [])).duplicate()
	if command_id not in ids:
		ids.append(command_id)
	result["applied_command_ids"] = ids
	return result


static func duplicate_result(snapshot: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"code": "duplicate_command",
		"error": "",
		"idempotent": true,
		"snapshot": snapshot.duplicate(true),
	}


static func pending_encounter(snapshot: Dictionary) -> Dictionary:
	var value: Variant = snapshot.get("pending_encounter", {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


## Walking, picking loot up and leaving stay available while an encounter waits.
## Only decisions that spend time and raise risk are held back.
static func require_no_pending_encounter(snapshot: Dictionary) -> Dictionary:
	if pending_encounter(snapshot).is_empty():
		return {"ok": true, "code": "ok", "error": ""}
	return failure(
		"encounter_pending",
		"Сначала ответьте на то, что происходит рядом."
	)


static func zone_states(session: Object) -> Dictionary:
	var value: Variant = session.get("search_zone_states") if session != null else {}
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func none_activity() -> Dictionary:
	return {"kind": "none", "id": "", "snapshot": {}}


static func failure(
	code: String,
	message: String,
	details: Dictionary = {}
) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result


static func _validation(session: Object) -> Dictionary:
	if session == null or not session.has_method("validate"):
		return {"ok": false, "errors": ["session.validate() отсутствует"]}
	var result: Variant = session.call("validate")
	if result is Dictionary:
		return result
	if result is bool:
		return {"ok": bool(result), "errors": [] if bool(result) else ["validation failed"]}
	return {"ok": false, "errors": ["session.validate() вернул неизвестный результат"]}
