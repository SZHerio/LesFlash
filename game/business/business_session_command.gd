class_name BusinessSessionCommand
extends RefCounted

## Buying a place, keeping it supplied, and settling up with it.
##
## Everything here is atomic in the ordinary way. The one thing worth noticing
## is that settling is not a reward the player collects — it is a reckoning. The
## bench has been running, or standing idle, since the last time he looked, and
## the number can be negative. A man who hired two hands and went away for a
## fortnight owes wages for fourteen days of nothing.

const CatalogScript := preload("res://game/business/business_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")


## What can be bought where the hero is standing, and what stands in the way.
static func offers_at(session: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null:
		return result
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var business: BusinessState = session.get("business_state")
	var run_state: RunState = session.get("run_state")
	for entry: Dictionary in CatalogScript.at_location(Dictionary(loaded["catalog"]), String(session.get("location"))):
		var reasons: Array[String] = []
		if business != null and business.owns_anything():
			reasons.append("У вас уже есть своё место")
		if run_state != null and run_state.money < int(entry.get("price_ard", 0)):
			reasons.append("Столько денег нет")
		result.append({
			"id": String(entry.get("id", "")),
			"title": String(entry.get("title", "")),
			"description": String(entry.get("description", "")),
			"price_ard": int(entry.get("price_ard", 0)),
			"reasons": reasons,
		})
	return result


static func open(target: Object, business_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var entry := _entry(business_id)
	if entry.is_empty():
		return _failure("unknown_business", "Такого места нет")
	if String(entry.get("location_id", "")) != String(target.get("location")):
		return _failure("wrong_place", "Это место не здесь")
	var business: BusinessState = target.get("business_state")
	if business != null and business.owns_anything():
		return _failure("already_owns", "У вас уже есть своё место")
	var price := int(entry.get("price_ard", 0))
	if int(target.get("run_state").money) < price:
		return _failure("not_enough_money", "Столько денег нет")
	return _commit(
		target,
		command_id,
		"business_open",
		"Своё место: %s" % String(entry.get("title", "")),
		[{"type": "change_money", "amount": -price, "reason": "Покупка места"}],
		func(state: BusinessState, elapsed: int) -> bool:
			return state.open(business_id, elapsed)
	)


## Materials, bought by the unit. Nothing is made without them, and an idle
## bench with people on it is the fastest way to lose money in this game.
static func restock(target: Object, units: int, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var business: BusinessState = target.get("business_state")
	if business == null or not business.owns_anything():
		return _failure("no_business", "Своего места пока нет")
	if units <= 0:
		return _failure("nothing_to_buy", "Сколько брать?")
	var entry := _entry(business.business_id)
	var cost := units * int(entry.get("stock_price_ard", 0))
	if int(target.get("run_state").money) < cost:
		return _failure("not_enough_money", "На столько материала не хватит")
	return _commit(
		target,
		command_id,
		"business_restock",
		"Закуплен материал",
		[{"type": "change_money", "amount": -cost, "reason": "Материал для верстака"}],
		func(state: BusinessState, _elapsed: int) -> bool:
			return state.add_stock(units)
	)


static func set_hands(target: Object, count: int, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var business: BusinessState = target.get("business_state")
	if business == null or not business.owns_anything():
		return _failure("no_business", "Своего места пока нет")
	var entry := _entry(business.business_id)
	var maximum := int(entry.get("max_hands", 0))
	if count < 0 or count > maximum:
		return _failure("too_many_hands", "Столько людей за верстак не встанет")
	# Hiring and letting go are settled first, so a day is never paid at the new
	# headcount when it was worked at the old one.
	var settled := settle(target, "%s:settle" % command_id)
	if not bool(settled.get("ok", true)):
		return settled
	return _commit(
		target,
		command_id,
		"business_hands",
		"Нанят помощник" if count > business.hands else "Помощник отпущен",
		[],
		func(state: BusinessState, _elapsed: int) -> bool:
			return state.set_hands(count, maximum)
	)


## The reckoning. Everything since the last one, paid or owed.
static func settle(target: Object, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	var business: BusinessState = target.get("business_state")
	if business == null or not business.owns_anything():
		return _failure("no_business", "Своего места пока нет")
	var run_state: RunState = target.get("run_state")
	var elapsed := int(run_state.calendar.elapsed_minutes)
	var days := business.days_owed(elapsed)
	if days <= 0:
		return {"ok": true, "code": "nothing_to_settle", "error": "", "idempotent": false, "reckoning": {}}
	var entry := _entry(business.business_id)
	var reckoning := CatalogScript.reckon(entry, business.stock, business.hands, days)
	var net := int(reckoning["net"])
	var effects: Array = []
	if net != 0:
		effects.append({
			"type": "change_money",
			"amount": net,
			"reason": "Выручка за место" if net > 0 else "Содержание места",
		})
	var result := _commit(
		target,
		command_id,
		"business_settle",
		"Счёт за %d дн." % days,
		effects,
		func(state: BusinessState, current: int) -> bool:
			state.consume_stock(state.stock - int(reckoning["stock_left"]))
			state.mark_settled(current, days, int(reckoning["idle_days"]))
			return true
	)
	if bool(result.get("ok", false)):
		result["reckoning"] = reckoning
	return result


static func _entry(business_id: String) -> Dictionary:
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return {}
	return CatalogScript.find(Dictionary(loaded["catalog"]), business_id)


## Clone, change the place, apply the money, validate, publish. The money moves
## through the ordinary transaction so a settlement lands in the journal like
## everything else the hero decides.
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
	var state: BusinessState = candidate.get("business_state")
	if state == null:
		return _failure("missing_business_state", "Состояние места недоступно")
	var elapsed := int(candidate.get("run_state").calendar.elapsed_minutes)
	if not bool(change.call(state, elapsed)):
		return _failure("rejected", "Изменение не принято")
	var validation := state.validate()
	if not bool(validation.get("ok", false)):
		return _failure("invalid_business", String(Array(validation.get("errors", ["Неверное состояние"]))[0]))
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": source_id,
		"title": title,
		"journal_message": title,
		"journal_payload": {"business_id": state.business_id},
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
