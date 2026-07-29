class_name ObligationSessionCommand
extends RefCounted

## Taking a room, paying what is due, and what happens when the day passes and
## nothing is paid.
##
## The last of those is the point of the whole stage. Everything else the hero
## does he can simply stop doing; rent arrives on its day regardless, and the
## only choice he has by then is whether he has the money.

const HousingScript := preload("res://game/housing/housing_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")


## Rooms going here, with what stands in the way of each.
static func rooms_at(session: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null:
		return result
	var loaded := HousingScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var run_state: RunState = session.get("run_state")
	var obligations: ObligationState = session.get("obligation_state")
	for entry: Dictionary in HousingScript.at_location(Dictionary(loaded["catalog"]), String(session.get("location"))):
		var room_id := String(entry.get("id", ""))
		var obligation_id := HousingScript.rent_obligation_id(room_id)
		var reasons: Array[String] = []
		if obligations != null and obligations.has(obligation_id):
			if obligations.is_broken(obligation_id):
				reasons.append("Вас отсюда уже попросили")
			else:
				reasons.append("Вы здесь и так живёте")
		var upfront := int(entry.get("deposit_ard", 0)) + int(entry.get("rent_ard", 0))
		if run_state != null and run_state.money < upfront:
			reasons.append("Залог и первую плату вперёд не собрать")
		result.append({
			"id": room_id,
			"title": String(entry.get("title", "")),
			"description": String(entry.get("description", "")),
			"deposit_ard": int(entry.get("deposit_ard", 0)),
			"rent_ard": int(entry.get("rent_ard", 0)),
			"rent_every_days": int(entry.get("rent_every_days", 0)),
			"upfront_ard": upfront,
			"reasons": reasons,
		})
	return result


## Everything owed, in the words the hero would use, with how long he has.
static func ledger(session: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null:
		return result
	var obligations: ObligationState = session.get("obligation_state")
	var run_state: RunState = session.get("run_state")
	if obligations == null or run_state == null:
		return result
	var now := int(run_state.calendar.elapsed_minutes)
	for raw_id: Variant in obligations.records:
		var record: Dictionary = obligations.record_of(String(raw_id))
		var minutes_left := int(record.get("due_at_minute", 0)) - now
		@warning_ignore("integer_division")
		var days_left := minutes_left / GameRules.DEFAULT_MINUTES_PER_DAY
		result.append({
			"id": String(raw_id),
			"kind": String(record.get("kind", "")),
			"title": String(record.get("title", "")),
			"amount_ard": int(record.get("amount_ard", 0)),
			"broken": bool(record.get("broken", false)),
			"overdue": minutes_left <= 0,
			"days_left": maxi(days_left, 0),
			"missed": int(record.get("missed", 0)),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("days_left", 0)) < int(right.get("days_left", 0))
	)
	return result


static func take_room(target: Object, room_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var loaded := HousingScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("invalid_catalog", "Список комнат недоступен")
	var entry := HousingScript.find(Dictionary(loaded["catalog"]), room_id)
	if entry.is_empty():
		return _failure("unknown_room", "Такой комнаты нет")
	if String(entry.get("location_id", "")) != String(target.get("location")):
		return _failure("wrong_place", "Это не здесь")
	var obligations: ObligationState = target.get("obligation_state")
	var obligation_id := HousingScript.rent_obligation_id(room_id)
	if obligations != null and obligations.has(obligation_id):
		return _failure("already_taken", "Вы здесь и так живёте")
	var upfront := int(entry.get("deposit_ard", 0)) + int(entry.get("rent_ard", 0))
	if int(target.get("run_state").money) < upfront:
		return _failure("not_enough_money", "Залог и первую плату вперёд не собрать")
	var every := int(entry.get("rent_every_days", 0)) * GameRules.DEFAULT_MINUTES_PER_DAY
	var due := int(target.get("run_state").calendar.elapsed_minutes) + every
	return _commit(
		target,
		command_id,
		"housing_take_room",
		"Снята комната: %s" % String(entry.get("title", "")),
		[{"type": "change_money", "amount": -upfront, "reason": "Залог и плата вперёд"}],
		func(state: ObligationState) -> bool:
			return state.take_on(
				obligation_id,
				ObligationState.RENT,
				"Плата за жильё: %s" % String(entry.get("title", "")),
				int(entry.get("rent_ard", 0)),
				due,
				every,
				String(entry.get("landlord_npc_id", ""))
			)
	)


## Paying one thing that is owed. Nothing is paid automatically: the hero has to
## come and hand it over, which is what makes forgetting possible.
static func pay(target: Object, obligation_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var obligations: ObligationState = target.get("obligation_state")
	if obligations == null or not obligations.has(obligation_id):
		return _failure("unknown_obligation", "Такого долга нет")
	var record := obligations.record_of(obligation_id)
	if bool(record.get("broken", false)):
		return _failure("already_broken", "Это уже не вернуть")
	var amount := int(record.get("amount_ard", 0))
	if int(target.get("run_state").money) < amount:
		return _failure("not_enough_money", "Столько денег нет")
	return _commit(
		target,
		command_id,
		"obligation_pay",
		"Уплачено: %s" % String(record.get("title", "")),
		[{"type": "change_money", "amount": -amount, "reason": String(record.get("title", "Долг"))}],
		func(state: ObligationState) -> bool:
			return state.settle(obligation_id)
	)


## The day came. Whatever was not paid is missed, and the third miss ends the
## arrangement. Called when the hero confirms anything that moved the clock past
## a due date, so a debt cannot be outrun by never opening the ledger.
static func fall_due(target: Object, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var obligations: ObligationState = target.get("obligation_state")
	var run_state: RunState = target.get("run_state")
	if obligations == null or run_state == null:
		return _failure("no_ledger", "Список долгов недоступен")
	var overdue := obligations.due_by(int(run_state.calendar.elapsed_minutes))
	if overdue.is_empty():
		return {"ok": true, "code": "nothing_due", "error": "", "idempotent": false, "missed": []}
	var broken: Array[String] = []
	var result := _commit(
		target,
		command_id,
		"obligation_missed",
		"Просрочено: %d" % overdue.size(),
		[],
		func(state: ObligationState) -> bool:
			for obligation_id: String in overdue:
				if state.miss(obligation_id):
					broken.append(obligation_id)
			return true
	)
	if bool(result.get("ok", false)):
		result["missed"] = overdue
		result["broken"] = broken
	return result


static func _commit(
	target: Object,
	command_id: String,
	source_id: String,
	title: String,
	effects: Array,
	change: Callable
) -> Dictionary:
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить решение")
	var state: ObligationState = candidate.get("obligation_state")
	if state == null:
		return _failure("missing_ledger", "Список долгов недоступен")
	if not bool(change.call(state)):
		return _failure("rejected", "Изменение не принято")
	var validation := state.validate()
	if not bool(validation.get("ok", false)):
		return _failure("invalid_ledger", String(Array(validation.get("errors", ["Неверный список"]))[0]))
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": source_id,
		"title": title,
		"journal_message": title,
		"journal_payload": {},
		"conditions": [],
		"effects": effects,
	})
	if not bool(committed.get("ok", false)):
		return committed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила решение")
	return {"ok": true, "code": "ok", "error": "", "idempotent": false, "transaction": committed}


static func _guard(target: Object, command_id: String) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Решение должно иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	return {}


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
