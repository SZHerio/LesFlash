extends SceneTree

## M3F.7 acceptance gate: the week is played, not asserted.
##
## Every other suite proves one system works on its own. This one proves the
## week works, and it does so the only way that counts — through the public
## sandbox adapter, the same commands the screens call. Nothing here writes a
## session field, advances the calendar by hand or sets a meter to make a day
## fit. If a legal build cannot survive seven days this way, the game cannot
## either, and this is where that has to fail.
##
## The driver is deliberately plain: it looks at what the place offers, acts on
## need first, and confirms. A week that only a clever player can survive is a
## balance problem the gate should expose rather than hide.

const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const SurvivalStateScript := preload("res://game/survival/survival_state.gd")
const InventoryState := preload("res://core/inventory/inventory_state.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const MasteryScript := preload("res://game/jobs/job_mastery.gd")

const EVENING_MINUTE := 18 * 60
const MAX_TURNS_PER_DAY := 60
const MAX_DAYS := 10
## A week is eight stretches at most; the rest is head-room for a bad day.
const MAX_ROUNDS := 24
## Luck is compared over a measured stretch: the spread and the fact that both
## extremes stay alive are visible long before the seventh day.
const LUCK_ROUNDS := 5
const HUNGRY := 35
## A night costs about as much hunger as a working day, so the hero goes to bed fed.
const NIGHT_HUNGER_FLOOR := 10
## Below this the day stops being about earning and starts being about resting.
const TIRED := 40
## Six hours of sorting with no chance to eat: nobody starts that hungry.
const SHIFT_HUNGER_LIMIT := 45
const FOOD_STOCK := 3
## Money kept back for shelter and emergencies before stocking the pack.
const FOOD_RESERVE := 60
## Everything the food row sells that answers hunger. The driver buys by value,
## not by habit: a ration tin is worth more hunger per arden than a hot meal.
const FOOD_ITEMS := ["ration_can", "sealed_food_can", "simple_meal", "bread_loaf"]
const FOOD_ITEM := "simple_meal"
const MARKET_STORE := "store_market_food_row"
const YARD := "recycling_point"
const MARKET := "market"
const CLINIC := "clinic_yard"
const PHARMACY_STORE := "store_clinic_pharmacy_window"
## Whatever the window happens to be selling: the shelf is generated, so a
## player who only knows one remedy goes untreated for reasons of stock.
const HEALING_ITEMS := ["bandage_roll", "painkiller_strip", "medicine_blister", "cloth_rag"]
const COMMISSION_STORE := "store_station_commission"
const STATION := "station_square"
## What a week outdoors is actually worth spending on, in the order it pays off.
## Cheapest warmth first: a blanket is what a first wage can actually reach,
## and sleeping rough without one is what killed the labourer.
const WEEK_GEAR := ["blanket_roll", "work_gloves", "sturdy_boots", "warm_jacket"]
## Gear is bought out of surplus, never out of the food money: a blanket that
## costs the week its meals kills faster than the cold it prevents.
const GEAR_RESERVE := 260
## A paid room costs a hundred; below this the night has to be free.
const ROOM_RESERVE := 420
## Below this a week of cold nights and heavy days needs treating, not enduring.
const HURT := 70
const SEARCH_ZONE_LOCATION := "underpass"
## The free niche: whatever else the day was, it can always end here.
const SHELTER_FALLBACK := "underpass"

## Three legal builds that spend the same eighteen points from different sides.
const BUILDS := {
	"labourer": {"strength": 10, "charisma": 3, "intelligence": 3, "luck": 2},
	"talker": {"strength": 3, "charisma": 10, "intelligence": 3, "luck": 2},
	"scavenger": {"strength": 3, "charisma": 2, "intelligence": 3, "luck": 10},
}
## What each of them reaches for first when the day is otherwise free.
const PRIORITIES := {
	"labourer": ["shift", "recycle", "work_action", "rest"],
	"talker": ["npc", "shift", "trade", "rest"],
	"scavenger": ["search", "recycle", "shift", "rest"],
}

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("three builds live seven real days through public commands", _test_three_builds_live_the_week)
	_run("a mid-week save reopens on exactly the same state", _test_midweek_save_load)
	_run("low and high Luck diverge on one seed without becoming a lottery", _test_luck_spread)
	_run("the earned quick shift is never worse than working it by hand", _test_quick_resolve_not_worse)
	_cleanup_saves()
	if _failures.is_empty():
		print("M3F.7 WEEK ACCEPTANCE PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.7 WEEK ACCEPTANCE FAILED: %d failure(s) across %d test(s)" % [
		_failures.size(), _tests_run,
	])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


# --- three legal builds -----------------------------------------------------


func _test_three_builds_live_the_week() -> void:
	var digests: Dictionary = {}
	var signatures: Dictionary = {}
	for build_id: String in BUILDS:
		var adapter = SandboxAdapter.create(BUILDS[build_id], 51_000)
		_expect(adapter != null, "%s must start" % build_id)
		if adapter == null:
			continue
		var lived := _live_week(adapter, build_id)
		var counters: Dictionary = lived["counters"]
		_expect(
			bool(lived.get("survived", false)),
			"%s must reach the end of the week alive (status=%s, rounds=%d, elapsed=%d, %s)" % [
				build_id,
				String(lived.get("status", "")),
				int(lived.get("days", 0)),
				int(lived.get("elapsed", 0)),
				_activity_signature(counters),
			]
		)
		_expect_equal(adapter.get_phase(), "completed", "%s must finish the prototype week" % build_id)
		_expect(
			int(counters.get("nights", 0)) >= 5,
			"%s must sleep through the week, not skip it (nights=%d)" % [
				build_id, int(counters.get("nights", 0)),
			]
		)
		_expect(
			int(counters.get("earned_ard", 0)) > 0,
			"%s must earn money during the week" % build_id
		)
		digests[build_id] = _digest(adapter)
		signatures[build_id] = _activity_signature(counters)
	var ids: Array = digests.keys()
	for left: int in ids.size():
		for right: int in range(left + 1, ids.size()):
			_expect(
				digests[ids[left]] != digests[ids[right]],
				"%s and %s must end the week in different states" % [ids[left], ids[right]]
			)
			_expect(
				signatures[ids[left]] != signatures[ids[right]],
				"%s and %s must spend the week on different occupations (%s | %s)" % [
					ids[left], ids[right], signatures[ids[left]], signatures[ids[right]],
				]
			)


# --- save and load in the middle of the week --------------------------------


func _test_midweek_save_load() -> void:
	var adapter = SandboxAdapter.create(BUILDS["labourer"], 51_501)
	_expect(adapter != null, "mid-week run must start")
	if adapter == null:
		return
	var counters := _fresh_counters()
	for _day: int in 3:
		if adapter.get_phase() == "completed":
			break
		_live_one_day(adapter, "labourer", counters)
	_expect(adapter.get_phase() != "completed", "the run must still be mid-week when it is saved")
	var path := _save_path("midweek")
	var saved: Dictionary = adapter.save(path)
	_expect(bool(saved.get("ok", false)), "mid-week save must succeed: %s" % str(saved))
	var before := _digest(adapter)

	var reopened: Dictionary = SandboxAdapter.load_session(path)
	_expect(bool(reopened.get("ok", false)), "mid-week save must reopen: %s" % str(reopened))
	if not bool(reopened.get("ok", false)):
		return
	var restored = reopened["adapter"]
	_expect(restored.is_valid(), "reopened run must validate")
	_expect_equal(_digest(restored), before, "reopening must not change a single observable value")

	# A reopened run has to be playable, not merely readable.
	var rounds := 0
	while restored.get_phase() != "completed" and rounds < MAX_ROUNDS:
		var before_elapsed := _elapsed(restored)
		_live_one_day(restored, "labourer", counters)
		rounds += 1
		if _elapsed(restored) == before_elapsed:
			break
	_expect_equal(
		restored.get_phase(),
		"completed",
		"a reopened run must still reach the end of the week"
	)


# --- luck -------------------------------------------------------------------


func _test_luck_spread() -> void:
	var low = SandboxAdapter.create(
		{"strength": 6, "charisma": 5, "intelligence": 6, "luck": 1}, 51_777
	)
	var high = SandboxAdapter.create(
		{"strength": 6, "charisma": 5, "intelligence": 6, "luck": 1}, 51_777
	)
	_expect(low != null and high != null, "both Luck runs must start")
	if low == null or high == null:
		return
	# Same seed, same eighteen points, one moved from Intelligence into Luck.
	var lucky = SandboxAdapter.create(
		{"strength": 6, "charisma": 5, "intelligence": 1, "luck": 6}, 51_777
	)
	_expect(lucky != null, "the lucky variant must start")
	if lucky == null:
		return
	var unlucky_result := _live_week(low, "scavenger", LUCK_ROUNDS)
	var lucky_result := _live_week(lucky, "scavenger", LUCK_ROUNDS)
	_expect(
		_digest(low) != _digest(lucky),
		"the same seed with different Luck must not end identically"
	)
	# The spread has to be visible without deciding whether the week is
	# survivable at all — that is the difference between variance and a lottery.
	_expect(
		String(unlucky_result.get("status", "")) != "dead",
		"low Luck must not be a death sentence (status=%s)" % String(unlucky_result.get("status", ""))
	)
	_expect(
		String(lucky_result.get("status", "")) != "dead",
		"high Luck must not be a death sentence either (status=%s)" % String(lucky_result.get("status", ""))
	)
	_expect(
		int(Dictionary(unlucky_result["counters"]).get("earned_ard", 0)) > 0
		and int(Dictionary(lucky_result["counters"]).get("earned_ard", 0)) > 0,
		"both Luck extremes must still earn a living"
	)
	# `high` is the untouched twin of `low`: identical points, identical seed.
	var twin_result := _live_week(high, "scavenger", LUCK_ROUNDS)
	_expect(
		String(twin_result.get("status", "")) != "dead",
		"the control twin must come through the same stretch"
	)
	_expect_equal(
		_digest(high),
		_digest(low),
		"two identical builds on one seed must reproduce each other exactly"
	)


# --- the earned shortcut ----------------------------------------------------


func _test_quick_resolve_not_worse() -> void:
	var adapter = SandboxAdapter.create(BUILDS["labourer"], 52_020)
	_expect(adapter != null, "quick-resolve run must start")
	if adapter == null:
		return
	var counters := _fresh_counters()
	# Earn the shortcut first: it opens only after several different shifts.
	for _round: int in MAX_ROUNDS:
		if adapter.get_phase() == "completed":
			break
		var before_elapsed := _elapsed(adapter)
		_live_one_day(adapter, "labourer", counters)
		if int(counters.get("shifts", 0)) >= MasteryScript.QUICK_MIN_SHIFTS:
			break
		if _elapsed(adapter) == before_elapsed:
			break
	_expect(
		int(counters.get("shifts", 0)) >= MasteryScript.QUICK_MIN_SHIFTS,
		"the week must allow the practice the shortcut asks for (shifts=%d)" % int(counters.get("shifts", 0))
	)
	# Then stand at the briefing of the next shift without working it.
	var prepared := false
	for _attempt: int in 4:
		if adapter.get_phase() == "completed":
			break
		if _begin_shift_only(adapter) and _quick_resolve_offered(adapter):
			prepared = true
			break
		_rest_until_morning(adapter, counters)
	_expect(
		prepared,
		"varied confirmed practice must open the quick calculation (shifts=%d)" % int(counters.get("shifts", 0))
	)
	if not prepared:
		return

	var path := _save_path("quick")
	_expect(bool(adapter.save(path).get("ok", false)), "the shift state must be saved for comparison")
	var manual = _reopen(path)
	var quick = _reopen(path)
	if manual == null or quick == null:
		return
	var manual_result := _finish_shift_manually(manual)
	var quick_result := _finish_shift_quickly(quick)
	_expect(bool(manual_result.get("ok", false)), "the hand-worked shift must finish: %s" % str(manual_result))
	_expect(bool(quick_result.get("ok", false)), "the quick shift must finish: %s" % str(quick_result))
	if not bool(manual_result.get("ok", false)) or not bool(quick_result.get("ok", false)):
		return
	_expect(bool(quick_result.get("used_quick", false)), "the quick path must use the shortcut")
	_expect(
		bool(quick_result.get("decided", false)),
		"the quick path must still ask for the decision of the shift"
	)
	_expect(
		int(quick_result["overall"]) >= int(manual_result["overall"]),
		"the shortcut must not score below working the same shift by hand (quick=%d manual=%d)" % [
			int(quick_result["overall"]), int(manual_result["overall"]),
		]
	)
	_expect(
		int(quick_result["money"]) >= int(manual_result["money"]),
		"the shortcut must not pay less than working the same shift by hand (quick=%d manual=%d)" % [
			int(quick_result["money"]), int(manual_result["money"]),
		]
	)


# --- the week driver --------------------------------------------------------


## Plays until the week ends, the hero does, or the run stops moving. Rounds are
## counted rather than days because a stretch that fails to reach the evening is
## still a stretch the driver has to get out of.
func _live_week(adapter: Object, build_id: String, round_limit: int = MAX_ROUNDS) -> Dictionary:
	var counters := _fresh_counters()
	var rounds := 0
	while rounds < round_limit and adapter.get_phase() != "completed":
		var before := _elapsed(adapter)
		_live_one_day(adapter, build_id, counters)
		rounds += 1
		if _elapsed(adapter) == before:
			break
	var lifecycle: Dictionary = Dictionary(adapter.get_summary_model().get("lifecycle", {}))
	var status := String(lifecycle.get("status", "unknown"))
	return {
		"survived": status == SurvivalStateScript.STATUS_WEEK_COMPLETE,
		"status": status,
		"days": rounds,
		"elapsed": _elapsed(adapter),
		"counters": counters,
	}


static func _record_income(counters: Dictionary, before: int, after: int) -> int:
	if after > before:
		counters["earned_ard"] = int(counters["earned_ard"]) + (after - before)
	return after


func _elapsed(adapter: Object) -> int:
	var lifecycle: Dictionary = Dictionary(adapter.get_summary_model().get("lifecycle", {}))
	return int(lifecycle.get("processed_elapsed_minutes", 0))


## One playable day: act until the evening, then find somewhere to sleep.
func _live_one_day(adapter: Object, build_id: String, counters: Dictionary) -> void:
	var turns := 0
	# Income is measured, not reported: whatever raised the wallet counts,
	# whether it was a shift, a sale or a stranger's kindness.
	var wallet := _money(adapter)
	while turns < MAX_TURNS_PER_DAY:
		turns += 1
		if adapter.get_phase() == "completed":
			_record_income(counters, wallet, _money(adapter))
			return
		if _minute_of_day(adapter) >= EVENING_MINUTE:
			break
		if _feed_if_hungry(adapter, counters):
			wallet = _record_income(counters, wallet, _money(adapter))
			continue
		if _treat_if_hurt(adapter, counters):
			wallet = _record_income(counters, wallet, _money(adapter))
			continue
		if _take_priority_turn(adapter, build_id, counters):
			wallet = _record_income(counters, wallet, _money(adapter))
			continue
		if not _pass_time(adapter, counters):
			break
		wallet = _record_income(counters, wallet, _money(adapter))
	# Twelve hours of sleep cost as much hunger as a working day, so a hero who
	# goes to bed merely "not starving" wakes up starving.
	_eat_down_to(adapter, counters, NIGHT_HUNGER_FLOOR)
	_sleep_somewhere(adapter, counters)


## Eats, buying if there is nothing to eat, until the need is genuinely met or
## nothing more can be done about it.
func _eat_down_to(adapter: Object, counters: Dictionary, floor_value: int) -> void:
	for _bite: int in 4:
		if adapter.get_phase() == "completed":
			return
		if _meter(adapter, "hunger") <= floor_value:
			return
		if _eat_carried_food(adapter, counters):
			continue
		if not _buy_food(adapter, counters):
			return
		if not _eat_carried_food(adapter, counters):
			return


## Opens a shift and stops at the briefing, so the comparison below happens on a
## shift that is genuinely in progress.
func _begin_shift_only(adapter: Object) -> bool:
	if adapter.is_job_shift_active():
		return true
	if not _go_to(adapter, YARD):
		return false
	if _find_action(adapter, "job_shift").is_empty():
		return false
	return bool(adapter.begin_job_shift().get("ok", false))


## Passes the rest of the day and sleeps, without touching the yard.
func _rest_until_morning(adapter: Object, counters: Dictionary) -> void:
	var turns := 0
	while turns < MAX_TURNS_PER_DAY and _minute_of_day(adapter) < EVENING_MINUTE:
		turns += 1
		if adapter.get_phase() == "completed":
			return
		if _feed_if_hungry(adapter, counters):
			continue
		if not _pass_time(adapter, counters):
			break
	_sleep_somewhere(adapter, counters)


func _take_priority_turn(adapter: Object, build_id: String, counters: Dictionary) -> bool:
	# An exhausted hero rests before he works, whatever he came here to do.
	if _meter(adapter, "energy") < TIRED and _perform_kind(adapter, "local", counters, "rest"):
		return true
	# Anything bought to be worn goes on before it is carried another day.
	if _wear_what_is_carried(adapter, counters):
		return true
	# A coat lasts the whole week; a third spare meal lasts three hours. Gear is
	# bought before the pack is topped up, or the wallet never reaches it.
	if _dress_for_the_week(adapter, counters):
		return true
	# The food row shuts at three; a hero who only shops when hungry starves at
	# night. Stock up while the counter is open.
	if _stock_food(adapter, counters):
		return true
	for intent: String in Array(PRIORITIES[build_id]):
		match intent:
			"shift":
				if _work_a_shift(adapter, counters):
					return true
			"recycle":
				if _sell_recyclables(adapter, counters):
					return true
			"search":
				if _run_a_search(adapter, counters):
					return true
			"npc":
				if _talk_to_someone(adapter, counters):
					return true
			"trade":
				if _buy_food(adapter, counters):
					return true
			"work_action":
				if _perform_kind(adapter, "local", counters, "work"):
					return true
			"rest":
				if _perform_kind(adapter, "local", counters, "rest"):
					return true
	return false


func _work_a_shift(adapter: Object, counters: Dictionary) -> bool:
	if not adapter.is_job_shift_active():
		# The shift is one uninterrupted stretch of six hours, so going into it
		# hungry means coming out of it starving.
		if _meter(adapter, "hunger") > SHIFT_HUNGER_LIMIT:
			printerr("SHIFT SKIP hungry=%d" % _meter(adapter, "hunger"))
			return false
		if not _go_to(adapter, YARD):
			printerr("SHIFT SKIP cannot reach yard from %s" % String(adapter.get_location_id()))
			return false
		if _find_action(adapter, "job_shift").is_empty():
			printerr("SHIFT SKIP no action minute=%d" % _minute_of_day(adapter))
			return false
		var began: Dictionary = adapter.begin_job_shift()
		if not bool(began.get("ok", false)):
			printerr("SHIFT SKIP begin failed %s" % str(began))
			return false
	var guard := 0
	while adapter.is_job_shift_active() and guard < 12:
		guard += 1
		var step := _current_shift_step(adapter)
		if step.is_empty():
			break
		var choices: Array = Array(step.get("choices", []))
		if choices.is_empty():
			return false
		var resolved: Dictionary = adapter.resolve_job_shift_step(
			String(Dictionary(choices[0]).get("id", ""))
		)
		if not bool(resolved.get("ok", false)):
			return false
		if bool(resolved.get("completed", false)):
			counters["shifts"] = int(counters["shifts"]) + 1
			break
	return true


func _sell_recyclables(adapter: Object, counters: Dictionary) -> bool:
	if _carried_recyclables(adapter) <= 0:
		return false
	if not _go_to(adapter, YARD):
		return false
	var offers: Array[Dictionary] = adapter.get_recycling_offers()
	if offers.is_empty():
		return false
	var before := _money(adapter)
	var sold: Dictionary = adapter.perform_inventory_action(
		String(offers[0].get("stack_id", "")),
		"sell",
		int(offers[0].get("quantity", 1))
	)
	if not bool(sold.get("ok", false)):
		return false
	counters["sales"] = int(counters["sales"]) + 1
	return true


## Works the zone the way a player does: walk to a thing, decide how to open it,
## take what is worth taking. The quick sweep is only used once the hero has
## earned it, which is exactly the rule the search domain enforces.
func _run_a_search(adapter: Object, counters: Dictionary) -> bool:
	if _find_action(adapter, "search").is_empty():
		if not _go_to(adapter, SEARCH_ZONE_LOCATION):
			return false
		if _find_action(adapter, "search").is_empty():
			return false
	if not bool(adapter.begin_search().get("ok", false)):
		return false
	var worked := false
	if bool(adapter.run_quick_search().get("ok", false)):
		worked = true
	else:
		worked = _work_the_zone_by_hand(adapter)
	_collect_loot(adapter)
	adapter.finish_search()
	if not worked:
		return false
	counters["searches"] = int(counters["searches"]) + 1
	return true


func _work_the_zone_by_hand(adapter: Object) -> bool:
	var worked := false
	for _attempt: int in 8:
		if not adapter.is_search_active():
			break
		if not Dictionary(adapter.get_encounter_model()).is_empty():
			break
		var snapshot: Dictionary = Dictionary(adapter.get_search_model().get("snapshot", {}))
		var target := _next_search_object(snapshot)
		if target.is_empty():
			break
		var approaches: Array = Array(target.get("approaches", []))
		if approaches.is_empty():
			break
		# The route is planned to the object itself, then walked to its last
		# point — the same two steps the search screen performs.
		var planned: Dictionary = adapter.plan_search_move(String(target.get("id", "")))
		if bool(planned.get("ok", false)):
			var points: Array = Array(Dictionary(planned.get("path", {})).get("points", []))
			if not points.is_empty():
				adapter.checkpoint_search_move(points[points.size() - 1], points.size() - 1)
		var resolved: Dictionary = adapter.confirm_search_interaction(
			String(target.get("id", "")),
			String(Dictionary(approaches[0]).get("id", ""))
		)
		if not bool(resolved.get("ok", false)):
			break
		worked = true
	return worked


func _next_search_object(snapshot: Dictionary) -> Dictionary:
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = raw_object
		if String(object.get("state", "")) == "exhausted" or bool(object.get("interacted", false)):
			continue
		return object.duplicate(true)
	return {}


func _collect_loot(adapter: Object) -> void:
	for _attempt: int in 8:
		var tray: Array = Array(adapter.get_search_model().get("loot_tray", []))
		var taken := false
		for raw_entry: Variant in tray:
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var stack_id := String(entry.get("stack_id", ""))
			if stack_id.is_empty():
				continue
			if bool(adapter.pick_up_search_loot(stack_id, "pockets").get("ok", false)):
				taken = true
				break
		if not taken:
			return


func _talk_to_someone(adapter: Object, counters: Dictionary) -> bool:
	var action := _find_action(adapter, "npc")
	if action.is_empty():
		return false
	var payload: Dictionary = Dictionary(Dictionary(action.get("intent", {})).get("payload", {}))
	var npc_id := String(payload.get("npc_id", ""))
	var model: Dictionary = adapter.get_npc_model(npc_id)
	if not bool(model.get("ok", false)):
		return false
	for raw_interaction: Variant in Array(model.get("interactions", [])):
		if not raw_interaction is Dictionary:
			continue
		var interaction: Dictionary = raw_interaction
		if not bool(interaction.get("enabled", false)):
			continue
		var executed: Dictionary = adapter.execute_npc_interaction(
			npc_id,
			String(interaction.get("id", "")),
			int(model.get("expected_revision", 0))
		)
		if bool(executed.get("ok", false)):
			counters["talks"] = int(counters["talks"]) + 1
			return true
	return false


## A week of open nights and heavy days wears a person down. The pharmacy window
## is the answer the district actually offers, and using it is part of living
## the week rather than merely surviving it.
func _treat_if_hurt(adapter: Object, counters: Dictionary) -> bool:
	if _meter(adapter, "health") >= HURT:
		return false
	for item_id: String in HEALING_ITEMS:
		if _use_carried(adapter, item_id):
			counters["treatments"] = int(counters["treatments"]) + 1
			return true
	if not _buy_from(adapter, counters, CLINIC, PHARMACY_STORE, HEALING_ITEMS):
		return false
	for item_id: String in HEALING_ITEMS:
		if _use_carried(adapter, item_id):
			counters["treatments"] = int(counters["treatments"]) + 1
			return true
	return false


## A week of open nights is answered with a coat, not with endurance. This is
## the whole point of the equipment the district sells.
func _dress_for_the_week(adapter: Object, counters: Dictionary) -> bool:
	if _money(adapter) < GEAR_RESERVE:
		return false
	var missing: Array[String] = []
	for item_id: String in WEEK_GEAR:
		if _carried(adapter, item_id) <= 0 and not _wearing(adapter, item_id):
			missing.append(item_id)
	if missing.is_empty():
		return false
	if not _buy_from(adapter, counters, STATION, COMMISSION_STORE, missing):
		return false
	counters["gear"] = int(counters["gear"]) + 1
	return true


## Anything bought to be worn is worn, or it is dead weight in the pack.
func _wear_what_is_carried(adapter: Object, counters: Dictionary) -> bool:
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		if String(stack.get("container_id", "")) == "equipped":
			continue
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		if String(definition.equip_slot()).is_empty():
			continue
		if bool(adapter.perform_inventory_action(
			String(stack.get("stack_id", "")),
			"equip"
		).get("ok", false)):
			counters["equipped"] = int(counters["equipped"]) + 1
			return true
	return false


func _wearing(adapter: Object, item_id: String) -> bool:
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		if (
			String(stack.get("item_id", "")) == item_id
			and String(stack.get("container_id", "")) == "equipped"
		):
			return true
	return false


## One counter, one shop, one list of things worth carrying home.
func _buy_from(
	adapter: Object,
	counters: Dictionary,
	location_id: String,
	store_id: String,
	wanted: Array
) -> bool:
	if _money(adapter) <= 0:
		return false
	if not _go_to(adapter, location_id):
		return false
	var store: Dictionary = adapter.get_store_model(store_id)
	if not bool(store.get("ok", false)) or not bool(store.get("open", false)):
		return false
	for item_id: Variant in wanted:
		for raw_offer: Variant in Array(store.get("offers", [])):
			if not raw_offer is Dictionary:
				continue
			var offer: Dictionary = raw_offer
			if String(offer.get("item_id", "")) != String(item_id):
				continue
			if int(offer.get("unit_price", 0)) > _money(adapter):
				continue
			if bool(adapter.buy_store_offer(
				store_id,
				String(offer.get("offer_id", "")),
				1,
				"pockets",
				int(store.get("revision", 0))
			).get("ok", false)):
				counters["purchases"] = int(counters["purchases"]) + 1
				return true
	return false


func _use_carried(adapter: Object, item_id: String) -> bool:
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		if String(stack.get("item_id", "")) != item_id:
			continue
		return bool(adapter.perform_inventory_action(
			String(stack.get("stack_id", "")),
			"use"
		).get("ok", false))
	return false


## Hunger is answered properly or not at all: a single meal on a day that costs
## seventy points of it only postpones the same problem by three hours.
func _feed_if_hungry(adapter: Object, counters: Dictionary) -> bool:
	if _meter(adapter, "hunger") < HUNGRY:
		return false
	var before := _meter(adapter, "hunger")
	_eat_down_to(adapter, counters, NIGHT_HUNGER_FLOOR)
	return _meter(adapter, "hunger") < before


## Food is eaten from the pack, wherever the hero happens to be — the market
## action is a convenience, not the only way a person opens a tin.
func _eat_carried_food(adapter: Object, counters: Dictionary) -> bool:
	var stack_id := _food_stack_id(adapter)
	if stack_id.is_empty():
		return false
	if not bool(adapter.perform_inventory_action(stack_id, "use").get("ok", false)):
		return false
	counters["meals"] = int(counters["meals"]) + 1
	return true


## Eats the most filling thing in the pack first.
func _food_stack_id(adapter: Object) -> String:
	var best := ""
	var best_relief := 0
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		var item_id := String(stack.get("item_id", ""))
		if item_id not in FOOD_ITEMS:
			continue
		var relief := _hunger_relief(item_id)
		if best.is_empty() or relief > best_relief:
			best = String(stack.get("stack_id", ""))
			best_relief = relief
	return best


## Keeps a day's meals in the pack whenever the shop and the wallet allow it.
func _stock_food(adapter: Object, counters: Dictionary) -> bool:
	if _carried_food(adapter) >= FOOD_STOCK or _money(adapter) < FOOD_RESERVE:
		return false
	if String(adapter.get_location_id()) != MARKET:
		return false
	return _buy_food(adapter, counters)


func _carried_food(adapter: Object) -> int:
	var total := 0
	for item_id: String in FOOD_ITEMS:
		total += _carried(adapter, item_id)
	return total


## Buys the best hunger for the money that is actually on the shelf today.
func _buy_food(adapter: Object, counters: Dictionary) -> bool:
	if _money(adapter) <= 0 or _carried_food(adapter) >= FOOD_STOCK:
		return false
	if not _go_to(adapter, MARKET):
		return false
	var store: Dictionary = adapter.get_store_model(MARKET_STORE)
	if not bool(store.get("ok", false)) or not bool(store.get("open", false)):
		return false
	var wallet := _money(adapter)
	var best: Dictionary = {}
	var best_value := 0
	for raw_offer: Variant in Array(store.get("offers", [])):
		if not raw_offer is Dictionary:
			continue
		var offer: Dictionary = raw_offer
		if String(offer.get("item_id", "")) not in FOOD_ITEMS:
			continue
		var price := maxi(int(offer.get("unit_price", 0)), 1)
		if price > wallet:
			continue
		# Hunger removed per hundred arden, so the comparison stays in integers.
		var value := _hunger_relief(String(offer.get("item_id", ""))) * 100 / price
		if best.is_empty() or value > best_value:
			best = offer
			best_value = value
	if best.is_empty():
		return false
	if not bool(adapter.buy_store_offer(
		MARKET_STORE,
		String(best.get("offer_id", "")),
		1,
		"pockets",
		int(store.get("revision", 0))
	).get("ok", false)):
		return false
	counters["purchases"] = int(counters["purchases"]) + 1
	return true


## Reads what the food is worth from the item itself, so the driver cannot
## drift away from the catalogue it is supposed to be playing.
func _hunger_relief(item_id: String) -> int:
	var definition: Variant = ItemCatalog.definition(item_id)
	for raw_effect: Variant in Array(definition.action("use").get("effects", [])):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if String(effect.get("id", "")) == "hunger":
			return absi(int(effect.get("delta", 0)))
	return 0


## Picks the longest thing worth doing here. A day spent in ten-minute slices is
## the same day as one spent in twenty-minute ones, only twice as many commands.
func _perform_kind(
	adapter: Object,
	kind: String,
	counters: Dictionary,
	category_id: String = ""
) -> bool:
	var best: Dictionary = {}
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		if String(action.get("kind", "")) != kind or not bool(action.get("available", false)):
			continue
		if not category_id.is_empty() and String(action.get("category_id", "")) != category_id:
			continue
		if int(action.get("minutes", 0)) <= 0:
			continue
		if best.is_empty() or int(action.get("minutes", 0)) > int(best.get("minutes", 0)):
			best = action
	if best.is_empty():
		return false
	if not bool(adapter.perform_location_action(String(best.get("id", ""))).get("ok", false)):
		return false
	counters["local_actions"] = int(counters["local_actions"]) + 1
	return true


## Nothing worthwhile is offered here: do whatever the place allows, or walk on.
## Walking costs the clock exactly what walking costs a person.
func _pass_time(adapter: Object, counters: Dictionary) -> bool:
	if _perform_kind(adapter, "local", counters):
		return true
	for raw_route: Variant in Array(adapter.get_city_map_model().get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var moved: Dictionary = adapter.travel(
			String(route.get("destination_id", "")),
			String(route.get("mode", "walk"))
		)
		if bool(moved.get("ok", false)):
			counters["travels"] = int(counters["travels"]) + 1
			return true
	return false


func _sleep_somewhere(adapter: Object, counters: Dictionary) -> void:
	for _attempt: int in 8:
		if adapter.get_phase() == "completed":
			return
		var shelter_id := _available_shelter(adapter)
		if not shelter_id.is_empty():
			var slept: Dictionary = adapter.choose_shelter(shelter_id)
			if bool(slept.get("ok", false)):
				counters["nights"] = int(counters["nights"]) + 1
				return
			if String(slept.get("code", "")) == "already_slept_today":
				return
		# Nowhere to sleep here: walk to the free niche rather than wander.
		if String(adapter.get_location_id()) != SHELTER_FALLBACK:
			if _go_to(adapter, SHELTER_FALLBACK):
				continue
		if not _pass_time(adapter, counters):
			return


## The cheapest bed is not always the right one: when the week can afford a
## sheltered night, a hero takes it rather than paying for it in health.
func _available_shelter(adapter: Object) -> String:
	var wallet := _money(adapter)
	var comfortable := wallet >= ROOM_RESERVE
	var best := ""
	var best_rank := -1
	for raw_option: Variant in adapter.available_shelters():
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		if bool(option.get("locked", true)):
			continue
		var price := int(option.get("price_arden", 0))
		if price > wallet:
			continue
		# Comfort is worth paying for only while there is money to spare.
		var rank := int(option.get("quality", 1)) if comfortable else (100 - price)
		if best.is_empty() or rank > best_rank:
			best = String(option.get("id", ""))
			best_rank = rank
	return best


# --- shift comparison -------------------------------------------------------


func _quick_resolve_offered(adapter: Object) -> bool:
	if not adapter.is_job_shift_active():
		return false
	return bool(
		Dictionary(adapter.get_job_shift_model().get("quick_resolve", {})).get("visible", false)
	)


func _finish_shift_manually(adapter: Object) -> Dictionary:
	var last: Dictionary = {}
	var guard := 0
	while adapter.is_job_shift_active() and guard < 12:
		guard += 1
		var step := _current_shift_step(adapter)
		if step.is_empty():
			break
		var choices: Array = Array(step.get("choices", []))
		if choices.is_empty():
			return {"ok": false, "reason": "no choices"}
		last = adapter.resolve_job_shift_step(String(Dictionary(choices[0]).get("id", "")))
		if not bool(last.get("ok", false)):
			return {"ok": false, "cause": last}
		if bool(last.get("completed", false)):
			break
	return _shift_outcome(adapter, last, false, true)


## The shortcut skips routine, not decisions. A shift whose next step is the
## decision has no routine to skip yet, so the player answers it and skips what
## follows — refusing there is the domain being right, not a defect.
func _finish_shift_quickly(adapter: Object) -> Dictionary:
	var last: Dictionary = {}
	var decided := false
	var used_quick := false
	var guard := 0
	while adapter.is_job_shift_active() and guard < 16:
		guard += 1
		var step := _current_shift_step(adapter)
		if step.is_empty():
			break
		if String(step.get("kind", "task")) != "decision":
			var quick: Dictionary = adapter.quick_resolve_job_shift()
			if bool(quick.get("ok", false)):
				used_quick = true
				last = quick
				if bool(quick.get("completed", false)):
					break
				continue
		var choices: Array = Array(step.get("choices", []))
		if choices.is_empty():
			return {"ok": false, "reason": "no choices"}
		decided = true
		last = adapter.resolve_job_shift_step(String(Dictionary(choices[0]).get("id", "")))
		if not bool(last.get("ok", false)):
			return {"ok": false, "cause": last}
		if bool(last.get("completed", false)):
			break
	if not used_quick:
		return {"ok": false, "reason": "the shortcut was never available"}
	return _shift_outcome(adapter, last, true, decided)


func _shift_outcome(
	adapter: Object,
	last: Dictionary,
	used_quick: bool,
	decided: bool
) -> Dictionary:
	var result: Dictionary = Dictionary(last.get("result", {}))
	return {
		"ok": not result.is_empty(),
		"overall": int(result.get("overall", 0)),
		"money": _money(adapter),
		"used_quick": used_quick,
		"decided": decided,
	}


func _current_shift_step(adapter: Object) -> Dictionary:
	return Dictionary(adapter.get_job_shift_model().get("current_step", {}))


# --- observation ------------------------------------------------------------


## Built only from public read models, so the digest can never see a value the
## player could not.
func _digest(adapter: Object) -> String:
	var summary: Dictionary = adapter.get_summary_model()
	var status: Dictionary = Dictionary(summary.get("status", {}))
	var lifecycle: Dictionary = Dictionary(summary.get("lifecycle", {}))
	var hero: Dictionary = adapter.get_hero_model()
	var parts := PackedStringArray([
		"loc=%s" % String(summary.get("base_location_id", "")),
		"phase=%s" % String(summary.get("phase", "")),
		"status=%s" % String(lifecycle.get("status", "")),
		"elapsed=%d" % int(lifecycle.get("processed_elapsed_minutes", 0)),
		"money=%d" % int(status.get("money", 0)),
		"meters=%s" % _sorted_pairs(Dictionary(status.get("meters", {}))),
		"skills=%s" % _sorted_pairs(Dictionary(hero.get("skills", {}))),
		"mastery=%d" % int(hero.get("mastery_points", 0)),
		"items=%d" % _carried_total(adapter),
		"biography=%d" % Array(summary.get("biography", [])).size(),
	])
	return "|".join(parts)


func _activity_signature(counters: Dictionary) -> String:
	var keys: Array = counters.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key: Variant in keys:
		if String(key) == "earned_ard":
			continue
		parts.append("%s=%d" % [String(key), int(counters[key])])
	return ";".join(parts)


func _sorted_pairs(source: Dictionary) -> String:
	var keys: Array = source.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key: Variant in keys:
		parts.append("%s:%s" % [String(key), str(source[key])])
	return ",".join(parts)


## The adapter hands out the inventory as the domain holds it, so the driver
## reads it with the same query the screens use rather than inventing a shape.
func _carried_stacks(adapter: Object) -> Array:
	var model: Dictionary = adapter.get_inventory_model()
	var inventory: Dictionary = Dictionary(model.get("inventory", {}))
	var result: Array = []
	for raw_stack: Variant in InventoryState.all_stacks(inventory):
		if raw_stack is Dictionary and not bool(Dictionary(raw_stack).get("external", false)):
			result.append(raw_stack)
	return result


func _carried_total(adapter: Object) -> int:
	var total := 0
	for raw_stack: Variant in _carried_stacks(adapter):
		total += int(Dictionary(raw_stack).get("quantity", 0))
	return total


func _carried(adapter: Object, item_id: String) -> int:
	var total := 0
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		if String(stack.get("item_id", "")) == item_id:
			total += int(stack.get("quantity", 0))
	return total


func _carried_recyclables(adapter: Object) -> int:
	var total := 0
	for raw_stack: Variant in _carried_stacks(adapter):
		var stack: Dictionary = raw_stack
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		if "recyclable" in definition.tags():
			total += int(stack.get("quantity", 0))
	return total


## The status block answers money, needs and the clock at once. Building it
## three times for three questions is what made a played week take minutes.
func _status(adapter: Object) -> Dictionary:
	return Dictionary(adapter.get_summary_model().get("status", {}))


func _money(adapter: Object) -> int:
	return int(_status(adapter).get("money", 0))


func _meter(adapter: Object, meter_id: String) -> int:
	return int(Dictionary(_status(adapter).get("meters", {})).get(meter_id, 0))


func _minute_of_day(adapter: Object) -> int:
	return int(Dictionary(_status(adapter).get("calendar", {})).get("minute_of_day", 0))


func _find_action(adapter: Object, kind: String) -> Dictionary:
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		if String(action.get("kind", "")) == kind and bool(action.get("available", false)):
			return action.duplicate(true)
	return {}


func _find_action_by_id(adapter: Object, action_id: String) -> Dictionary:
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if raw_action is Dictionary and String(Dictionary(raw_action).get("id", "")) == action_id:
			return Dictionary(raw_action).duplicate(true)
	return {}


## Walks to a place using only the routes the map offers from where the hero
## actually stands.
## Walks the map graph properly. The greedy version stepped onto whichever
## route came first and could wander between two neighbours for a whole day,
## which cost the hero the shift he set out for.
func _go_to(adapter: Object, destination: String) -> bool:
	for _hop: int in 6:
		var here := String(adapter.get_location_id())
		if here == destination:
			return true
		var next_stop := _first_step_towards(adapter, here, destination)
		if next_stop.is_empty():
			return false
		var mode := "walk"
		for raw_route: Variant in Array(adapter.get_city_map_model().get("routes", [])):
			var route: Dictionary = raw_route
			if String(route.get("destination_id", "")) == next_stop:
				mode = String(route.get("mode", "walk"))
				break
		if not bool(adapter.travel(next_stop, mode).get("ok", false)):
			return false
	return String(adapter.get_location_id()) == destination


## Breadth-first over the district, returning the neighbour to leave by.
func _first_step_towards(adapter: Object, origin: String, destination: String) -> String:
	var neighbours := _district_graph(adapter)
	if not neighbours.has(origin):
		return ""
	var queue: Array[String] = [origin]
	var came_from: Dictionary = {origin: ""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == destination:
			var step := current
			while String(came_from[step]) != origin and not String(came_from[step]).is_empty():
				step = String(came_from[step])
			return step
		for raw_next: Variant in Array(neighbours.get(current, [])):
			var next_id := String(raw_next)
			if came_from.has(next_id):
				continue
			came_from[next_id] = current
			queue.append(next_id)
	return ""


func _district_graph(adapter: Object) -> Dictionary:
	var graph: Dictionary = {}
	var model: Dictionary = adapter.get_city_map_model()
	for raw_location: Variant in Array(model.get("locations", [])):
		graph[String(Dictionary(raw_location).get("id", ""))] = []
	# The map read-model only exposes routes out of the current place, so the
	# graph is completed from the authored district instead.
	var content = load("res://game/first_day/first_day_content.gd")
	for location_id: String in Dictionary(content.locations()):
		var place: Dictionary = Dictionary(content.locations())[location_id]
		var exits: Array[String] = []
		for raw_route: Variant in Array(place.get("routes", [])):
			exits.append(String(Dictionary(raw_route).get("destination_id", "")))
		graph[location_id] = exits
	return graph


func _fresh_counters() -> Dictionary:
	return {
		"shifts": 0,
		"sales": 0,
		"searches": 0,
		"talks": 0,
		"purchases": 0,
		"meals": 0,
		"treatments": 0,
		"gear": 0,
		"equipped": 0,
		"local_actions": 0,
		"travels": 0,
		"nights": 0,
		"earned_ard": 0,
	}


func _reopen(path: String) -> Object:
	var result: Dictionary = SandboxAdapter.load_session(path)
	_expect(bool(result.get("ok", false)), "comparison save must reopen: %s" % str(result))
	return result.get("adapter") if bool(result.get("ok", false)) else null


func _save_path(label: String) -> String:
	return "user://m3f7_acceptance_%s.json" % label


func _cleanup_saves() -> void:
	for label: String in ["midweek", "quick"]:
		for suffix: String in ["", ".tmp", ".bak"]:
			var path := _save_path(label) + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A played week takes minutes, so a failure is reported the moment it happens
## rather than at the end of the run: waiting for the summary to learn why the
## first day went wrong wastes the whole run.
func _fail(message: String) -> void:
	var line := "%s — %s" % [_current, message]
	_failures.append(line)
	printerr("FAILURE: %s" % line)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
