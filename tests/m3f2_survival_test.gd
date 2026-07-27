extends SceneTree

const SurvivalStateScript := preload("res://game/survival/survival_state.gd")
const TimeRules := preload("res://game/survival/survival_time_rules.gd")
const PassageCommand := preload("res://game/survival/survival_passage_command.gd")
const FoodProfile := preload("res://game/survival/food_effect_profile.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("survival state validates and round-trips", _test_state_round_trip)
	_run("unconfirmed passage changes nothing", _test_confirmation_gate)
	_run("sixty minutes equals six ten-minute chunks", _test_interval_equivalence)
	_run("food profile is validated described and previewed", _test_food_profile)
	_run("health depletion ends the run at the exact minute", _test_death)
	_run("seven days end at the exact prototype boundary", _test_week_complete)
	if _failures.is_empty():
		print("M3F.2 SURVIVAL TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.2 SURVIVAL TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_state_round_trip() -> void:
	var state := SurvivalStateScript.fresh(120)
	state.remainders["hunger"] = 17
	state.record_applied("fixture:one")
	var restored := SurvivalStateScript.from_dict(state.to_dict())
	_expect(restored != null, "serialized state must restore")
	if restored != null:
		_expect_equal(restored.to_dict(), state.to_dict(), "round-trip must be exact")
	var json_data: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	var from_json := SurvivalStateScript.from_dict(json_data)
	_expect(from_json != null, "integral JSON numbers must restore")
	var invalid := state.to_dict()
	invalid["schema_version"] = 2
	_expect(SurvivalStateScript.from_dict(invalid) == null, "unknown version must fail closed")
	invalid = state.to_dict()
	invalid["remainders"]["energy"] = 1.5
	_expect(SurvivalStateScript.from_dict(invalid) == null, "fractional remainder must be rejected")


func _test_confirmation_gate() -> void:
	var run := _run_state()
	var survival := SurvivalStateScript.fresh(run.calendar.elapsed_minutes)
	var before_run := run.to_dict()
	var before_survival := survival.to_dict()
	var result := PassageCommand.execute(run, survival, {
		"passage_id": "unconfirmed:walk",
		"confirmed": false,
		"minutes": 20,
		"reason": "Неподтверждённый путь",
	})
	_expect_equal(result.get("code"), "not_confirmed", "unconfirmed request must be explicit")
	_expect_equal(run.to_dict(), before_run, "calendar and meters must remain unchanged")
	_expect_equal(survival.to_dict(), before_survival, "fixed-point state must remain unchanged")


func _test_interval_equivalence() -> void:
	var meters := _meters()
	meters["hunger"] = 74
	meters["energy"] = 26
	meters["tension"] = 80
	var whole_state := SurvivalStateScript.fresh(0)
	var split_state := SurvivalStateScript.fresh(0)
	var whole := TimeRules.simulate(meters, whole_state, 60)
	var split_meters := meters.duplicate(true)
	for _index: int in range(6):
		var chunk := TimeRules.simulate(split_meters, split_state, 10)
		_expect(bool(chunk.get("ok", false)), "every ten-minute chunk must resolve")
		if not bool(chunk.get("ok", false)):
			return
		split_meters = chunk["meters"]
		split_state = chunk["survival_state"]
	_expect(bool(whole.get("ok", false)), "whole interval must resolve")
	if not bool(whole.get("ok", false)):
		return
	_expect_equal(split_meters, whole["meters"], "meter result must not depend on chunking")
	_expect_equal(split_state.remainders, whole["survival_state"].remainders, "fractional debt must match")
	_expect_equal(split_state.processed_elapsed_minutes, whole["survival_state"].processed_elapsed_minutes, "processed time must match")
	_expect(int(whole["meters"]["hunger"]) > int(meters["hunger"]), "hunger must progress with confirmed time")
	_expect(int(whole["meters"]["energy"]) < int(meters["energy"]), "energy must progress with confirmed time")
	_expect(int(whole["meters"]["health"]) < int(meters["health"]), "severe deprivation must affect health")
	_expect(int(whole["meters"]["mental_state"]) < int(meters["mental_state"]), "severe deprivation must affect mental state")

	var whole_run := _run_state()
	var split_run := _run_state()
	for key: String in meters:
		whole_run.set_meter(key, int(meters[key]))
		split_run.set_meter(key, int(meters[key]))
	var whole_lifecycle := SurvivalStateScript.fresh(0)
	var split_lifecycle := SurvivalStateScript.fresh(0)
	_expect(bool(PassageCommand.execute(whole_run, whole_lifecycle, {
		"passage_id": "whole:60", "confirmed": true, "minutes": 60,
	}).get("ok", false)), "whole confirmed command must commit")
	for index: int in range(6):
		_expect(bool(PassageCommand.execute(split_run, split_lifecycle, {
			"passage_id": "split:%d" % index, "confirmed": true, "minutes": 10,
		}).get("ok", false)), "split confirmed command must commit")
	_expect_equal(split_run.meters, whole_run.meters, "atomic command preserves interval equivalence")
	_expect_equal(split_run.calendar.current_stamp(), whole_run.calendar.current_stamp(), "calendar result is equivalent")
	_expect_equal(split_lifecycle.remainders, whole_lifecycle.remainders, "committed fixed-point debt is equivalent")


func _test_food_profile() -> void:
	var profile := {
		"schema_version": 1,
		"profile_id": "food_hot_porridge",
		"title": "Горячая каша",
		"consumption_minutes": 12,
		"effects": [
			{"type": "change_state", "id": "hunger", "delta": -28},
			{"type": "change_state", "id": "energy", "delta": 6},
			{"type": "change_state", "id": "mental_state", "delta": 3},
		],
	}
	var before := profile.duplicate(true)
	_expect(bool(FoodProfile.validate(profile).get("ok", false)), "authored profile must validate")
	var description := FoodProfile.describe(profile)
	_expect_equal(description.get("summary_ru"), "Голод -28 · Энергия +6 · Психика +3 · 12 мин", "description must disclose exact effects")
	var effects := FoodProfile.command_effects(profile)
	_expect_equal(Array(effects.get("effects", [])).size(), 4, "profile compiles to time and meter effects")
	var meters := _meters()
	meters["hunger"] = 20
	meters["energy"] = 98
	var preview := FoodProfile.preview(profile, meters)
	_expect_equal(preview["meters"]["hunger"], 0, "preview clamps hunger")
	_expect_equal(preview["meters"]["energy"], 100, "preview clamps energy")
	_expect_equal(profile, before, "validation and preview must be pure")
	var invalid := profile.duplicate(true)
	invalid["effects"] = [{"type": "change_state", "id": "hunger", "delta": 5}]
	_expect(not bool(FoodProfile.validate(invalid).get("ok", true)), "harm-only value is not a food benefit profile")


func _test_death() -> void:
	var run := _run_state()
	run.set_meter("health", 1)
	run.set_meter("hunger", 100)
	run.set_meter("energy", 0)
	var survival := SurvivalStateScript.fresh(run.calendar.elapsed_minutes)
	var result := PassageCommand.execute(run, survival, {
		"passage_id": "fatal:wait",
		"confirmed": true,
		"minutes": 120,
		"reason": "Ожидание без еды",
		"profile": {"hunger_units_per_minute": 0, "energy_drain_units_per_minute": 0},
	})
	_expect(bool(result.get("ok", false)), "fatal passage must commit deterministically")
	_expect_equal(run.get_meter("health"), 0, "health reaches zero")
	_expect_equal(survival.status, SurvivalStateScript.STATUS_DEAD, "lifecycle becomes dead")
	_expect_equal(survival.death_reason, "deprivation", "death reason is saved")
	_expect(int(result.get("consumed_minutes", 0)) > 0 and int(result.get("consumed_minutes", 0)) < 120, "passage stops on the exact fatal minute")
	var snapshot := run.to_dict()
	var duplicate := PassageCommand.execute(run, survival, {
		"passage_id": "fatal:wait",
		"confirmed": true,
		"minutes": 120,
	})
	_expect_equal(duplicate.get("code"), "already_applied", "replay is idempotent")
	_expect_equal(run.to_dict(), snapshot, "replay changes nothing")


func _test_week_complete() -> void:
	var run := _run_state()
	var survival := SurvivalStateScript.fresh(run.calendar.elapsed_minutes)
	var result := PassageCommand.execute(run, survival, {
		"passage_id": "week:quiet",
		"confirmed": true,
		"minutes": SurvivalStateScript.WEEK_MINUTES + 90,
		"reason": "Проверочный переход недели",
		"profile": {"hunger_units_per_minute": 0, "energy_drain_units_per_minute": 0},
	})
	_expect(bool(result.get("ok", false)), "safe week passage must commit")
	_expect_equal(result.get("consumed_minutes"), SurvivalStateScript.WEEK_MINUTES, "passage clips to exact week boundary")
	_expect_equal(result.get("unconsumed_minutes"), 90, "caller can see unused requested time")
	_expect_equal(run.calendar.elapsed_minutes, SurvivalStateScript.WEEK_MINUTES, "calendar ends exactly after seven days")
	_expect_equal(survival.status, SurvivalStateScript.STATUS_WEEK_COMPLETE, "lifecycle becomes week_complete")
	_expect(bool(survival.validate().get("ok", false)), "terminal state remains valid")


func _run_state() -> RunState:
	return RunState.new({"strength": 5, "charisma": 4, "intelligence": 5, "luck": 4}, 1_980_202)


func _meters() -> Dictionary:
	return {
		"health": 100,
		"hunger": 0,
		"energy": 100,
		"tension": 0,
		"mental_state": 50,
	}


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_expect(false, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
