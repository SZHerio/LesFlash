class_name QualificationSessionCommand
extends RefCounted

## Obtaining a paper: one confirmed decision that costs time and a fee and
## leaves the hero holding something he did not hold before.
##
## Atomic like every other command — the queue, the fee and the document commit
## together, so a run interrupted at the counter never ends up paid but
## unregistered.

const Catalog := preload("res://game/content/catalogs/qualification_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")


static func available(session: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null:
		return result
	var loaded := Catalog.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var run_state: RunState = session.get("run_state")
	var location_id := String(session.get("location"))
	for raw_entry: Variant in Array(Dictionary(loaded["catalog"]).get("qualifications", [])):
		var entry: Dictionary = raw_entry
		if String(entry.get("location_id", "")) != location_id:
			continue
		var qualification_id := String(entry.get("id", ""))
		if run_state.holds_qualification(qualification_id):
			continue
		result.append({
			"id": qualification_id,
			"title": String(entry.get("title", "")),
			"description": String(entry.get("description", "")),
			"minutes": int(entry.get("duration_minutes", 0)),
			"fee_ard": int(entry.get("fee_ard", 0)),
			"reasons": Catalog.blockers(entry, run_state, run_state.qualifications),
		})
	return result


static func obtain(target: Object, qualification_id: String, command_id: String) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Обращение должно иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var loaded := Catalog.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("invalid_catalog", "Каталог квалификаций недоступен")
	var entry := Catalog.find(Dictionary(loaded["catalog"]), qualification_id)
	if entry.is_empty():
		return _failure("unknown_qualification", "Такой бумаги здесь не выдают")
	var run_state: RunState = target.get("run_state")
	if String(entry.get("location_id", "")) != String(target.get("location")):
		return _failure("wrong_counter", "За этим обращаются в другое место")
	if run_state.holds_qualification(qualification_id):
		return _failure("already_held", "Эта бумага у вас уже есть")
	var blockers := Catalog.blockers(entry, run_state, run_state.qualifications)
	if not blockers.is_empty():
		return _failure("not_eligible", String(blockers[0]))

	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить обращение")
	if not candidate.get("run_state").grant_qualification(qualification_id):
		return _failure("grant_failed", "Бумага не была выдана")
	var effects: Array = [{
		"type": "advance_time",
		"minutes": int(entry.get("duration_minutes", 0)),
		"reason": "Очередь и оформление",
	}]
	var fee := int(entry.get("fee_ard", 0))
	if fee > 0:
		effects.append({"type": "change_money", "amount": -fee, "reason": "Пошлина"})
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "qualification_%s" % qualification_id,
		"title": String(entry.get("title", "")),
		"journal_message": "Получена бумага: %s" % String(entry.get("title", "")),
		"journal_payload": {"qualification_id": qualification_id, "fee_ard": fee},
		"conditions": [],
		"effects": effects,
	})
	if not bool(committed.get("ok", false)):
		return committed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила обращение")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"qualification_id": qualification_id,
		"transaction": committed,
	}


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
