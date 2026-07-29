class_name RoutineRunner
extends RefCounted

## Keeping to the plan, one stretch of the day at a time, until something stops
## it.
##
## The runner invents nothing. It walks to the place and confirms the same
## commands the screens confirm, through the same adapter, which is the only way
## the result can be trusted: a week lived by routine and a week lived by hand
## run identical code and can end in the same state. That is why this lives in
## the app layer next to the flow coordinators and not in the domain — it is a
## player who does not need to be asked, not a new rule.
##
## Its real job is knowing when to stop. A routine that pushes through a fever,
## an empty stomach and a waiting conversation is not a routine, it is a way of
## skipping the game. Every reason to hand control back is named and reported.

const CatalogScript := preload("res://game/routine/routine_catalog.gd")
const RoutesScript := preload("res://game/district/district_routes.gd")

## Needs at which the day stops being about the plan.
const HUNGRY := 70
const EXHAUSTED := 20
const HURT := 40

## Why control came back. The player is told in words; this is what code matches.
const STOP_DONE := "done"
const STOP_NOT_FOLLOWING := "not_following"
const STOP_NEED := "need"
const STOP_EVENT := "event"
const STOP_UNAVAILABLE := "unavailable"
const STOP_UNREACHABLE := "unreachable"
const STOP_REFUSED := "refused"
const STOP_TERMINAL := "terminal"

## No single stretch may take more turns than this. A stretch that cannot finish
## is a defect, and spinning is the one failure a player cannot tell from a crash.
const MAX_TURNS_PER_SLOT := 12
## How far one walk may go before the runner decides the map is wrong.
const MAX_LEGS := 8

## What the pack counts as food, most filling first.
const FOOD_ITEMS := ["ration_can", "sealed_food_can", "simple_meal", "bread_loaf"]
## Meals kept in the pack before buying more is pointless.
const FOOD_STOCK := 3


## What the plan says about right now, without acting on it.
static func current_slot(adapter: Object) -> Dictionary:
	var session: Object = adapter.get("_session")
	if session == null:
		return {}
	var run_state: RunState = session.get("run_state")
	if run_state == null:
		return {}
	var elapsed := int(run_state.calendar.elapsed_minutes)
	var minute := int(run_state.calendar.minute_of_day)
	return {
		"day_of_week": WeekSchedule.day_of_week(elapsed),
		"block_id": WeekSchedule.block_of_minute(minute),
		"slot_key": WeekSchedule.slot_key(elapsed, minute),
	}


## Carries the plan forward for up to `slots` stretches and reports what
## happened. Stops at the first thing that would need a decision.
static func follow(adapter: Object, slots: int) -> Dictionary:
	var routine := _routine(adapter)
	if routine == null:
		return _stopped(STOP_NOT_FOLLOWING, "Распорядок недоступен", [])
	if not routine.following:
		return _stopped(STOP_NOT_FOLLOWING, "Вы не держитесь распорядка", [])
	if not routine.is_planned():
		return _stopped(STOP_NOT_FOLLOWING, "Неделя ещё не расписана", [])
	var carried: Array = []
	for _index: int in maxi(slots, 1):
		var step := _run_one_slot(adapter)
		if not Dictionary(step.get("entry", {})).is_empty():
			carried.append(step["entry"])
		if String(step.get("stop", "")) != "":
			return _stopped(String(step["stop"]), String(step.get("reason", "")), carried)
	return _stopped(STOP_DONE, "", carried)


static func _run_one_slot(adapter: Object) -> Dictionary:
	if String(adapter.call("get_phase")) == "completed":
		return {"stop": STOP_TERMINAL, "reason": "Попытка окончена"}
	# A card waiting for an answer outranks anything written in a plan.
	if _has_pending_event(adapter):
		return {"stop": STOP_EVENT, "reason": "Случившееся требует ответа"}
	var needs := need_reasons(adapter)
	if not needs.is_empty():
		return {"stop": STOP_NEED, "reason": String(needs[0])}

	var routine := _routine(adapter)
	var slot := current_slot(adapter)
	if slot.is_empty():
		return {"stop": STOP_UNAVAILABLE, "reason": "Время неизвестно"}
	var slot_key := String(slot["slot_key"])
	var loaded_now := CatalogScript.load_default()
	var catalog_now: Dictionary = Dictionary(loaded_now.get("catalog", {}))
	var day_plan: Dictionary = Dictionary(Dictionary(routine.plan).get(str(int(slot["day_of_week"])), {}))
	var holder := CatalogScript.holder_of(catalog_now, day_plan, String(slot["block_id"]))
	# A stretch the morning's work is still running through is not a new activity
	# to start. The shift already took it; the day moves on.
	if not holder.is_empty() and bool(holder.get("spills", false)):
		if not _let_the_stretch_pass(adapter):
			return {"stop": STOP_UNAVAILABLE, "reason": "Время не сдвинулось"}
		routine.mark_slot(slot_key)
		return {}
	var activity_id := routine.activity_for(int(slot["day_of_week"]), String(slot["block_id"]))
	# A stretch already lived — after reloading a save mid-week, say — is moved
	# past rather than lived twice.
	if routine.has_run_slot(slot_key) or activity_id.is_empty():
		if not _let_the_stretch_pass(adapter):
			return {"stop": STOP_UNAVAILABLE, "reason": "Время не сдвинулось"}
		routine.mark_slot(slot_key)
		return {}

	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return {"stop": STOP_UNAVAILABLE, "reason": "Список занятий недоступен"}
	var activity := CatalogScript.find(Dictionary(loaded["catalog"]), activity_id)
	if activity.is_empty():
		return {"stop": STOP_UNAVAILABLE, "reason": "Занятие из распорядка больше не существует"}

	var arrival := _walk_to(adapter, String(activity.get("location_id", "")))
	if not bool(arrival.get("ok", true)):
		return {
			"stop": String(arrival.get("stop", STOP_UNREACHABLE)),
			"reason": String(arrival.get("reason", "")),
		}

	var unattended := routine.is_mastered(activity_id, int(activity.get("mastery_repeats", 4)))
	var done := _carry_out(adapter, activity, unattended)
	if not bool(done.get("ok", false)):
		var stop := String(done.get("stop", STOP_REFUSED))
		# Something that simply cannot be done right now — nothing to hand in,
		# the counter is shut — costs the hero the stretch and the week moves on.
		# A need or a waiting decision does not: those are meant to be dealt with
		# and the stretch resumed, and consuming it would quietly skip the plan.
		if stop == STOP_UNAVAILABLE:
			_let_the_stretch_pass(adapter)
			routine.mark_slot(slot_key)
		return {"stop": stop, "reason": String(done.get("reason", "Не вышло"))}
	routine.record_practice(activity_id)
	routine.mark_slot(slot_key)
	return {
		"entry": {
			"activity_id": activity_id,
			"title": String(activity.get("title", "")),
			"day_of_week": int(slot["day_of_week"]),
			"block_id": String(slot["block_id"]),
			"unattended": unattended,
		},
	}


## Needs a plan is not allowed to override, in the words the player would hear.
static func need_reasons(adapter: Object) -> Array[String]:
	var reasons: Array[String] = []
	var session: Object = adapter.get("_session")
	if session == null:
		return reasons
	var run_state: RunState = session.get("run_state")
	if run_state == null:
		return reasons
	if int(run_state.get_meter("hunger")) >= HUNGRY:
		reasons.append("Голод не даёт заниматься чем-то ещё")
	if int(run_state.get_meter("energy")) <= EXHAUSTED:
		reasons.append("Сил не осталось")
	if int(run_state.get_meter("health")) <= HURT:
		reasons.append("Со здоровьем так нельзя")
	return reasons


static func _routine(adapter: Object) -> RoutineState:
	var session: Object = adapter.get("_session")
	if session == null:
		return null
	return session.get("routine_state")


static func _has_pending_event(adapter: Object) -> bool:
	var model: Dictionary = adapter.call("get_current_event_model")
	return not model.is_empty() and not Array(model.get("choices", [])).is_empty()


## Walks one leg at a time. Travel is an ordinary confirmed command, so getting
## there costs what getting there costs.
static func _walk_to(adapter: Object, destination: String) -> Dictionary:
	if destination.is_empty():
		return {"ok": true}
	var legs := 0
	while String(adapter.call("get_location_id")) != destination:
		legs += 1
		if legs > MAX_LEGS:
			return {"ok": false, "stop": STOP_UNREACHABLE, "reason": "Дорога туда потерялась"}
		var step := RoutesScript.first_step(String(adapter.call("get_location_id")), destination)
		if step.is_empty():
			return {"ok": false, "stop": STOP_UNREACHABLE, "reason": "Туда отсюда не пройти"}
		var travelled: Dictionary = adapter.call("travel", step, "walk")
		if not bool(travelled.get("ok", false)):
			return {
				"ok": false,
				"stop": STOP_UNREACHABLE,
				"reason": String(travelled.get("error", "Дорога закрыта")),
			}
		if _has_pending_event(adapter):
			return {"ok": false, "stop": STOP_EVENT, "reason": "По дороге что-то случилось"}
	return {"ok": true}


static func _carry_out(adapter: Object, activity: Dictionary, unattended: bool) -> Dictionary:
	match String(activity.get("kind", "")):
		"job_shift":
			return _work_shift(adapter, unattended)
		"search":
			return _search(adapter, unattended)
		"shelter":
			return _sleep(adapter)
		"meal":
			return _eat(adapter)
		"stock":
			return _stock_food(adapter, activity)
		"recycle":
			return _sell_recyclables(adapter)
		"rest":
			return _rest(adapter)
	return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Такое занятие не выполняется"}


## A shift the hero knows is skipped through; one he does not is worked step by
## step. Either way the decision inside it comes back to the player — that is
## the part of a shift which is not routine.
static func _work_shift(adapter: Object, unattended: bool) -> Dictionary:
	# A shift left half-worked — the runner handed the decision back and the
	# player did something else — is picked up rather than started again. One
	# shift a day is the rule, so beginning a second would refuse and the hero
	# would stand at the gate every morning for the rest of the week.
	if not bool(adapter.call("is_job_shift_active")):
		if not bool(adapter.call("begin_job_shift").get("ok", false)):
			return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "В смену сегодня не ставят"}
	var turns := 0
	while bool(adapter.call("is_job_shift_active")):
		turns += 1
		if turns > MAX_TURNS_PER_SLOT:
			return {"ok": false, "stop": STOP_REFUSED, "reason": "Смена не двигается"}
		var model: Dictionary = adapter.call("get_job_shift_model")
		var step: Dictionary = Dictionary(model.get("current_step", {}))
		if String(step.get("kind", "task")) == "decision":
			return {"ok": false, "stop": STOP_EVENT, "reason": "Смена дошла до решения"}
		if unattended and bool(adapter.call("quick_resolve_job_shift").get("ok", false)):
			continue
		var choices: Array = Array(step.get("choices", []))
		if choices.is_empty():
			return {"ok": false, "stop": STOP_REFUSED, "reason": "Смена не предлагает действий"}
		var resolved: Dictionary = adapter.call(
			"resolve_job_shift_step", String(Dictionary(choices[0]).get("id", ""))
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "stop": STOP_REFUSED, "reason": String(resolved.get("error", ""))}
	return {"ok": true}


## The zone is swept the quick way once that has been earned, and walked by hand
## before then — the same rule the search domain already enforces.
static func _search(adapter: Object, unattended: bool) -> Dictionary:
	if not bool(adapter.call("begin_search").get("ok", false)):
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Здесь сейчас не поискать"}
	var swept := unattended and bool(adapter.call("run_quick_search").get("ok", false))
	if not swept:
		swept = bool(adapter.call("run_quick_search").get("ok", false))
	adapter.call("finish_search")
	if not swept:
		return {"ok": false, "stop": STOP_REFUSED, "reason": "Обход не задался"}
	return {"ok": true}


static func _sleep(adapter: Object) -> Dictionary:
	var chosen := ""
	var best := -1
	for raw_option: Variant in Array(adapter.call("available_shelters")):
		var option: Dictionary = raw_option
		if bool(option.get("locked", false)):
			continue
		if int(option.get("quality", 0)) > best:
			best = int(option.get("quality", 0))
			chosen = String(option.get("id", ""))
	if chosen.is_empty():
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Ночевать негде"}
	var slept: Dictionary = adapter.call("choose_shelter", chosen)
	if not bool(slept.get("ok", false)):
		return {"ok": false, "stop": STOP_REFUSED, "reason": String(slept.get("error", "Не пустили"))}
	return {"ok": true}


## Eats the most filling thing in the pack. Nothing to eat is a reason to stop,
## not a stretch quietly skipped.
static func _eat(adapter: Object) -> Dictionary:
	var stack_id := ""
	var best := FOOD_ITEMS.size()
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		var rank := FOOD_ITEMS.find(String(stack.get("item_id", "")))
		if rank < 0 or rank >= best:
			continue
		best = rank
		stack_id = String(stack.get("stack_id", ""))
	if stack_id.is_empty():
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Есть нечего"}
	if not bool(adapter.call("perform_inventory_action", stack_id, "use").get("ok", false)):
		return {"ok": false, "stop": STOP_REFUSED, "reason": "Поесть не вышло"}
	return {"ok": true}


static func _stock_food(adapter: Object, activity: Dictionary) -> Dictionary:
	var store_id := String(activity.get("store_id", ""))
	if store_id.is_empty():
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Покупать негде"}
	if _carried_food(adapter) >= FOOD_STOCK:
		return {"ok": true}
	var store: Dictionary = adapter.call("get_store_model", store_id)
	if not bool(store.get("ok", false)) or not bool(store.get("open", false)):
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Сегодня закрыто"}
	var money := _money(adapter)
	for item_id: String in FOOD_ITEMS:
		for raw_offer: Variant in Array(store.get("offers", [])):
			var offer: Dictionary = raw_offer
			if String(offer.get("item_id", "")) != item_id:
				continue
			if int(offer.get("unit_price", 0)) > money:
				continue
			if bool(adapter.call(
				"buy_store_offer",
				store_id,
				String(offer.get("offer_id", "")),
				1,
				"pockets",
				int(store.get("revision", 0))
			).get("ok", false)):
				return {"ok": true}
	return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "На еду сейчас не хватает"}


static func _sell_recyclables(adapter: Object) -> Dictionary:
	var offers: Array = adapter.call("get_recycling_offers")
	if offers.is_empty():
		return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Сдавать нечего"}
	var offer: Dictionary = offers[0]
	var sold: Dictionary = adapter.call(
		"perform_inventory_action",
		String(offer.get("stack_id", "")),
		"sell",
		int(offer.get("quantity", 1))
	)
	if not bool(sold.get("ok", false)):
		return {"ok": false, "stop": STOP_REFUSED, "reason": "Не приняли"}
	return {"ok": true}


## Doing nothing on purpose: whatever the place allows that costs time.
static func _rest(adapter: Object) -> Dictionary:
	if _let_the_stretch_pass(adapter):
		return {"ok": true}
	return {"ok": false, "stop": STOP_UNAVAILABLE, "reason": "Здесь не передохнуть"}


## Moves the clock out of this stretch entirely, not merely forward.
##
## One call to the runner is meant to be one stretch of the day. Doing a single
## short thing and returning left the hero inside the same morning, so following
## a routine for a week took hundreds of calls and looked like it was stuck.
static func _let_the_stretch_pass(adapter: Object) -> bool:
	var session: Object = adapter.get("_session")
	if session == null:
		return false
	var run_state: RunState = session.get("run_state")
	if run_state == null:
		return false
	var started_in := WeekSchedule.block_of_minute(int(run_state.calendar.minute_of_day))
	var moved := false
	for _turn: int in MAX_TURNS_PER_SLOT:
		if not _spend_a_little_time(adapter):
			break
		moved = true
		if WeekSchedule.block_of_minute(int(run_state.calendar.minute_of_day)) != started_in:
			return true
		if _has_pending_event(adapter):
			return true
	return moved


## Whatever the place allows that costs the clock something, or a walk if it
## allows nothing at all.
static func _spend_a_little_time(adapter: Object) -> bool:
	var best: Dictionary = {}
	for raw_action: Variant in Array(Dictionary(adapter.call("get_location_model")).get("actions", [])):
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		if String(action.get("kind", "")) != "local" or not bool(action.get("available", false)):
			continue
		if int(action.get("minutes", 0)) <= 0:
			continue
		if best.is_empty() or int(action.get("minutes", 0)) > int(best.get("minutes", 0)):
			best = action
	if not best.is_empty():
		if bool(adapter.call("perform_location_action", String(best.get("id", ""))).get("ok", false)):
			return true
	for neighbour: String in RoutesScript.exits_from(String(adapter.call("get_location_id"))):
		if bool(adapter.call("travel", neighbour, "walk").get("ok", false)):
			return true
	return false


static func _carried_stacks(adapter: Object) -> Array:
	var model: Dictionary = adapter.call("get_inventory_model")
	var result: Array = []
	for raw_container: Variant in Array(model.get("containers", [])):
		if not raw_container is Dictionary:
			continue
		result.append_array(Array(Dictionary(raw_container).get("stacks", [])))
	return result


static func _carried_food(adapter: Object) -> int:
	var total := 0
	for raw_stack: Variant in _carried_stacks(adapter):
		if String(Dictionary(raw_stack).get("item_id", "")) in FOOD_ITEMS:
			total += int(Dictionary(raw_stack).get("quantity", 1))
	return total


static func _money(adapter: Object) -> int:
	var session: Object = adapter.get("_session")
	if session == null:
		return 0
	var run_state: RunState = session.get("run_state")
	return 0 if run_state == null else int(run_state.money)


static func _stopped(code: String, reason: String, carried: Array) -> Dictionary:
	return {"ok": true, "stopped": code, "reason": reason, "carried": carried}
