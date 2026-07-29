extends SceneTree

## M5 stage 1: the week a person means to have, and living it unattended.
##
## The claims that matter are not "the code runs". They are: a plan survives a
## save, a routine cannot be made of activities that do not exist, and — the one
## the whole idea stands on — the runner hands control back rather than pushing
## the hero through a week he should have been asked about.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const RoutineStateScript = preload("res://game/routine/routine_state.gd")
const CatalogScript = preload("res://game/routine/routine_catalog.gd")
const RunnerScript = preload("res://app/routine/routine_runner.gd")
const RoutesScript = preload("res://game/district/district_routes.gd")

## Eighteen points, which is the whole budget. A build that does not spend
## exactly that is refused by the domain, and an adapter that was never created
## makes every check below pass by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_week_is_divided_the_same_way_everywhere()
	_test_catalog_describes_a_liveable_week()
	_test_plan_survives_a_save()
	_test_a_save_without_a_routine_still_opens()
	_test_the_plan_refuses_impossible_entries()
	_test_following_needs_something_to_follow()
	_test_every_place_can_be_reached()
	_test_the_routine_is_lived()
	_test_need_stops_the_routine()
	_finish()


func _adapter() -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	# Calling a method on a null adapter aborts the test quietly and the suite
	# reports success for checks that never ran. It has to be loud.
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
	return adapter


# --- the shape of the week --------------------------------------------------


func _test_week_is_divided_the_same_way_everywhere() -> void:
	_expect_equal(WeekSchedule.day_of_week(0), 1, "the run opens on the first day of the week")
	_expect_equal(WeekSchedule.day_of_week(6 * 1440), 7, "the seventh day is the last")
	_expect_equal(WeekSchedule.day_of_week(7 * 1440), 1, "the week comes round again")
	_expect_equal(WeekSchedule.block_of_minute(8 * 60), "morning", "eight in the morning is morning")
	_expect_equal(WeekSchedule.block_of_minute(14 * 60), "day", "two in the afternoon is the day")
	_expect_equal(WeekSchedule.block_of_minute(20 * 60), "evening", "eight at night is the evening")
	_expect_equal(WeekSchedule.block_of_minute(2 * 60), "night", "two in the morning is still the night")
	_expect_equal(WeekSchedule.block_of_minute(23 * 60 + 30), "night", "half past eleven is the night")
	# Every stretch has to end, or a routine written against it never advances.
	for block_id: String in WeekSchedule.BLOCK_IDS:
		var start := int(Dictionary(WeekSchedule.BLOCKS[block_id])["starts_minute"])
		_expect(
			WeekSchedule.minutes_left_in_block(start) > 0,
			"%s must have time left in it at its own start" % block_id
		)
	_expect_equal(WeekSchedule.minutes_until_block(8 * 60, "morning"), 0, "the current stretch is now")
	_expect(WeekSchedule.minutes_until_block(8 * 60, "evening") > 0, "the evening is still ahead at eight")


func _test_catalog_describes_a_liveable_week() -> void:
	var loaded := CatalogScript.load_default()
	_expect(bool(loaded.get("ok", false)), "the routine catalog must load: %s" % str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]
	_expect(
		not CatalogScript.for_block(catalog, "night").is_empty(),
		"there must be something to do with a night"
	)
	# Sleeping is a night thing; a shift is not. A catalog that lets them swap
	# would let a player write a week nobody can keep.
	var night_kinds: Array[String] = []
	for entry: Dictionary in CatalogScript.for_block(catalog, "night"):
		night_kinds.append(String(entry.get("kind", "")))
	_expect("job_shift" not in night_kinds, "a shift was offered for the night")

	var broken: Dictionary = catalog.duplicate(true)
	Dictionary(Array(broken["activities"])[0])["blocks"] = ["полдень"]
	_expect(
		not bool(CatalogScript.validate(broken).get("ok", true)),
		"a catalog naming a stretch of the day that does not exist was accepted"
	)


# --- the plan ---------------------------------------------------------------


func _test_plan_survives_a_save() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	var result: Dictionary = adapter.set_routine_block(2, "morning", "routine_shift_yard")
	_expect(bool(result.get("ok", false)), "writing one stretch of the week failed: %s" % str(result))
	var session = adapter.get("_session")
	_expect_equal(
		session.routine_state.activity_for(2, "morning"),
		"routine_shift_yard",
		"the plan did not record what was written"
	)
	_expect_equal(session.routine_state.activity_for(2, "day"), "", "writing one stretch filled another")

	var restored = session.clone()
	_expect(restored != null, "a session holding a plan failed to clone")
	if restored != null:
		_expect_equal(
			restored.routine_state.activity_for(2, "morning"),
			"routine_shift_yard",
			"the plan was lost on a round trip"
		)

	# Clearing has to be sayable: a week with gaps is a decision.
	_expect(bool(adapter.set_routine_block(2, "morning", "").get("ok", false)), "clearing a stretch failed")
	_expect_equal(session.routine_state.activity_for(2, "morning"), "", "the stretch was not cleared")


func _test_a_save_without_a_routine_still_opens() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	var session = adapter.get("_session")
	var saved: Dictionary = session.to_dict()
	saved.erase("routine_state")
	var reopened = session.get_script().from_dict(saved)
	_expect(reopened != null, "a save written before routines existed no longer opens")
	if reopened != null:
		_expect_equal(
			reopened.routine_state.planned_count(),
			0,
			"migration invented a week nobody planned"
		)


func _test_the_plan_refuses_impossible_entries() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	_expect(
		not bool(adapter.set_routine_block(1, "night", "routine_shift_yard").get("ok", true)),
		"a shift was accepted for the night"
	)
	_expect(
		not bool(adapter.set_routine_block(1, "morning", "routine_nothing_at_all").get("ok", true)),
		"an activity that does not exist was accepted"
	)
	_expect(
		not bool(adapter.set_routine_block(9, "morning", "routine_rest").get("ok", true)),
		"a ninth day of the week was accepted"
	)
	var session = adapter.get("_session")
	_expect_equal(session.routine_state.planned_count(), 0, "a refused edit still changed the plan")


func _test_following_needs_something_to_follow() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	_expect(
		not bool(adapter.set_routine_following(true).get("ok", true)),
		"an empty week was followed"
	)
	_expect(bool(adapter.set_routine_block(1, "morning", "routine_rest").get("ok", false)), "planning failed")
	_expect(bool(adapter.set_routine_following(true).get("ok", false)), "a planned week was not followed")
	var session = adapter.get("_session")
	_expect(session.routine_state.following, "following was not recorded")
	# Abandoning a plan must not erase it.
	_expect(bool(adapter.set_routine_following(false).get("ok", false)), "the plan could not be abandoned")
	_expect_equal(session.routine_state.planned_count(), 1, "abandoning the plan erased it")


func _test_every_place_can_be_reached() -> void:
	var reach := RoutesScript.every_place_is_reachable()
	_expect(
		bool(reach.get("ok", false)),
		"some places cannot be reached from others: %s" % str(reach.get("unreachable", []))
	)


# --- living it --------------------------------------------------------------


func _test_the_routine_is_lived() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	var session = adapter.get("_session")
	for day: int in range(1, WeekSchedule.DAYS_PER_WEEK + 1):
		adapter.set_routine_block(day, "morning", "routine_rest")
		adapter.set_routine_block(day, "night", "routine_sleep")
	_expect(bool(adapter.set_routine_following(true).get("ok", false)), "the week could not be followed")

	var before := int(session.run_state.calendar.elapsed_minutes)
	var report: Dictionary = adapter.follow_routine(3)
	_expect(bool(report.get("ok", false)), "following the routine failed outright: %s" % str(report))
	_expect(
		int(session.run_state.calendar.elapsed_minutes) > before,
		"following the routine cost no time at all"
	)
	# Whatever happened, it must say what it was and why it stopped.
	_expect(
		String(report.get("stopped", "")) != "",
		"the runner did not say why it handed control back"
	)
	if String(report.get("stopped", "")) not in [RunnerScript.STOP_DONE]:
		_expect(
			String(report.get("reason", "")) != "",
			"the runner stopped as %s without a reason" % String(report.get("stopped", ""))
		)


func _test_need_stops_the_routine() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	var session = adapter.get("_session")
	adapter.set_routine_block(1, "morning", "routine_rest")
	adapter.set_routine_following(true)
	# A hero this hungry has one thing to do, and it is not what he wrote down.
	session.run_state.set_meter("hunger", 95)
	var report: Dictionary = adapter.follow_routine(2)
	_expect_equal(
		String(report.get("stopped", "")),
		RunnerScript.STOP_NEED,
		"hunger did not interrupt the routine (stopped=%s)" % String(report.get("stopped", ""))
	)
	_expect(
		String(report.get("reason", "")).strip_edges() != "",
		"the interruption did not say what was wrong"
	)
	_expect(
		Array(report.get("carried", [])).is_empty(),
		"the routine carried something out despite being interrupted first"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 ROUTINE TESTS PASSED: 9/9")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 ROUTINE: %s" % failure)
	quit(1)
