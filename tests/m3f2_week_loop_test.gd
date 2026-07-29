extends SceneTree

const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const SurvivalStateScript := preload("res://game/survival/survival_state.gd")

const DEFAULT_BUILD := {
	"strength": 5,
	"charisma": 4,
	"intelligence": 4,
	"luck": 5,
}

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("location and store reads keep time and state still", _test_pure_reads)
	_run("purchase atomically persists one stable stock snapshot", _test_purchase_and_reopen)
	_run("recyclables become arden through the sandbox adapter", _test_recycling_sale)
	_run("sleep crosses the calendar date only after confirmation", _test_sleep_crosses_date)
	_run("the recycling minigame becomes available again next day", _test_daily_job_reset)
	_run("deprivation ends a run and a new adapter starts immediately", _test_death_and_restart)
	_run("the exact seven-day boundary completes the prototype week", _test_week_complete)
	_run("extreme builds expose distinct starts and explicit gates", _test_extreme_builds)
	if _failures.is_empty():
		print("M3F.2 WEEK LOOP TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.2 WEEK LOOP TESTS FAILED: %d failure(s) across %d test(s)" % [
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


func _test_pure_reads() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_001)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "clinic_yard")
	var before: Dictionary = session.to_dict()
	var first_location: Dictionary = adapter.get_location_model()
	var second_location: Dictionary = adapter.get_location_model()
	var first_store: Dictionary = adapter.get_store_model(
		"store_clinic_pharmacy_window"
	)
	var second_store: Dictionary = adapter.get_store_model(
		"store_clinic_pharmacy_window"
	)
	_expect(not first_location.is_empty(), "location read-model must exist")
	_expect_equal(second_location, first_location, "location reopening must be stable")
	_expect(bool(first_store.get("ok", false)), "store preview must resolve")
	_expect_equal(second_store, first_store, "unconfirmed stock preview must be deterministic")
	_expect(not bool(first_store.get("snapshot_persisted", true)), "preview must remain unpersisted")
	_expect(session.world_state.stock_snapshots.is_empty(), "reading stock must not write WorldState")
	_expect_equal(session.to_dict(), before, "all reads must leave the complete session unchanged")


func _test_purchase_and_reopen() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_002)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "clinic_yard")
	_expect(session.run_state.set_money(1_000), "money fixture must be valid")
	var store: Dictionary = adapter.get_store_model("store_clinic_pharmacy_window")
	_expect(bool(store.get("ok", false)), "pharmacy preview must resolve")
	_expect(bool(store.get("open", false)), "pharmacy must be open at the first 08:00")
	var offer := _cheapest_offer(Array(store.get("offers", [])))
	_expect(not offer.is_empty(), "pharmacy must have a purchasable offer")
	if offer.is_empty():
		return
	var before_failure: Dictionary = session.to_dict()
	var stale: Dictionary = adapter.buy_store_offer(
		"store_clinic_pharmacy_window",
		String(offer.get("offer_id", "")),
		1,
		"pockets",
		int(store.get("revision", 0)) + 1
	)
	_expect_equal(stale.get("code"), "stock_conflict", "stale preview must fail explicitly")
	_expect_equal(session.to_dict(), before_failure, "failed purchase must be fully atomic")

	var money_before: int = session.run_state.money
	var time_before: int = session.run_state.calendar.elapsed_minutes
	var item_before: int = session.run_state.get_item_count(String(offer.get("item_id", "")))
	var bought: Dictionary = adapter.buy_store_offer(
		"store_clinic_pharmacy_window",
		String(offer.get("offer_id", "")),
		1,
		"pockets",
		int(store.get("revision", 0))
	)
	_expect(bool(bought.get("ok", false)), "purchase must commit: %s" % str(bought))
	if not bool(bought.get("ok", false)):
		return
	var receipt: Dictionary = bought.get("receipt", {})
	_expect_equal(
		session.run_state.money,
		money_before - int(receipt.get("total_price", 0)),
		"money and receipt must agree"
	)
	_expect_equal(
		session.run_state.get_item_count(String(offer.get("item_id", ""))),
		item_before + 1,
		"purchased item must enter inventory"
	)
	_expect_equal(session.run_state.calendar.elapsed_minutes, time_before + 5, "purchase must spend five minutes")
	_expect_equal(
		session.survival_state.processed_elapsed_minutes,
		session.run_state.calendar.elapsed_minutes,
		"purchase time must pass through survival"
	)
	var reopened: Dictionary = adapter.get_store_model("store_clinic_pharmacy_window")
	var reopened_again: Dictionary = adapter.get_store_model("store_clinic_pharmacy_window")
	_expect(bool(reopened.get("snapshot_persisted", false)), "confirmed purchase must persist stock")
	_expect_equal(reopened_again, reopened, "reopening persisted stock must not reroll it")
	_expect_equal(
		reopened.get("snapshot"),
		Dictionary(bought.get("store", {})).get("snapshot"),
		"purchase result and reopened store must share one snapshot"
	)
	var after_reopen: Dictionary = session.to_dict()
	adapter.get_store_model("store_clinic_pharmacy_window")
	_expect_equal(session.to_dict(), after_reopen, "reopening persisted stock must be read-only")


func _test_recycling_sale() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_003)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "recycling_point")
	_expect(session.run_state.add_item("copper_scrap", 2, "pockets"), "recyclable fixture must fit")
	var offers: Array[Dictionary] = adapter.get_recycling_offers()
	_expect_equal(offers.size(), 1, "adapter must expose the carried recyclable")
	if offers.is_empty():
		return
	var offer: Dictionary = offers[0]
	var money_before: int = session.run_state.money
	var time_before: int = session.run_state.calendar.elapsed_minutes
	var sold: Dictionary = adapter.perform_inventory_action(
		String(offer.get("stack_id", "")), "sell", 1
	)
	_expect(bool(sold.get("ok", false)), "recycling sale must commit: %s" % str(sold))
	_expect_equal(session.run_state.get_item_count("copper_scrap"), 1, "only selected quantity is sold")
	_expect_equal(
		session.run_state.money,
		money_before + int(Dictionary(sold.get("receipt", {})).get("payout", 0)),
		"payout must reach the same session"
	)
	_expect_equal(session.run_state.calendar.elapsed_minutes, time_before + 8, "one item takes eight minutes")


func _test_sleep_crosses_date() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_004)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "underpass")
	_expect(_advance_fixture(session, 10 * 60), "fixture must reach 18:00 without desynchronizing")
	var before: Dictionary = session.run_state.calendar.current_stamp()
	var options: Array = adapter.available_shelters()
	var option := _find_by_id(options, "shelter_underpass_niche", "id")
	_expect(not option.is_empty() and not bool(option.get("locked", true)), "underpass niche must be available at 18:00")
	var slept: Dictionary = adapter.choose_shelter("shelter_underpass_niche")
	_expect(bool(slept.get("ok", false)), "sleep must commit: %s" % str(slept))
	if not bool(slept.get("ok", false)):
		return
	var after: Dictionary = session.run_state.calendar.current_stamp()
	_expect(int(after.get("day", 0)) != int(before.get("day", 0)), "confirmed sleep must cross the date")
	_expect_equal(after.get("minute_of_day"), 390, "niche wake-up must be 06:30")
	_expect_equal(
		session.survival_state.processed_elapsed_minutes,
		session.run_state.calendar.elapsed_minutes,
		"sleep must keep survival synchronized"
	)


func _test_daily_job_reset() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_040)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "recycling_point")
	_expect(_advance_fixture(session, 60), "fixture must reach the opening of the yard")
	var started: Dictionary = adapter.begin_job_shift()
	_expect(bool(started.get("ok", false)), "first shift must start: %s" % str(started))
	if not bool(started.get("ok", false)):
		return
	_expect(_work_shift_to_the_end(adapter), "the whole shift must resolve")
	var same_day: Dictionary = adapter.begin_job_shift()
	_expect(not bool(same_day.get("ok", false)), "one shift per day must be enforced")
	_expect(_advance_fixture(session, 1440), "fixture must reach the next day")
	var next_day: Dictionary = adapter.begin_job_shift()
	_expect(bool(next_day.get("ok", false)), "the shift must reopen on the next day: %s" % str(next_day))


func _work_shift_to_the_end(adapter: Object) -> bool:
	for _step: int in 12:
		var model: Dictionary = adapter.get_job_shift_model()
		var step: Dictionary = Dictionary(model.get("current_step", {}))
		if step.is_empty():
			return true
		var choices: Array = Array(step.get("choices", []))
		if choices.is_empty():
			return false
		var resolved: Dictionary = adapter.resolve_job_shift_step(String(
			Dictionary(choices[0]).get("id", "")
		))
		if not bool(resolved.get("ok", false)):
			return false
		if bool(resolved.get("completed", false)):
			return true
	return false


func _test_death_and_restart() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_005)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "embankment")
	session.run_state.set_meter("health", 1)
	session.run_state.set_meter("hunger", 100)
	session.run_state.set_meter("energy", 15)
	var result: Dictionary = adapter.perform_location_action(
		"action_embankment_walk_waterfront"
	)
	_expect(bool(result.get("ok", false)), "fatal confirmed action must still commit its consumed time")
	_expect_equal(session.survival_state.status, "dead", "deprivation must end the current run")
	_expect_equal(adapter.get_phase(), "completed", "adapter must expose terminal lifecycle")

	var replacement = SandboxAdapter.create(DEFAULT_BUILD, 93_006)
	_expect(replacement != null, "a new adapter must be created without restarting the app")
	if replacement == null:
		return
	var fresh = _session(replacement)
	_expect(replacement.is_valid(), "replacement run must validate")
	_expect_equal(fresh.survival_state.status, "active", "replacement lifecycle must be active")
	_expect_equal(fresh.run_state.calendar.elapsed_minutes, 0, "replacement run must start at its own zero")
	_expect_equal(replacement.get_phase(), "map", "new sandbox run returns directly to a location")


func _test_week_complete() -> void:
	var adapter = _adapter(DEFAULT_BUILD, 93_007)
	if adapter == null:
		return
	var session = _session(adapter)
	_place(session, "clinic_yard")
	# A run lasts far longer than a week now; this check is about what happens on
	# a horizon, so it gives the session one it can reach inside a test.
	session.survival_state.horizon_minutes = SurvivalStateScript.WEEK_MINUTES
	var almost_week := SurvivalStateScript.WEEK_MINUTES - 10
	_expect(_advance_fixture(session, almost_week), "fixture must reach ten minutes before week end")
	session.run_state.set_meter("health", 100)
	session.run_state.set_meter("hunger", 0)
	session.run_state.set_meter("energy", 90)
	var result: Dictionary = adapter.perform_location_action("action_clinic_rest_bench")
	_expect(bool(result.get("ok", false)), "final confirmed action must commit: %s" % str(result))
	_expect_equal(session.survival_state.status, "week_complete", "the exact horizon must end the run")
	_expect_equal(
		session.run_state.calendar.elapsed_minutes,
		SurvivalStateScript.WEEK_MINUTES,
		"the calendar must stop exactly on the horizon"
	)
	_expect_equal(adapter.get_phase(), "completed", "the adapter must expose a finished run")


func _test_extreme_builds() -> void:
	var builds := [
		{"strength": 10, "charisma": 1, "intelligence": 1, "luck": 6},
		{"strength": 1, "charisma": 10, "intelligence": 6, "luck": 1},
		{"strength": 1, "charisma": 1, "intelligence": 6, "luck": 10},
	]
	var expected_starts := ["underpass", "station_square", "market"]
	var adapters: Array = []
	var signatures: Array[String] = []
	for index: int in builds.size():
		var adapter = _adapter(builds[index], 3)
		if adapter == null:
			return
		adapters.append(adapter)
		adapter.set_setting("show_locked_options", true)
		_expect_equal(adapter.get_location_id(), expected_starts[index], "seeded extreme start must remain reproducible")
		signatures.append(_action_signature(adapter.get_location_model()))
	_expect(signatures[0] != signatures[1] and signatures[0] != signatures[2] and signatures[1] != signatures[2], "three extreme builds must expose distinct action sets")

	for adapter in adapters:
		_place(_session(adapter), "recycling_point")
	var strong_action := _find_by_id(
		adapters[0].get_location_model().get("actions", []),
		"action_recycling_move_bundle"
	)
	var charismatic_action := _find_by_id(
		adapters[1].get_location_model().get("actions", []),
		"action_recycling_move_bundle"
	)
	var lucky_action := _find_by_id(
		adapters[2].get_location_model().get("actions", []),
		"action_recycling_move_bundle"
	)
	_expect(bool(strong_action.get("available", false)), "Strength 10 must open the heavy bundle")
	_expect(not bool(charismatic_action.get("available", true)), "Charisma build must see the strength gate")
	_expect(not bool(lucky_action.get("available", true)), "Luck build must see the strength gate")
	_expect(not Array(charismatic_action.get("reasons", [])).is_empty(), "blocked action must explain its requirement")


func _adapter(build: Dictionary, seed: int) -> Object:
	var adapter = SandboxAdapter.create(build, seed)
	_expect(adapter != null, "sandbox adapter must be created")
	if adapter != null:
		_expect(adapter.is_valid(), "new sandbox adapter must validate")
	return adapter


func _session(adapter: Object) -> Object:
	return adapter.get("_session") as Object if adapter != null else null


func _place(session: Object, location_id: String) -> void:
	session.set("location", location_id)
	session.set("phase", "map")
	session.set("current_event", "")


func _advance_fixture(session: Object, minutes: int) -> bool:
	if not session.run_state.calendar.advance_minutes(minutes):
		return false
	session.survival_state.processed_elapsed_minutes += minutes
	return bool(session.validate().get("ok", false))


func _cheapest_offer(raw_offers: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_offer: Variant in raw_offers:
		if not raw_offer is Dictionary:
			continue
		var offer: Dictionary = raw_offer
		if result.is_empty() or int(offer.get("unit_price", 0)) < int(result.get("unit_price", 0)):
			result = offer.duplicate(true)
	return result


func _find_by_id(raw_entries: Variant, identifier: String, field: String = "id") -> Dictionary:
	for raw_entry: Variant in Array(raw_entries):
		if raw_entry is Dictionary and String(raw_entry.get(field, "")) == identifier:
			return Dictionary(raw_entry).duplicate(true)
	return {}


func _action_signature(model: Dictionary) -> String:
	var parts: Array[String] = [String(model.get("id", ""))]
	for raw_action: Variant in Array(model.get("actions", [])):
		if raw_action is Dictionary:
			parts.append("%s:%s" % [
				String(raw_action.get("id", "")),
				str(bool(raw_action.get("available", false))),
			])
	return "|".join(parts)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current, message, str(expected), str(actual),
		])
