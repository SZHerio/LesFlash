extends SceneTree

const CatalogScript := preload("res://game/location/location_action_catalog.gd")
const ServiceScript := preload("res://game/location/location_action_service.gd")

class SessionHolder:
	extends RefCounted
	var run_state: RunState

	func _init(value: RunState) -> void:
		run_state = value


var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""


func _init() -> void:
	_run_test("versioned catalog validates", _test_catalog_validates)
	_run_test("catalog rejects malformed conditions and effects", _test_catalog_rejects_malformed_rules)
	_run_test("location changes available actions", _test_location_changes_actions)
	_run_test("time changes available actions", _test_time_changes_actions)
	_run_test("state changes available actions", _test_state_changes_actions)
	_run_test("characteristics change actions and reasons", _test_characteristics_change_actions)
	_run_test("read models are timeless and deterministic", _test_reads_are_pure)
	_run_test("confirmed action advances time exactly once", _test_execute_once)
	_run_test("blocked execution is atomic", _test_blocked_is_atomic)

	if _failures.is_empty():
		print("LOCATION ACTION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("LOCATION ACTION TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current_test, message, str(expected), str(actual)])


func _test_catalog_validates() -> void:
	var loaded := CatalogScript.load_default()
	_expect(bool(loaded.get("ok", false)), "default catalog must load: %s" % str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded.get("catalog", {})
	_expect_equal(int(catalog.get("schema_version", 0)), 1, "catalog must carry schema version 1")
	_expect(Array(catalog.get("actions", [])).size() >= 12, "catalog must cover the six prototype locations")
	var service := ServiceScript.new(catalog)
	_expect(service.is_ready(), "validated catalog must build a ready service")


func _test_catalog_rejects_malformed_rules() -> void:
	var loaded := CatalogScript.load_default()
	_expect(bool(loaded.get("ok", false)), "default catalog must load before mutation")
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded.get("catalog", {})
	var invalid_condition := catalog.duplicate(true)
	var condition_actions: Array = invalid_condition.get("actions", [])
	var condition_action: Dictionary = condition_actions[0]
	var conditions: Array = condition_action.get("conditions", [])
	var condition: Dictionary = conditions[0]
	condition["kind"] = "telepathy"
	conditions[0] = condition
	condition_action["conditions"] = conditions
	condition_actions[0] = condition_action
	invalid_condition["actions"] = condition_actions
	var condition_validation := CatalogScript.validate(invalid_condition)
	_expect(
		not bool(condition_validation.get("ok", true)),
		"unknown condition kind must fail at catalog load time"
	)

	var invalid_effect := catalog.duplicate(true)
	var effect_actions: Array = invalid_effect.get("actions", [])
	var mutated := false
	for action_index in range(effect_actions.size()):
		var action: Dictionary = effect_actions[action_index]
		var effects: Array = action.get("effects", [])
		for effect_index in range(effects.size()):
			var effect: Dictionary = effects[effect_index]
			if String(effect.get("type", "")) != "change_state":
				continue
			effect.erase("id")
			effect.erase("delta")
			effects[effect_index] = effect
			action["effects"] = effects
			effect_actions[action_index] = action
			mutated = true
			break
		if mutated:
			break
	invalid_effect["actions"] = effect_actions
	_expect(mutated, "fixture must contain a change_state effect")
	var effect_validation := CatalogScript.validate(invalid_effect)
	_expect(
		not bool(effect_validation.get("ok", true)),
		"effect without id/delta must fail at catalog load time"
	)


func _test_location_changes_actions() -> void:
	var service := ServiceScript.new()
	var state := _state_at(8 * 60, _balanced_build())
	var market_ids := _ids(service.read_models(state, "market"))
	var clinic_ids := _ids(service.read_models(state, "clinic_yard"))
	_expect(not market_ids.is_empty(), "market must expose at least one action at 08:00")
	_expect(not clinic_ids.is_empty(), "clinic yard must expose at least one action at 08:00")
	_expect(market_ids != clinic_ids, "different locations must not expose the same action set")
	_expect("market_read_notices" in market_ids, "market-specific action must be present")
	_expect("clinic_read_notice" in clinic_ids, "clinic-specific action must be present")


func _test_time_changes_actions() -> void:
	var service := ServiceScript.new()
	var morning := _state_at(8 * 60, _balanced_build())
	var night := _state_at(20 * 60, _balanced_build())
	var morning_ids := _ids(service.read_models(morning, "market"))
	var night_ids := _ids(service.read_models(night, "market"))
	_expect("market_read_notices" in morning_ids, "market notices must be readable in the morning")
	_expect("market_read_notices" not in night_ids, "closed market action must disappear at night")
	var blocked := service.read_models(night, "market", {"include_blocked": true})
	var notice := _find_model(blocked, "market_read_notices")
	_expect(not notice.is_empty(), "blocked policy must be able to expose closed action")
	_expect(not bool(notice.get("available", true)), "closed action must remain non-executable")
	_expect(_has_reason(notice, "time_window_closed"), "closed action must explain its time window")


func _test_state_changes_actions() -> void:
	var service := ServiceScript.new()
	var rested := _state_at(9 * 60, _balanced_build())
	var tired := _state_at(9 * 60, _balanced_build())
	tired.set_meter("energy", 55)
	var rested_ids := _ids(service.read_models(rested, "clinic_yard"))
	var tired_ids := _ids(service.read_models(tired, "clinic_yard"))
	_expect("clinic_rest_bench" not in rested_ids, "rest action must not be offered at full energy")
	_expect("clinic_rest_bench" in tired_ids, "rest action must appear when energy is low")


func _test_characteristics_change_actions() -> void:
	var service := ServiceScript.new()
	var weak := _state_at(9 * 60, {"strength": 1, "charisma": 5, "intelligence": 4, "luck": 8})
	var strong := _state_at(9 * 60, {"strength": 8, "charisma": 5, "intelligence": 4, "luck": 1})
	var weak_ids := _ids(service.read_models(weak, "market"))
	var strong_ids := _ids(service.read_models(strong, "market"))
	_expect("market_shift_trolley" not in weak_ids, "low Strength must hide heavy action by default")
	_expect("market_shift_trolley" in strong_ids, "high Strength must open heavy action")
	var weak_models := service.read_models(weak, "market", {"include_blocked": true})
	var trolley := _find_model(weak_models, "market_shift_trolley")
	_expect(not trolley.is_empty(), "debug/help policy must expose the blocked action")
	_expect(_has_reason(trolley, "stat_too_low"), "blocked action must keep a structured characteristic reason")


func _test_reads_are_pure() -> void:
	var service := ServiceScript.new()
	var state := _state_at(8 * 60, _balanced_build())
	var before: Dictionary = state.to_dict()
	var first := ServiceScript.get_actions(
		SessionHolder.new(state),
		"underpass",
		{"include_blocked": true}
	)
	var second := service.read_models(state, "underpass", {"include_blocked": true})
	_expect_equal(state.to_dict(), before, "read-model generation must not mutate RunState, time, journal or RNG")
	_expect_equal(first, second, "same state must produce the same read-model")
	_expect(
		not ServiceScript.definition_for("underpass_map_exits").is_empty(),
		"static facade must expose a transaction-ready data definition"
	)


func _test_execute_once() -> void:
	var service := ServiceScript.new()
	var state := _state_at(8 * 60, _balanced_build())
	var before_elapsed := int(state.calendar.current_stamp().get("elapsed_minutes", -1))
	var result := ServiceScript.execute(state, "market", "market_read_notices")
	_expect(bool(result.get("ok", false)), "available local action must execute")
	_expect(not String(result.get("outcome", "")).is_empty(), "successful action must return a compact outcome")
	var after_elapsed := int(state.calendar.current_stamp().get("elapsed_minutes", -1))
	_expect_equal(after_elapsed - before_elapsed, 10, "confirmed action must advance the clock by its exact duration")
	var transaction: Dictionary = result.get("transaction", {})
	_expect_equal(_count_time_changes(Array(transaction.get("changes", []))), 1, "transaction must contain exactly one time effect")
	_expect(state.has_knowledge("market_schedule"), "effects must commit together with time")
	var snapshot: Dictionary = state.to_dict()
	var duplicate := ServiceScript.execute(state, "market", "market_read_notices")
	_expect(not bool(duplicate.get("ok", true)), "one-time action must be revalidated on repeated confirmation")
	_expect_equal(state.to_dict(), snapshot, "repeated blocked confirmation must not advance time again")


func _test_blocked_is_atomic() -> void:
	var service := ServiceScript.new()
	var state := _state_at(9 * 60, {"strength": 1, "charisma": 5, "intelligence": 4, "luck": 8})
	var before: Dictionary = state.to_dict()
	var result := ServiceScript.execute(state, "market", "market_shift_trolley")
	_expect(not bool(result.get("ok", true)), "blocked heavy action must fail")
	_expect_equal(String(result.get("code", "")), "blocked", "blocked command must use explicit code")
	_expect(not Array(result.get("blocked_reasons", [])).is_empty(), "blocked command must explain the failure")
	_expect_equal(state.to_dict(), before, "blocked command must leave the entire state untouched")


func _state_at(minute_of_day: int, build: Dictionary) -> RunState:
	var stamp := GameRules.default_start_stamp()
	stamp["minute_of_day"] = minute_of_day
	return RunState.new(build, 91_001 + minute_of_day, {}, stamp)


func _balanced_build() -> Dictionary:
	return {"strength": 5, "charisma": 5, "intelligence": 4, "luck": 4}


func _ids(models: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_model: Variant in models:
		if raw_model is Dictionary:
			result.append(String(raw_model.get("id", "")))
	return result


func _find_model(models: Array, action_id: String) -> Dictionary:
	for raw_model: Variant in models:
		if raw_model is Dictionary and String(raw_model.get("id", "")) == action_id:
			return raw_model
	return {}


func _has_reason(model: Dictionary, code: String) -> bool:
	for raw_reason: Variant in Array(model.get("reasons", [])):
		if raw_reason is Dictionary and String(raw_reason.get("code", "")) == code:
			return true
	return false


func _count_time_changes(changes: Array) -> int:
	var count := 0
	for raw_change: Variant in changes:
		if raw_change is Dictionary and String(raw_change.get("effect_type", "")) == "advance_time":
			count += 1
	return count
