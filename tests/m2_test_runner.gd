extends SceneTree

const FirstDayContentScript = preload("res://game/first_day/first_day_content.gd")
const FirstDaySessionScript = preload("res://game/first_day/first_day_session.gd")
const FirstDaySaveScript = preload("res://game/first_day/first_day_save.gd")
const SessionCommandTransactionScript = preload("res://game/session/session_command_transaction.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _save_prefix := ".m2_integration_test_%d_%d_" % [OS.get_process_id(), Time.get_ticks_usec()]


func _init() -> void:
	_run_test("catalog counts and unconditional exits", _test_catalog_counts_and_unconditional_exits)
	_run_test("deterministic seed", _test_deterministic_seed)
	_run_test("Luck start distribution and valid runs", _test_luck_start_distribution)
	_run_test("contrasting builds expose different answers", _test_contrasting_builds)
	_run_test("hidden and shown locked policy", _test_locked_option_policy)
	_run_test("reading is timeless and travel advances time", _test_discrete_time)
	_run_test("due consequences resolve atomically", _test_due_consequences)
	_run_test("shelter window and nearest 08:00", _test_shelter_window)
	_run_test("Luck biases event adversity", _test_luck_event_weights)
	_run_test("session semantic validation", _test_session_semantic_validation)
	_run_test("temporary and backup recovery", _test_recovery_candidates)
	_run_test("three complete first days", _test_three_complete_runs)
	_run_test("save round-trip at map and event", _test_phase_round_trips)
	_run_test("psyche setting is presentation-only", _test_psyche_setting)
	_cleanup_all_test_saves()

	if _failures.is_empty():
		print("M2 TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M2 TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var failures_before := _failures.size()
	test_method.call()
	if _failures.size() == failures_before:
		print("PASS: %s" % test_name)
	else:
		print("FAIL: %s" % test_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if not _values_equal(actual, expected):
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current_test, message, str(expected), str(actual)])


func _values_equal(actual: Variant, expected: Variant) -> bool:
	var actual_type: int = typeof(actual)
	var expected_type: int = typeof(expected)
	if actual_type in [TYPE_INT, TYPE_FLOAT] and expected_type in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(actual), float(expected))
	if actual_type != expected_type:
		return false
	if actual_type == TYPE_DICTIONARY:
		var actual_dictionary: Dictionary = actual
		var expected_dictionary: Dictionary = expected
		if actual_dictionary.size() != expected_dictionary.size():
			return false
		for key in expected_dictionary:
			if not actual_dictionary.has(key) or not _values_equal(actual_dictionary[key], expected_dictionary[key]):
				return false
		return true
	if actual_type == TYPE_ARRAY:
		var actual_array: Array = actual
		var expected_array: Array = expected
		if actual_array.size() != expected_array.size():
			return false
		for index in range(expected_array.size()):
			if not _values_equal(actual_array[index], expected_array[index]):
				return false
		return true
	return actual == expected


func _test_catalog_counts_and_unconditional_exits() -> void:
	var validation: Dictionary = FirstDayContentScript.validate_content()
	_expect(bool(validation.get("ok", false)), "catalog validation must pass: %s" % str(validation.get("errors", [])))
	var counts: Dictionary = validation.get("counts", {})
	_expect_equal(int(counts.get("locations", -1)), 6, "catalog must contain six locations")
	_expect_equal(int(counts.get("starts", -1)), 4, "catalog must contain four starts")
	_expect_equal(int(counts.get("event_families", -1)), 13, "catalog must contain thirteen event families")
	_expect_equal(int(counts.get("event_cards", -1)), 22, "catalog must contain twenty-two event cards")
	_expect_equal(int(counts.get("event_choices", -1)), 62, "catalog must contain sixty-two event choices")
	_expect_equal(int(counts.get("deferred_effects", -1)), 10, "catalog must contain ten deferred effects")
	_expect_equal(int(counts.get("job_prompts", -1)), 6, "job must contain six prompts")
	_expect_equal(int(counts.get("shelters", -1)), 4, "catalog must contain four shelters")

	var cards: Dictionary = FirstDayContentScript.event_cards()
	for card_id in cards:
		var card: Dictionary = cards[card_id]
		var choices: Array = card.get("choices", [])
		var has_unconditional := false
		for choice_value in choices:
			if choice_value is Dictionary and Array(choice_value.get("conditions", [])).is_empty():
				has_unconditional = true
				break
		_expect(has_unconditional, "card %s must have an unconditional exit" % String(card_id))


func _test_deterministic_seed() -> void:
	var build := _build_for_luck(5)
	var first = FirstDaySessionScript.create(build, 77_777)
	var second = FirstDaySessionScript.create(build, 77_777)
	_expect(first != null and second != null, "same-seed sessions must be created")
	if first == null or second == null:
		return
	_expect_equal(first.start, second.start, "same seed must select the same start")
	_expect_equal(first.location, second.location, "same seed must select the same start location")
	_expect_equal(first.current_event, second.current_event, "same seed must select the same opening event")
	_expect_equal(first.get_current_event_model(), second.get_current_event_model(), "same seed must expose the same opening model")
	var first_choice := _first_available_option(first.get_current_event_model())
	var second_choice := _first_available_option(second.get_current_event_model())
	_expect_equal(first_choice, second_choice, "same seed must choose the same public option")
	if not first_choice.is_empty():
		_expect(bool(first.resolve_choice(first_choice).get("ok", false)), "first deterministic choice must resolve")
		_expect(bool(second.resolve_choice(second_choice).get("ok", false)), "second deterministic choice must resolve")
		_expect_equal(first.to_dict(), second.to_dict(), "same decisions must leave identical sessions")


func _test_luck_start_distribution() -> void:
	var severities: Dictionary = {}
	for start_value in FirstDayContentScript.start_situations():
		if start_value is Dictionary:
			severities[String(start_value.get("id", ""))] = int(start_value.get("severity", 0))
	var low_total := 0
	var high_total := 0
	var sample_count := 240
	for seed in range(1, sample_count + 1):
		var low = FirstDaySessionScript.create(_build_for_luck(1), seed)
		var high = FirstDaySessionScript.create(_build_for_luck(10), seed)
		_expect(low != null and high != null, "sampled Luck runs must be valid")
		if low != null:
			low_total += int(severities.get(low.start, 0))
		if high != null:
			high_total += int(severities.get(high.start, 0))
	_expect(low_total > high_total, "low Luck must produce statistically harsher starts")
	_expect(float(low_total) / sample_count > float(high_total) / sample_count + 0.75, "Luck severity gap must be material")
	for luck in [1, 5, 10]:
		var session = FirstDaySessionScript.create(_build_for_luck(luck), 9000 + luck)
		_expect(session != null, "Luck %d must create a run" % luck)
		if session != null:
			_expect(bool(session.validate().get("ok", false)), "Luck %d run must validate" % luck)


func _test_contrasting_builds() -> void:
	var strong_build := {"strength": 10, "charisma": 6, "intelligence": 1, "luck": 1}
	var clever_build := {"strength": 1, "charisma": 6, "intelligence": 10, "luck": 1}
	var strong = _new_map_session(strong_build, 31_337)
	var clever = _new_map_session(clever_build, 31_337)
	_expect(strong != null and clever != null, "contrasting runs must reach the map")
	if strong == null or clever == null:
		return
	_expect_equal(strong.start, clever.start, "equal seed and Luck must keep start constant")
	_expect(_travel_to(strong, "market"), "strong run must reach the market")
	_expect(_travel_to(clever, "market"), "clever run must reach the market")
	var card_id := "market_unloading_offer"
	_expect(bool(strong.enter_event(card_id).get("ok", false)), "strong run must enter comparison event")
	_expect(bool(clever.enter_event(card_id).get("ok", false)), "clever run must enter comparison event")
	var strong_options := _option_ids(strong.get_current_event_model())
	var clever_options := _option_ids(clever.get_current_event_model())
	_expect(strong_options != clever_options, "contrasting characteristics must expose different answers")
	_expect("market_unloading_offer.lift" in strong_options, "high Strength must expose lifting answer")
	_expect("market_unloading_offer.lift" not in clever_options, "low Strength must hide lifting answer")
	_expect("market_unloading_offer.organize" in clever_options, "high Intelligence must expose organization answer")
	_expect("market_unloading_offer.organize" not in strong_options, "low Intelligence must hide organization answer")


func _test_locked_option_policy() -> void:
	var build := {"strength": 10, "charisma": 6, "intelligence": 1, "luck": 1}
	var session = _new_map_session(build, 55_001)
	_expect(session != null, "policy test run must reach map")
	if session == null:
		return
	_expect(_travel_to(session, "market"), "policy test run must reach market")
	_expect(bool(session.enter_event("market_unloading_offer").get("ok", false)), "policy test event must open")
	var hidden_model: Dictionary = session.get_current_event_model()
	var hidden_ids := _option_ids(hidden_model)
	var state_before: Dictionary = session.run_state.to_dict()
	_expect(session.set_setting("show_locked_options", true), "locked options setting must be accepted")
	var shown_model: Dictionary = session.get_current_event_model()
	var shown_ids := _option_ids(shown_model)
	_expect(shown_ids.size() > hidden_ids.size(), "shown policy must add locked answers")
	var locked_id := ""
	for option_value in Array(shown_model.get("options", [])):
		if option_value is Dictionary and bool(option_value.get("locked", false)):
			locked_id = String(option_value.get("id", ""))
			_expect(not Array(option_value.get("reasons", [])).is_empty(), "shown locked answer must explain why")
			break
	_expect(not locked_id.is_empty(), "shown model must contain a locked answer")
	if locked_id.is_empty():
		return
	var shown_attempt: Dictionary = session.resolve_choice(locked_id)
	_expect(not bool(shown_attempt.get("ok", false)), "shown locked answer must remain impossible")
	_expect_equal(session.run_state.to_dict(), state_before, "failed shown answer must not mutate RunState")
	_expect(session.set_setting("show_locked_options", false), "hidden policy must be restored")
	_expect(locked_id not in _option_ids(session.get_current_event_model()), "locked answer must be hidden again")
	var hidden_attempt: Dictionary = session.resolve_choice(locked_id)
	_expect(not bool(hidden_attempt.get("ok", false)), "hidden locked answer must remain impossible when invoked by id")
	_expect_equal(session.run_state.to_dict(), state_before, "visibility setting must never change action feasibility")


func _test_discrete_time() -> void:
	var session = _new_map_session(_build_for_luck(5), 4_204)
	_expect(session != null, "time test run must reach map")
	if session == null:
		return
	var before: int = int(session.run_state.calendar.elapsed_minutes)
	for _read in range(20):
		session.get_map_model()
		session.get_current_event_model()
		session.available_shelters()
		session.psyche_intensity()
	_expect_equal(session.run_state.calendar.elapsed_minutes, before, "reading public models must not advance time")
	var route := _first_available_route(session.get_map_model())
	_expect(not route.is_empty(), "map must expose an available route")
	if route.is_empty():
		return
	var result: Dictionary = session.travel(String(route["destination_id"]), String(route["mode"]))
	_expect(bool(result.get("ok", false)), "confirmed travel must succeed")
	_expect_equal(
		session.run_state.calendar.elapsed_minutes,
		before + int(route["minutes"]),
		"travel must advance exactly its displayed duration"
	)


func _test_due_consequences() -> void:
	var session = _new_map_session(_build_for_luck(5), 4_205)
	_expect(session != null, "due consequence run must reach map")
	if session == null:
		return
	var route := _first_available_route(session.get_map_model())
	_expect(not route.is_empty(), "due consequence run must expose a route")
	if route.is_empty():
		return
	var health_before: int = int(session.run_state.get_meter("health"))
	_expect(
		session.run_state.schedule_consequence_after(
			"test_due_health", 1, "cold_symptoms", {"health": -5}, "test"
		),
		"mechanical consequence must be scheduled"
	)
	_expect(
		session.run_state.schedule_consequence_after(
			"test_due_social", 1, "local_recognition", {"location_id": "underpass"}, "test"
		),
		"social consequence must be scheduled"
	)
	var travel_result: Dictionary = session.travel(String(route["destination_id"]), String(route["mode"]))
	_expect(bool(travel_result.get("ok", false)), "travel crossing due time must succeed")
	_expect_equal(session.run_state.get_meter("health"), maxi(health_before - 5, 0), "due health penalty must apply once")
	_expect(session.run_state.has_knowledge("local_recognition"), "social consequence must become persistent knowledge")
	_expect_equal(session.run_state.deferred_consequences.size(), 0, "resolved consequences must leave the queue")
	var due_journal_entries := 0
	for entry_value in session.run_state.journal:
		if not entry_value is Dictionary:
			continue
		var payload: Dictionary = entry_value.get("payload", {})
		if String(payload.get("action_id", "")).begins_with("deferred:"):
			due_journal_entries += 1
	_expect_equal(due_journal_entries, 2, "each due consequence must receive its own journal entry")
	var state_after: Dictionary = session.run_state.to_dict()
	session.get_map_model()
	session.available_shelters()
	_expect_equal(session.run_state.to_dict(), state_after, "model reads must not replay resolved consequences")

	var broken = _new_map_session(_build_for_luck(5), 4_206)
	_expect(broken != null, "atomic failure run must reach map")
	if broken == null:
		return
	var broken_route := _first_available_route(broken.get_map_model())
	_expect(not broken_route.is_empty(), "atomic failure run must expose a route")
	if broken_route.is_empty():
		return
	_expect(
		broken.run_state.schedule_consequence_after(
			"test_broken_due", 1, "cold_symptoms", {"health": -4}, "test"
		),
		"malformed consequence must fit the generic M1 queue"
	)
	var broken_state_before: Dictionary = broken.run_state.to_dict()
	var broken_location_before: String = broken.location
	var broken_revision_before: int = broken.flow_revision
	var rejected: Dictionary = broken.travel(
		String(broken_route["destination_id"]),
		String(broken_route["mode"])
	)
	_expect(not bool(rejected.get("ok", false)), "malformed due consequence must reject the whole decision")
	_expect_equal(String(rejected.get("code", "")), "deferred_resolution_failed", "failure must identify deferred resolution")
	_expect_equal(broken.run_state.to_dict(), broken_state_before, "failed due resolution must roll back time, journal and queue")
	_expect_equal(broken.location, broken_location_before, "failed due resolution must not move the hero")
	_expect_equal(broken.flow_revision, broken_revision_before, "failed due resolution must not touch flow revision")


func _test_shelter_window() -> void:
	var evening = _new_map_session(_build_for_luck(5), 4_208)
	_expect(evening != null, "shelter window run must reach map")
	if evening == null:
		return
	_expect(_travel_to(evening, "underpass"), "shelter window run must reach underpass")
	_expect(evening.available_shelters().is_empty(), "morning must not expose shelter choices")
	var early_attempt: Dictionary = evening.choose_shelter("underpass_niche")
	_expect_equal(String(early_attempt.get("code", "")), "shelter_time_closed", "morning shelter attempt must explain the time lock")
	var early_wait: Dictionary = evening.wait_until_evening()
	_expect_equal(String(early_wait.get("code", "")), "evening_wait_not_earned", "a fresh run must not skip straight to evening")
	while evening.completed.size() < 3:
		var selected: Dictionary = evening.select_event()
		_expect(bool(selected.get("ok", false)), "the run must expose enough events to earn evening wait")
		if not bool(selected.get("ok", false)):
			return
		var option_id := _first_available_option(evening.get_current_event_model())
		_expect(not option_id.is_empty(), "earned-wait setup event must have an answer")
		if option_id.is_empty() or not bool(evening.resolve_choice(option_id).get("ok", false)):
			return
	_expect(
		evening.run_state.schedule_consequence_after("test_wait_due", 1, "cold_symptoms", {"health": -5}, "test"),
		"wait test must schedule a consequence"
	)
	var health_before_wait := int(evening.run_state.get_meter("health"))
	var wait_result: Dictionary = evening.wait_until_evening()
	_expect(bool(wait_result.get("ok", false)), "earned public wait action must advance to 18:00")
	_expect_equal(evening.run_state.get_meter("health"), maxi(health_before_wait - 5, 0), "waiting must resolve due consequences")
	_expect(not evening.available_shelters().is_empty(), "18:00 must expose a local shelter")
	_expect(bool(evening.choose_shelter("underpass_niche").get("ok", false)), "evening shelter must complete the day")
	_expect_equal(evening.run_state.calendar.elapsed_minutes, FirstDaySessionScript.FIRST_DAY_DURATION_MINUTES, "evening sleep must end at the first next 08:00")
	_expect_equal(evening.run_state.calendar.minute_of_day, FirstDaySessionScript.SHELTER_WAKE_MINUTE, "evening sleep must wake at 08:00")

	var after_midnight = _new_map_session(_build_for_luck(5), 4_209)
	_expect(after_midnight != null, "after-midnight shelter run must reach map")
	if after_midnight == null:
		return
	_expect(_travel_to(after_midnight, "underpass"), "after-midnight run must reach underpass")
	var one_am_elapsed := 17 * 60
	var until_one_am := one_am_elapsed - int(after_midnight.run_state.calendar.elapsed_minutes)
	var midnight_setup := SessionCommandTransactionScript.execute(after_midnight, {
		"command_id": "test:after_midnight:setup",
		"source_id": "test_after_midnight",
		"title": "Подготовка времени ночлега",
		"conditions": [],
		"effects": [{
			"type": "advance_time",
			"minutes": until_one_am,
			"reason": "Тестовый подтверждённый переход к 01:00",
		}],
	}) if until_one_am >= 0 else {"ok": false}
	_expect(bool(midnight_setup.get("ok", false)), "test must advance to 01:00 through the session time gateway")
	_expect_equal(
		after_midnight.survival_state.processed_elapsed_minutes,
		after_midnight.run_state.calendar.elapsed_minutes,
		"after-midnight fixture must keep survival and calendar synchronized"
	)
	var before_sleep := int(after_midnight.run_state.calendar.elapsed_minutes)
	_expect(bool(after_midnight.choose_shelter("underpass_niche").get("ok", false)), "01:00 shelter must be accepted")
	_expect_equal(
		after_midnight.run_state.calendar.elapsed_minutes - before_sleep,
		7 * 60,
		"01:00 sleep must advance seven hours, not thirty-one"
	)
	_expect_equal(after_midnight.run_state.calendar.elapsed_minutes, FirstDaySessionScript.FIRST_DAY_DURATION_MINUTES, "after-midnight sleep must not create a multi-day M2 run")


func _test_luck_event_weights() -> void:
	var adverse_ids := {
		"embankment_cold_wind": true,
		"embankment_nightfall": true,
	}
	var low_adverse := 0
	var high_adverse := 0
	var sample_count := 320
	for seed in range(20_000, 20_000 + sample_count):
		var low = FirstDaySessionScript.new()
		var high = FirstDaySessionScript.new()
		low.run_state = RunState.new(_build_for_luck(1), seed)
		high.run_state = RunState.new(_build_for_luck(10), seed)
		for session in [low, high]:
			session.phase = "map"
			session.location = "embankment"
			session.current_event = ""
			session.seen = []
			session.completed = []
		var low_pick: Dictionary = low.select_event()
		var high_pick: Dictionary = high.select_event()
		_expect(bool(low_pick.get("ok", false)) and bool(high_pick.get("ok", false)), "Luck event samples must select an event")
		if adverse_ids.has(low.current_event):
			low_adverse += 1
		if adverse_ids.has(high.current_event):
			high_adverse += 1
	_expect(low_adverse > high_adverse, "low Luck must select more adverse events")
	_expect(low_adverse - high_adverse > sample_count / 5, "Luck event weighting must have a material effect")


func _test_session_semantic_validation() -> void:
	var event_session = FirstDaySessionScript.create(_build_for_luck(5), 4_210)
	_expect(event_session != null, "semantic validation event run must exist")
	if event_session == null:
		return
	var wrong_location = event_session.clone()
	wrong_location.location = "embankment" if event_session.location != "embankment" else "market"
	_expect(not bool(wrong_location.validate().get("ok", true)), "event in another location must fail validation")
	var wrong_phase = event_session.clone()
	wrong_phase.phase = "map"
	_expect(not bool(wrong_phase.validate().get("ok", true)), "current_event outside event phase must fail validation")
	var unknown_history = event_session.clone()
	unknown_history.seen.append("unknown_event")
	unknown_history.completed.append("unknown_event")
	_expect(not bool(unknown_history.validate().get("ok", true)), "unknown history ids must fail validation")

	var unknown_phase = event_session.clone()
	unknown_phase.phase = "job"
	_expect(
		not bool(unknown_phase.validate().get("ok", true)),
		"the removed job phase must fail validation instead of loading silently"
	)


func _test_recovery_candidates() -> void:
	var temporary_path := _test_save_path("temporary_recovery")
	_cleanup_save(temporary_path)
	var temporary_session = _new_map_session(_build_for_luck(5), 7_001)
	_expect(temporary_session != null, "temporary recovery session must exist")
	if temporary_session != null:
		var saved: Dictionary = FirstDaySaveScript.save_session(temporary_session, temporary_path)
		_expect(bool(saved.get("ok", false)), "temporary recovery source must save")
		_expect(_copy_file(temporary_path, temporary_path + ".tmp"), "test must create an interrupted valid temporary")
		var recovered: Dictionary = FirstDaySaveScript.load_session(temporary_path)
		_expect(bool(recovered.get("ok", false)), "valid temporary must recover")
		_expect(bool(recovered.get("recovered_from_temporary", false)), "temporary recovery flag must be true")
		var restored = recovered.get("session")
		_expect(restored != null and _values_equal(restored.to_dict(), temporary_session.to_dict()), "temporary recovery must preserve session")
	_cleanup_save(temporary_path)

	var backup_path := _test_save_path("backup_recovery")
	_cleanup_save(backup_path)
	var backup_session = _new_map_session(_build_for_luck(5), 7_002)
	_expect(backup_session != null, "backup recovery session must exist")
	if backup_session != null:
		_expect(bool(FirstDaySaveScript.save_session(backup_session, backup_path).get("ok", false)), "first backup source save must succeed")
		var expected_backup: Dictionary = backup_session.to_dict()
		_expect(backup_session.set_setting("show_locked_options", true), "second revision must mutate flow")
		_expect(bool(FirstDaySaveScript.save_session(backup_session, backup_path).get("ok", false)), "second save must create backup")
		_expect(_write_text(backup_path, "{broken"), "test must corrupt primary")
		var recovered_backup: Dictionary = FirstDaySaveScript.load_session(backup_path)
		_expect(bool(recovered_backup.get("ok", false)), "valid backup must recover")
		_expect(bool(recovered_backup.get("recovered_from_backup", false)), "backup recovery flag must be true")
		var restored_backup = recovered_backup.get("session")
		_expect(restored_backup != null and _values_equal(restored_backup.to_dict(), expected_backup), "backup must restore the previous complete revision")
	_cleanup_save(backup_path)


func _test_three_complete_runs() -> void:
	for luck in [1, 5, 10]:
		var session = _complete_first_day(luck, 80_000 + luck)
		_expect(session != null, "Luck %d run must complete" % luck)
		if session == null:
			continue
		_expect(session.day_completed, "Luck %d run must set day_completed" % luck)
		_expect_equal(session.phase, "completed", "Luck %d run must enter completed phase" % luck)
		_expect_equal(session.run_state.calendar.minute_of_day, 8 * 60, "Luck %d run must wake at 08:00" % luck)
		_expect_equal(session.biography.size(), 1, "Luck %d run must write one biography entry" % luck)
		_expect(bool(session.validate().get("ok", false)), "Luck %d completed run must validate" % luck)


func _test_phase_round_trips() -> void:
	var event_session = FirstDaySessionScript.create(_build_for_luck(5), 90_001)
	_expect(event_session != null and event_session.phase == "event", "new run must expose event phase")
	if event_session != null:
		_expect(_assert_session_round_trip(event_session, "event"), "event phase must survive save round-trip")

	var map_session = _new_map_session(_build_for_luck(5), 90_002)
	_expect(map_session != null and map_session.phase == "map", "prepared run must expose map phase")
	if map_session != null:
		_expect(_assert_session_round_trip(map_session, "map"), "map phase must survive save round-trip")


func _test_psyche_setting() -> void:
	var session = null
	for seed in range(1, 100):
		var candidate = FirstDaySessionScript.create(_build_for_luck(1), seed)
		if candidate != null and candidate.psyche_intensity() > 0.0:
			session = candidate
			break
	_expect(session != null, "test must find a run with a visible psyche effect")
	if session == null:
		return
	var state_snapshot: Dictionary = session.run_state.to_dict()
	var full: float = float(session.psyche_intensity())
	_expect(session.set_setting("psyche_effect_mode", "reduced"), "reduced psyche mode must be accepted")
	var reduced: float = float(session.psyche_intensity())
	_expect(session.set_setting("psyche_effect_mode", "off"), "off psyche mode must be accepted")
	var disabled: float = float(session.psyche_intensity())
	_expect(full > reduced and reduced > disabled, "full, reduced and off intensities must be ordered")
	_expect(is_equal_approx(reduced, full * 0.5), "reduced mode must halve presentation intensity")
	_expect_equal(disabled, 0.0, "off mode must remove presentation intensity")
	_expect_equal(session.run_state.to_dict(), state_snapshot, "psyche presentation setting must not mutate gameplay state")


func _build_for_luck(luck: int) -> Dictionary:
	var result := {
		"strength": 1,
		"charisma": 1,
		"intelligence": 1,
		"luck": luck,
	}
	var remaining := GameRules.CHARACTERISTIC_BUDGET - luck - 3
	for key in ["strength", "charisma", "intelligence"]:
		var addition := mini(9, remaining)
		result[key] = 1 + addition
		remaining -= addition
	return result


func _new_map_session(build: Dictionary, seed: int) -> Variant:
	var session = FirstDaySessionScript.create(build, seed)
	if session == null:
		return null
	var guard := 0
	while session.phase in ["start", "event"] and guard < 8:
		var model: Dictionary = session.get_current_event_model()
		var choice_id := _first_available_option(model)
		if choice_id.is_empty():
			return null
		var result: Dictionary = session.resolve_choice(choice_id)
		if not bool(result.get("ok", false)):
			return null
		guard += 1
	return session if session.phase == "map" else null


func _first_available_option(model: Dictionary) -> String:
	for option_value in Array(model.get("options", [])):
		if option_value is Dictionary and not bool(option_value.get("locked", false)):
			return String(option_value.get("id", ""))
	return ""


func _option_ids(model: Dictionary) -> Array:
	var result: Array = []
	for option_value in Array(model.get("options", [])):
		if option_value is Dictionary:
			result.append(String(option_value.get("id", "")))
	return result


func _first_available_route(map_model: Dictionary, destination: String = "") -> Dictionary:
	var fallback: Dictionary = {}
	for route_value in Array(map_model.get("routes", [])):
		if not route_value is Dictionary or not bool(route_value.get("available", false)):
			continue
		if not destination.is_empty() and String(route_value.get("destination_id", "")) != destination:
			continue
		if fallback.is_empty():
			fallback = route_value.duplicate(true)
		if String(route_value.get("mode", "")) == "walk":
			return route_value.duplicate(true)
	return fallback


func _travel_to(session: Variant, destination: String) -> bool:
	if session == null or session.phase != "map":
		return false
	if session.location == destination:
		return true
	var path := _location_path(String(session.location), destination)
	if path.is_empty():
		return false
	for next_location in path:
		var route := _first_available_route(session.get_map_model(), String(next_location))
		if route.is_empty():
			return false
		var travel_result: Dictionary = session.travel(String(route["destination_id"]), String(route["mode"]))
		if not bool(travel_result.get("ok", false)):
			return false
	return session.location == destination


func _location_path(origin: String, destination: String) -> Array:
	if origin == destination:
		return []
	var queue: Array = [origin]
	var parent: Dictionary = {origin: ""}
	while not queue.is_empty():
		var current := String(queue.pop_front())
		for route_value in FirstDayContentScript.routes_from(current):
			if not route_value is Dictionary:
				continue
			var next := String(route_value.get("destination_id", route_value.get("to", "")))
			if next.is_empty() or parent.has(next):
				continue
			parent[next] = current
			if next == destination:
				var reversed: Array = []
				var cursor := destination
				while cursor != origin:
					reversed.append(cursor)
					cursor = String(parent[cursor])
				reversed.reverse()
				return reversed
			queue.append(next)
	return []


## Lives out `wanted` ordinary events wherever they can be found, so a test can
## reach the evening the way a player does instead of through a shortcut.
func _resolve_local_events(session: Variant, wanted: int) -> bool:
	var guard := 0
	while session.completed.size() < wanted and guard < 40:
		guard += 1
		var map_model: Dictionary = session.get_map_model()
		var opened := false
		for raw_event: Variant in Array(map_model.get("events", [])):
			if not raw_event is Dictionary:
				continue
			var event: Dictionary = raw_event
			if not bool(event.get("available", false)) or bool(event.get("completed", false)):
				continue
			if not bool(session.enter_event(String(event.get("id", ""))).get("ok", false)):
				continue
			opened = true
			break
		if not opened:
			var route := _first_available_route(session.get_map_model())
			if route.is_empty():
				return false
			if not bool(session.travel(
				String(route["destination_id"]),
				String(route["mode"])
			).get("ok", false)):
				return false
			continue
		var choice_id := _first_available_option(session.get_current_event_model())
		if choice_id.is_empty():
			return false
		if not bool(session.resolve_choice(choice_id).get("ok", false)):
			return false
		while session.phase == "event":
			var next_choice := _first_available_option(session.get_current_event_model())
			if next_choice.is_empty() or not bool(session.resolve_choice(next_choice).get("ok", false)):
				return false
	return session.completed.size() >= wanted


func _complete_first_day(luck: int, seed: int) -> Variant:
	var session = _new_map_session(_build_for_luck(luck), seed)
	if session == null:
		return null
	# Waiting out the afternoon is earned by living the day, so the run has to
	# resolve real events before the evening opens up.
	if not _resolve_local_events(session, 3):
		return null
	if not _travel_to(session, "underpass"):
		return null
	var wait_result: Dictionary = session.wait_until_evening()
	if not bool(wait_result.get("ok", false)):
		return null
	var shelter_options: Array = session.available_shelters()
	if shelter_options.is_empty():
		return null
	var before_date := _date_key(session.run_state.calendar.current_stamp())
	var shelter_id := ""
	for shelter_value in shelter_options:
		if shelter_value is Dictionary and not bool(shelter_value.get("locked", false)):
			shelter_id = String(shelter_value.get("id", ""))
			break
	if shelter_id.is_empty() or not bool(session.choose_shelter(shelter_id).get("ok", false)):
		return null
	var after_date := _date_key(session.run_state.calendar.current_stamp())
	_expect(after_date != before_date, "completed run must wake on the next date (before=%s, after=%s)" % [before_date, after_date])
	return session


func _date_key(stamp: Dictionary) -> String:
	return "%s-%s-%s" % [stamp.get("year", 0), stamp.get("month", 0), stamp.get("day", 0)]


func _assert_session_round_trip(session: Variant, label: String) -> bool:
	var path := _test_save_path("phase_%s" % label)
	_cleanup_save(path)
	var expected: Dictionary = session.to_dict()
	var saved: Dictionary = FirstDaySaveScript.save_session(session, path)
	if not bool(saved.get("ok", false)):
		_cleanup_save(path)
		return false
	var loaded: Dictionary = FirstDaySaveScript.load_session(path)
	var restored = loaded.get("session")
	var result: bool = bool(loaded.get("ok", false)) and restored != null and _values_equal(restored.to_dict(), expected)
	_cleanup_save(path)
	return result


func _test_save_path(label: String) -> String:
	return ProjectSettings.globalize_path("res://.godot/%s%s.json" % [_save_prefix, label])


func _copy_file(source_path: String, destination_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var payload := source.get_as_text()
	source = null
	var destination := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination == null:
		return false
	destination.store_string(payload)
	destination.flush()
	var error := destination.get_error()
	destination = null
	return error == OK


func _write_text(path: String, payload: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.flush()
	var error := file.get_error()
	file = null
	return error == OK


func _cleanup_save(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _cleanup_all_test_saves() -> void:
	for label in [
		"temporary_recovery",
		"backup_recovery",
		"phase_event",
		"phase_map",
	]:
		_cleanup_save(_test_save_path(label))
