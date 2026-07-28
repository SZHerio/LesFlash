extends SceneTree

## M5 groundwork: a skill grows from varied practice.
##
## Before this a rank could only be handed out by legacy content, so in the week
## sandbox no skill could be raised at all — the game checked skills it gave the
## player no way to earn. The rule here is the one the shift already used for
## mastery: what counts is how many *different* things the hero has done, not
## how many times he repeated the easy one.

const RunStateScript = preload("res://core/state/run_state.gd")
const EffectApplier = preload("res://core/rules/effect_applier.gd")
const EffectScript = preload("res://core/rules/effect.gd")

const BUILD := {"strength": 6, "charisma": 3, "intelligence": 5, "luck": 4}

var _failures: Array[String] = []


func _init() -> void:
	_test_repetition_teaches_nothing()
	_test_varied_practice_earns_rank()
	_test_rank_never_falls()
	_test_effect_records_practice()
	_test_practice_survives_save()
	_test_migration_keeps_earned_ranks()
	_finish()


func _state() -> RunState:
	return RunStateScript.new(BUILD, 4242)


func _test_repetition_teaches_nothing() -> void:
	var state := _state()
	for _attempt: int in 20:
		state.record_practice("repair", "fixed_the_same_scale")
	_expect_equal(state.practice_sources("repair"), 1, "a repeated source counted more than once")
	_expect_equal(state.get_skill_rank("repair"), 0, "repetition alone raised a rank")


func _test_varied_practice_earns_rank() -> void:
	var state := _state()
	var thresholds: Array = GameRules.SKILL_PRACTICE_FOR_RANK
	for index: int in int(thresholds[0]):
		state.record_practice("trade", "haggle_%d" % index)
	_expect_equal(state.get_skill_rank("trade"), 1, "three different practices did not earn the first rank")
	for index: int in range(int(thresholds[0]), int(thresholds[1])):
		state.record_practice("trade", "haggle_%d" % index)
	_expect_equal(state.get_skill_rank("trade"), 2, "the second rank did not arrive on schedule")
	for index: int in range(int(thresholds[1]), int(thresholds[2])):
		state.record_practice("trade", "haggle_%d" % index)
	_expect_equal(state.get_skill_rank("trade"), 3, "the third rank did not arrive on schedule")
	# Mastery is the ceiling; nothing beyond it.
	for index: int in range(int(thresholds[2]), int(thresholds[2]) + 6):
		state.record_practice("trade", "haggle_%d" % index)
	_expect_equal(state.get_skill_rank("trade"), GameRules.SKILL_MAX_RANK, "practice pushed past mastery")


## A rank already held is knowledge the hero has. Practice may raise it and must
## never take it away.
func _test_rank_never_falls() -> void:
	var state := _state()
	state.set_skill_rank("cooking", 2)
	state.record_practice("cooking", "boiled_water")
	_expect_equal(state.get_skill_rank("cooking"), 2, "recording practice lowered an earned rank")
	_expect_equal(state.practice_sources("cooking"), 1, "the practice was not recorded")


func _test_effect_records_practice() -> void:
	var state := _state()
	var first: Dictionary = EffectApplier.apply_one(state, EffectScript.practice_skill(&"search", &"underpass_niche"))
	_expect(bool(first.get("ok", false)), "the practice effect was rejected: %s" % str(first))
	_expect_equal(state.practice_sources("search"), 1, "the effect did not record its source")

	var unnamed: Dictionary = EffectApplier.apply_one(state, {"type": "practice_skill", "id": "search"})
	_expect(
		not bool(unnamed.get("ok", true)),
		"practice without a source was accepted, so repetition could be laundered"
	)
	var unknown: Dictionary = EffectApplier.apply_one(
		state, {"type": "practice_skill", "id": "alchemy", "source_id": "x"}
	)
	_expect(not bool(unknown.get("ok", true)), "practice was recorded for an unknown skill")


func _test_practice_survives_save() -> void:
	var state := _state()
	for index: int in 4:
		state.record_practice("first_aid", "bandaged_%d" % index)
	var restored: RunState = RunStateScript.from_dict(state.to_dict())
	_expect(restored != null, "a state carrying practice failed to reload")
	if restored == null:
		return
	_expect_equal(restored.practice_sources("first_aid"), 4, "practice was lost on reload")
	_expect_equal(restored.get_skill_rank("first_aid"), 1, "the earned rank was lost on reload")
	# A duplicate source in a save is corruption, not a rounding error.
	var broken: Dictionary = state.to_dict()
	broken["skill_practice"] = {"first_aid": ["a", "a"]}
	_expect(
		RunStateScript.from_dict(broken) == null,
		"a save with a repeated practice source was accepted"
	)


## A save written before practice existed keeps whatever ranks it had: the hero
## does not forget what he could do yesterday because the bookkeeping changed.
func _test_migration_keeps_earned_ranks() -> void:
	var state := _state()
	state.set_skill_rank("cargo_handling", 2)
	var legacy: Dictionary = state.to_dict()
	legacy.erase("skill_practice")
	legacy["save_version"] = GameRules.RUN_STATE_VERSION_V4
	var migrated: RunState = RunStateScript.from_dict(legacy)
	_expect(migrated != null, "a version 4 run state no longer loads")
	if migrated == null:
		return
	_expect_equal(migrated.get_skill_rank("cargo_handling"), 2, "migration dropped an earned rank")
	_expect_equal(migrated.practice_sources("cargo_handling"), 0, "migration invented practice")
	_expect_equal(
		int(migrated.to_dict()["save_version"]),
		GameRules.SAVE_VERSION,
		"migration did not reach the current version"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 SKILL PRACTICE TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 SKILL PRACTICE: %s" % failure)
	quit(1)
