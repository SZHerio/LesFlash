extends SceneTree

const GameRulesScript = preload("res://core/config/game_rules.gd")
const RunStateScript = preload("res://core/state/run_state.gd")
const DeterministicRngScript = preload("res://core/random/deterministic_rng.gd")
const ConditionScript = preload("res://core/rules/condition.gd")
const EffectScript = preload("res://core/rules/effect.gd")
const CheckResolverScript = preload("res://core/rules/check_resolver.gd")
const ActionTransactionScript = preload("res://core/rules/action_transaction.gd")
const RunStateSaveScript = preload("res://core/save/run_state_save.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""


func _init() -> void:
	_run_test("characteristic allocation", _test_characteristic_allocation)
	_run_test("initial state and profiles", _test_initial_state_and_profiles)
	_run_test("conditions and blocked reasons", _test_conditions_and_blocked_reasons)
	_run_test("successful atomic action", _test_successful_atomic_action)
	_run_test("blocked action does not advance time", _test_blocked_action_does_not_advance_time)
	_run_test("failed effects roll back", _test_failed_effects_roll_back)
	_run_test("invalid source state cannot be cloned", _test_invalid_source_state_cannot_be_cloned)
	_run_test("skill rank cap cannot lower a skill", _test_skill_rank_cap_cannot_lower_skill)
	_run_test("time advance is bounded", _test_time_advance_is_bounded)
	_run_test("JSON payload exactness", _test_json_payload_exactness)
	_run_test("computed profile evidence bounds", _test_computed_profile_evidence_bounds)
	_run_test("deterministic RNG and snapshot", _test_deterministic_rng_and_snapshot)
	_run_test("calendar and age", _test_calendar_and_age)
	_run_test("save round-trip and backup recovery", _test_save_round_trip_and_backup_recovery)
	_run_test("temporary save recovery", _test_temporary_save_recovery)
	_run_test("invalid save candidates", _test_invalid_save_candidates)

	if _failures.is_empty():
		print("M1 TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return

	print("M1 TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
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
	if actual != expected:
		_failures.append(
			"%s — %s (expected=%s, actual=%s)" % [
				_current_test,
				message,
				str(expected),
				str(actual),
			]
		)


func _specialized_characteristics() -> Dictionary:
	return {
		"strength": 8,
		"charisma": 3,
		"intelligence": 4,
		"luck": 3,
	}


func _test_characteristic_allocation() -> void:
	var state = RunStateScript.new()
	_expect(state.validate()["ok"], "default RunState must be valid")
	_expect_equal(_sum_dictionary_values(state.characteristics), 18, "default budget must total 18")
	_expect(state.set_characteristics(_specialized_characteristics()), "valid specialized allocation must be accepted")
	_expect_equal(state.get_characteristic("strength"), 8, "specialized Strength must be stored")

	var before: Dictionary = state.characteristics.duplicate(true)
	var invalid := _specialized_characteristics()
	invalid["luck"] = 4
	_expect(not state.set_characteristics(invalid), "allocation totaling 19 must be rejected")
	_expect_equal(state.characteristics, before, "rejected allocation must not mutate state")

	invalid = _specialized_characteristics()
	invalid["strength"] = 11
	invalid["charisma"] = 0
	_expect(not state.set_characteristics(invalid), "values outside 1..10 must be rejected")

	var build_count := 0
	for strength in range(1, 11):
		for charisma in range(1, 11):
			for intelligence in range(1, 11):
				for luck in range(1, 11):
					if strength + charisma + intelligence + luck == GameRulesScript.CHARACTERISTIC_BUDGET:
						build_count += 1
	_expect_equal(build_count, 540, "the fixed budget must produce 540 numeric builds")

	var serialized := state.to_dict()
	serialized["characteristics"]["luck"] = 10
	_expect(RunStateScript.from_dict(serialized) == null, "deserialization must reject an invalid budget")


func _test_initial_state_and_profiles() -> void:
	var state = RunStateScript.new(_specialized_characteristics(), 12345)
	_expect_equal(state.age_years, 18, "a new run must start at age 18")
	_expect_equal(state.money, 0, "a new run must start without money")
	_expect_equal(state.get_item_count("cardboard_sheet"), 0, "a new run must start without items")
	_expect_equal(state.stored_polarities.size(), 6, "six polarities must be stored")
	_expect_equal(state.computed_profiles.size(), 2, "two polarities must be computed profiles")
	for polarity_value in state.stored_polarities.values():
		_expect_equal(polarity_value, 0, "stored polarities must start neutral")
	for profile_value in state.computed_profiles.values():
		_expect(not profile_value["formed"], "computed profiles must start unformed")
		_expect_equal(profile_value["value"], 0, "unformed profiles must start at zero")
	_expect_equal(state.skills.size(), 7, "seven test skills must exist")
	for skill_rank in state.skills.values():
		_expect_equal(skill_rank, 0, "skills must not be selected at character creation")
	_expect_equal(state.mastery_points, 0, "mastery points must start at zero")
	_expect_equal(state.calendar.elapsed_minutes, 0, "reading state must not advance game time")


func _test_conditions_and_blocked_reasons() -> void:
	var state = RunStateScript.new()
	var strength_gate := ConditionScript.with_reason(
		ConditionScript.stat(&"strength", 8),
		"Нужно не менее 8 Силы"
	)
	var check: Dictionary = CheckResolverScript.evaluate_all(state, [strength_gate])
	_expect(not check["allowed"], "insufficient Strength must block the option")
	_expect_equal(check["reasons"].size(), 1, "one failed condition must have one reason")
	_expect_equal(check["reasons"][0]["message"], "Нужно не менее 8 Силы", "custom reason must be preserved")

	var profile_condition := ConditionScript.polarity(&"relationship_investment", 20)
	var profile_check: Dictionary = CheckResolverScript.evaluate(state, profile_condition)
	_expect(not profile_check["passed"], "unformed computed profile must not pass a threshold")
	_expect_equal(profile_check["code"], "profile_not_formed", "unformed profile must have a specific reason")
	_expect(state.set_computed_profile("relationship_investment", 30, 5), "enough evidence must form a profile")
	profile_check = CheckResolverScript.evaluate(state, profile_condition)
	_expect(profile_check["passed"], "formed profile must participate in checks")


func _test_successful_atomic_action() -> void:
	var state = RunStateScript.new(_specialized_characteristics(), 777)
	var action := {
		"id": "shop_unloading",
		"option_id": "carry_crates",
		"title": "Разгрузка",
		"option_title": "Перенести ящики",
		"conditions": [
			ConditionScript.stat(&"strength", 7),
			ConditionScript.state(&"energy", 40),
		],
		"effects": [
			EffectScript.advance_time(60, "Разгрузка у магазина"),
			EffectScript.change_state(&"energy", -25),
			EffectScript.change_state(&"hunger", 20),
			EffectScript.change_money(350),
			EffectScript.add_item(&"bread", 2),
			EffectScript.shift_polarity(&"physical_specialization", -6),
			EffectScript.unlock_skill(&"cargo_handling", 1),
			EffectScript.mastery(3),
			EffectScript.knowledge(&"cargo_safety", 1, &"unlock"),
			EffectScript.deferred(&"muscle_soreness", 180, {"severity": 1}),
		],
	}

	var result = ActionTransactionScript.execute(state, action)
	_expect(result.success, "valid action must commit")
	_expect_equal(result.changes.size(), 10, "every applied effect must produce a change record")
	_expect_equal(state.calendar.elapsed_minutes, 60, "confirmed action must advance discrete time")
	_expect_equal(state.get_meter("energy"), 75, "energy cost must be applied")
	_expect_equal(state.get_meter("hunger"), 20, "hunger cost must be applied")
	_expect_equal(state.money, 350, "payment must be applied")
	_expect_equal(state.get_item_count("bread"), 2, "item reward must be applied")
	_expect_equal(state.get_polarity("physical_specialization"), -6, "polarity drift must be applied")
	_expect_equal(state.get_skill_rank("cargo_handling"), 1, "skill must be acquired in play")
	_expect_equal(state.mastery_points, 3, "mastery points must be granted")
	_expect_equal(state.get_knowledge_level("cargo_safety"), 1, "knowledge must be acquired")
	_expect_equal(state.deferred_consequences.size(), 1, "deferred consequence must be scheduled")
	_expect(state.validate()["ok"], "committed state must validate")

	_expect_equal(result.journal_entry["type"], "action", "transaction must append an action journal entry")
	_expect_equal(result.journal_entry["payload"]["changes"].size(), 10, "journal must explain every effect")
	_expect_equal(result.journal_entry["payload"]["time"]["advanced_minutes"], 60, "journal must explain elapsed time")
	_expect_equal(state.journal.back()["id"], result.journal_entry["id"], "committed journal entry must match result")


func _test_blocked_action_does_not_advance_time() -> void:
	var state = RunStateScript.new()
	var snapshot := state.to_dict()
	var result = ActionTransactionScript.execute_parts(
		state,
		&"heavy_door",
		&"force_open",
		[ConditionScript.stat(&"strength", 10)],
		[EffectScript.advance_time(30, "Попытка открыть дверь")]
	)
	_expect(not result.success, "blocked action must fail")
	_expect_equal(String(result.code), "blocked", "blocked action must have blocked code")
	_expect_equal(state.to_dict(), snapshot, "blocked action must leave all state unchanged")
	_expect_equal(state.calendar.elapsed_minutes, 0, "blocked action must not advance time")


func _test_failed_effects_roll_back() -> void:
	var state = RunStateScript.new(_specialized_characteristics())
	var snapshot := state.to_dict()
	var result = ActionTransactionScript.execute_parts(
		state,
		&"bad_transaction",
		&"missing_item",
		[],
		[
			EffectScript.change_state(&"health", -50),
			EffectScript.remove_item(&"medicine", 1),
		]
	)
	_expect(not result.success, "batch with a failing effect must fail")
	_expect_equal(String(result.code), "insufficient_item", "failure must identify the rejected effect")
	_expect_equal(result.failed_effect_index, 1, "failure must report the effect index")
	_expect_equal(result.changes.size(), 1, "result may explain discarded changes")
	_expect_equal(state.to_dict(), snapshot, "failed batch must roll back every prior effect")


func _test_invalid_source_state_cannot_be_cloned() -> void:
	var state = RunStateScript.new()
	state.characteristics["strength"] = 99
	var snapshot := state.to_dict()
	var result = ActionTransactionScript.execute_parts(
		state,
		&"invalid_source",
		&"try_action",
		[],
		[EffectScript.change_money(100)]
	)
	_expect(not result.success, "an invalid source state must not produce a working copy")
	_expect_equal(String(result.code), "clone_failed", "clone failure must be explicit")
	_expect_equal(state.to_dict(), snapshot, "clone failure must not replace the run with defaults")


func _test_skill_rank_cap_cannot_lower_skill() -> void:
	var state = RunStateScript.new()
	_expect(state.set_skill_rank("repair", 3), "fixture skill must reach rank 3")
	var snapshot := state.to_dict()
	var result = ActionTransactionScript.execute_parts(
		state,
		&"skill_regression",
		&"train",
		[],
		[EffectScript.advance_skill(&"repair", 1, 2)]
	)
	_expect(not result.success, "a cap below the current rank must be rejected")
	_expect_equal(String(result.code), "invalid_max_rank", "rank regression must have a specific code")
	_expect_equal(state.to_dict(), snapshot, "a rejected skill effect must be atomic")


func _test_time_advance_is_bounded() -> void:
	var state = RunStateScript.new()
	var snapshot := state.to_dict()
	var result = ActionTransactionScript.execute_parts(
		state,
		&"impossible_timeskip",
		&"wait",
		[],
		[EffectScript.advance_time(GameRulesScript.MAX_TIME_ADVANCE_MINUTES + 1)]
	)
	_expect(not result.success, "one action must not skip beyond the configured bound")
	_expect_equal(String(result.code), "time_advance_too_large", "oversized time skip must be identified")
	_expect_equal(state.to_dict(), snapshot, "rejected time must leave calendar and journal unchanged")

	result = ActionTransactionScript.execute_parts(
		state,
		&"cumulative_timeskip",
		&"wait_twice",
		[],
		[
			EffectScript.advance_time(GameRulesScript.MAX_TIME_ADVANCE_MINUTES),
			EffectScript.advance_time(1),
		]
	)
	_expect(not result.success, "the time bound must apply to the whole decision")
	_expect_equal(String(result.code), "time_advance_too_large", "cumulative time overflow must be identified")
	_expect_equal(state.to_dict(), snapshot, "cumulative time rejection must roll back earlier time effects")

	var boundary_stamp: Dictionary = state.calendar.current_stamp()
	boundary_stamp["year"] = 1_000_000
	_expect(state.calendar.set_stamp(boundary_stamp), "calendar boundary fixture must be valid")
	var calendar_snapshot: Dictionary = state.calendar.current_stamp()
	_expect(not state.calendar.advance_days(366), "calendar must not advance beyond its supported year")
	_expect_equal(state.calendar.current_stamp(), calendar_snapshot, "failed calendar advance must be atomic")


func _test_json_payload_exactness() -> void:
	var state = RunStateScript.new()
	_expect(
		state.add_journal_entry("test", "integral float", {"value": 1.0}),
		"an exact integral float payload must be accepted"
	)
	_expect(state.journal.back()["payload"]["value"] is int, "integral payloads must be canonical integers")
	var journal_size: int = state.journal.size()
	_expect(
		not state.add_journal_entry(
			"test",
			"unsafe integer",
			{"value": GameRulesScript.JSON_SAFE_INTEGER_MAX + 1}
		),
		"integers outside JSON's exact range must be rejected"
	)
	_expect_equal(state.journal.size(), journal_size, "rejected payload must not append a journal entry")


func _test_computed_profile_evidence_bounds() -> void:
	var state = RunStateScript.new()
	state.computed_profiles["knowledge_profile"]["evidence"] = GameRulesScript.MASTERY_POINTS_MAX + 1
	_expect(not state.validate()["ok"], "live state must reject unbounded profile evidence")

	var serialized = RunStateScript.new().to_dict()
	serialized["computed_profiles"]["knowledge_profile"]["evidence"] = GameRulesScript.MASTERY_POINTS_MAX + 1
	_expect(RunStateScript.from_dict(serialized) == null, "deserialization must reject unbounded profile evidence")


func _test_deterministic_rng_and_snapshot() -> void:
	var left = DeterministicRngScript.new(424242)
	var right = DeterministicRngScript.new(424242)
	for index in range(20):
		_expect_equal(left.next_int(-1000, 1000), right.next_int(-1000, 1000), "same seed must reproduce draw %d" % index)

	var snapshot := left.to_dict()
	_expect(snapshot["seed"] is String, "seed must be serialized without JSON precision loss")
	_expect(snapshot["state"] is String, "RNG state must be serialized without JSON precision loss")
	var expected_next := left.next_u32()
	var restored = DeterministicRngScript.from_dict(snapshot)
	_expect(restored != null, "valid RNG snapshot must restore")
	if restored != null:
		_expect_equal(restored.next_u32(), expected_next, "restored state must continue the same sequence")


func _test_calendar_and_age() -> void:
	var state = RunStateScript.new()
	_expect_equal(state.age_years, 18, "run must begin at age 18")
	var minutes_in_year := 365 * 24 * 60
	_expect(state.advance_time(minutes_in_year, "Прошёл год"), "explicit yearly advance must succeed")
	_expect_equal(state.age_years, 19, "age must follow the calendar")
	_expect_equal(state.calendar.year, 1981, "calendar must cross into the next year")
	_expect_equal(state.calendar.month, 9, "calendar month must remain aligned")
	_expect_equal(state.calendar.day, 1, "calendar day must remain aligned")
	_expect_equal(state.calendar.minute_of_day, 8 * 60, "time of day must remain aligned")
	_expect_equal(state.journal.back()["payload"]["minutes"], minutes_in_year, "direct time advance must be logged")

	var invalid_calendar_state = RunStateScript.new()
	invalid_calendar_state.calendar.minutes_per_day = 100_001
	_expect(not invalid_calendar_state.validate()["ok"], "live calendar validation must match deserialization limits")
	_expect(invalid_calendar_state.clone() == null, "an invalid calendar must not clone into default time")


func _test_save_round_trip_and_backup_recovery() -> void:
	var save_path := "user://m1-tests/run_state.json"
	var absolute_path := ProjectSettings.globalize_path(save_path)
	_cleanup_save_files(absolute_path)

	var state = RunStateScript.new(_specialized_characteristics(), 919191)
	var result = ActionTransactionScript.execute_parts(
		state,
		&"prepare_save",
		&"confirm",
		[],
		[
			EffectScript.advance_time(45, "Подготовка"),
			EffectScript.change_money(125),
			EffectScript.add_item(&"notebook", 1),
		]
	)
	_expect(result.success, "fixture action must succeed before save")
	_expect(
		state.add_journal_entry("test", "precise float", {"value": 0.12345678901234567}),
		"precise float fixture must be accepted"
	)
	var first_snapshot := state.to_dict()

	var save_result: Dictionary = RunStateSaveScript.save_state(state, save_path)
	_expect(save_result["ok"], "first save must succeed: %s" % save_result.get("error", ""))
	var load_result: Dictionary = RunStateSaveScript.load_state(save_path)
	_expect(load_result["ok"], "saved state must load: %s" % load_result.get("error", ""))
	if load_result["ok"]:
		_expect_equal(load_result["state"].to_dict(), first_snapshot, "loaded state must equal saved state")

	_expect(state.set_money(999), "fixture mutation must succeed")
	state.rng.next_u32()
	var second_snapshot := state.to_dict()
	save_result = RunStateSaveScript.save_state(state, save_path)
	_expect(save_result["ok"], "overwrite save must succeed: %s" % save_result.get("error", ""))
	_expect(FileAccess.file_exists(absolute_path + ".bak"), "overwrite must retain a valid backup")
	load_result = RunStateSaveScript.load_state(save_path)
	if load_result["ok"]:
		_expect_equal(load_result["state"].to_dict(), second_snapshot, "primary must contain the overwritten state")

	var corrupt_file := FileAccess.open(absolute_path, FileAccess.WRITE)
	_expect(corrupt_file != null, "test must be able to corrupt the primary save")
	if corrupt_file != null:
		corrupt_file.store_string("{not valid json")
		corrupt_file = null
	load_result = RunStateSaveScript.load_state(save_path)
	_expect(load_result["ok"], "loader must recover from a valid backup")
	_expect(load_result.get("recovered_from_backup", false), "load result must report backup recovery")
	if load_result["ok"]:
		_expect_equal(load_result["state"].to_dict(), first_snapshot, "recovery must return the previous valid save")

	_cleanup_save_files(absolute_path)


func _test_temporary_save_recovery() -> void:
	var save_path := "user://m1-tests-temporary/run_state.json"
	var absolute_path := ProjectSettings.globalize_path(save_path)
	_cleanup_save_files(absolute_path)

	var state = RunStateScript.new(_specialized_characteristics(), 515151)
	_expect(state.set_money(777), "temporary fixture state must be mutable")
	var snapshot := state.to_dict()
	var save_result: Dictionary = RunStateSaveScript.save_state(state, save_path)
	_expect(save_result["ok"], "temporary fixture save must succeed")
	if save_result["ok"]:
		var rename_error := DirAccess.rename_absolute(absolute_path, absolute_path + ".tmp")
		_expect_equal(rename_error, OK, "test must simulate an interrupted first save")

	var blocked_save: Dictionary = RunStateSaveScript.save_state(RunStateScript.new(), save_path)
	_expect(not blocked_save["ok"], "autosave must not overwrite a valid interrupted save")
	_expect_equal(blocked_save["code"], "pending_temporary_recovery", "pending recovery must be explicit")

	var load_result: Dictionary = RunStateSaveScript.load_state(save_path)
	_expect(load_result["ok"], "a valid temporary-only save must recover")
	_expect(load_result.get("recovered_from_temporary", false), "load result must report temporary recovery")
	_expect(FileAccess.file_exists(absolute_path), "recovery must install the primary save")
	_expect(not FileAccess.file_exists(absolute_path + ".tmp"), "recovery must consume the temporary file")
	if load_result["ok"]:
		_expect_equal(load_result["state"].to_dict(), snapshot, "temporary recovery must preserve the exact run")

	_cleanup_save_files(absolute_path)

	var newer_save_path := "user://m1-tests-temporary-newer/run_state.json"
	var newer_absolute_path := ProjectSettings.globalize_path(newer_save_path)
	_cleanup_save_files(newer_absolute_path)
	var older_state = RunStateScript.new(_specialized_characteristics(), 616161)
	var newer_state = RunStateScript.new(_specialized_characteristics(), 717171)
	_expect(older_state.set_money(100), "older primary fixture must be mutable")
	_expect(newer_state.set_money(900), "newer temporary fixture must be mutable")
	_expect(RunStateSaveScript.save_state(older_state, save_path)["ok"], "older primary fixture must save")
	_expect(RunStateSaveScript.save_state(newer_state, newer_save_path)["ok"], "newer temporary fixture must save")
	var newer_snapshot := newer_state.to_dict()
	_expect_equal(
		DirAccess.rename_absolute(newer_absolute_path, absolute_path + ".tmp"),
		OK,
		"test must place a newer validated temporary save beside the primary"
	)

	load_result = RunStateSaveScript.load_state(save_path)
	_expect(load_result["ok"], "newer temporary save must recover over an older primary")
	_expect(load_result.get("recovered_from_temporary", false), "newer temporary recovery must be reported")
	_expect(FileAccess.file_exists(absolute_path + ".bak"), "older valid primary must remain as backup")
	if load_result["ok"]:
		_expect_equal(load_result["state"].to_dict(), newer_snapshot, "newer temporary state must win recovery")

	_cleanup_save_files(absolute_path)
	_cleanup_save_files(newer_absolute_path)


func _test_invalid_save_candidates() -> void:
	var save_path := "user://m1-tests-invalid/run_state.json"
	var absolute_path := ProjectSettings.globalize_path(save_path)
	_cleanup_save_files(absolute_path)
	_expect_equal(
		DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()),
		OK,
		"test save directory must be created"
	)
	_expect(_write_text_file(absolute_path, "{\"schema_version\":999,\"run_state\":{}}"), "primary fixture must be written")
	_expect(_write_text_file(absolute_path + ".tmp", "{broken temporary"), "temporary fixture must be written")
	_expect(_write_text_file(absolute_path + ".bak", "[]"), "backup fixture must be written")

	var load_result: Dictionary = RunStateSaveScript.load_state(save_path)
	_expect(not load_result["ok"], "invalid candidates must never produce a state")
	_expect_equal(load_result["code"], "no_valid_save", "all invalid candidates must have one aggregate error")
	var candidate_errors: Dictionary = load_result.get("details", {}).get("candidate_errors", {})
	_expect_equal(candidate_errors.size(), 3, "aggregate error must retain every candidate failure")

	_cleanup_save_files(absolute_path)


func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total


func _cleanup_save_files(absolute_path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = absolute_path + String(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	var directory_path := absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(directory_path):
		DirAccess.remove_absolute(directory_path)


func _write_text_file(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file = null
	return write_error == OK
