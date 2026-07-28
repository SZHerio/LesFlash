extends SceneTree

## M5: a paper must be obtainable, and obtaining it must be atomic.
##
## This exists because gating the porter's shift behind a sanitary book without
## a counter to issue it would have locked the job forever — a regression that
## looks like content and reads like a bug.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const Command = preload("res://game/content/qualification_session_command.gd")

const BUILD := {"strength": 6, "charisma": 4, "intelligence": 4, "luck": 4}

var _failures: Array[String] = []


func _init() -> void:
	_test_counter_is_reachable()
	_test_obtaining_is_atomic_and_once()
	_test_wrong_counter_refuses()
	_test_porter_needs_its_paper()
	_finish()


func _adapter(location_id: String) -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 7_707)
	var session = adapter.get("_session")
	session.location = location_id
	session.phase = "map"
	return adapter


func _test_counter_is_reachable() -> void:
	var adapter: SandboxSessionAdapter = _adapter("station_square")
	var session = adapter.get("_session")
	session.run_state.money = 400
	session.run_state.knowledge["district_services"] = 1
	var offers: Array = Command.available(session)
	var slip: Dictionary = {}
	for raw: Variant in offers:
		if String(Dictionary(raw).get("id", "")) == "qual_residence_slip":
			slip = raw
	_expect(not slip.is_empty(), "the residence slip is not offered where it should be")
	if slip.is_empty():
		return
	_expect(
		Array(slip.get("reasons", [])).is_empty(),
		"a hero with the money and the knowledge was refused: %s" % str(slip.get("reasons"))
	)
	# It must also surface as an ordinary location action, or no screen shows it.
	var found := false
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if String(Dictionary(raw_action).get("kind", "")) == "qualification":
			found = true
	_expect(found, "the counter never reaches the location read-model")


func _test_obtaining_is_atomic_and_once() -> void:
	var adapter: SandboxSessionAdapter = _adapter("station_square")
	var session = adapter.get("_session")
	session.run_state.money = 400
	session.run_state.knowledge["district_services"] = 1
	var money_before := int(session.run_state.money)
	var elapsed_before := int(session.run_state.calendar.elapsed_minutes)

	var result: Dictionary = adapter.obtain_qualification("qual_residence_slip")
	_expect(bool(result.get("ok", false)), "the slip was refused: %s" % str(result))
	_expect(
		session.run_state.holds_qualification("qual_residence_slip"),
		"the slip was not recorded after a successful obtain"
	)
	_expect(int(session.run_state.money) < money_before, "the fee was never charged")
	_expect(
		int(session.run_state.calendar.elapsed_minutes) > elapsed_before,
		"standing in a queue cost no time"
	)

	var again: Dictionary = adapter.obtain_qualification("qual_residence_slip")
	_expect(not bool(again.get("ok", true)), "the same paper was issued twice")

	# A refusal must leave nothing behind.
	var poor: SandboxSessionAdapter = _adapter("station_square")
	var poor_session = poor.get("_session")
	poor_session.run_state.knowledge["district_services"] = 1
	poor_session.run_state.money = 0
	var refused: Dictionary = poor.obtain_qualification("qual_residence_slip")
	_expect(not bool(refused.get("ok", true)), "a penniless hero was given the slip")
	_expect(
		not poor_session.run_state.holds_qualification("qual_residence_slip"),
		"a refused obtain still recorded the paper"
	)
	_expect(int(poor_session.run_state.calendar.elapsed_minutes) == 0, "a refusal spent time")


func _test_wrong_counter_refuses() -> void:
	var adapter: SandboxSessionAdapter = _adapter("embankment")
	var session = adapter.get("_session")
	session.run_state.money = 400
	session.run_state.knowledge["district_services"] = 1
	var result: Dictionary = adapter.obtain_qualification("qual_residence_slip")
	_expect(
		not bool(result.get("ok", true)),
		"a paper was issued from a place that does not issue it"
	)


## The porter now needs a sanitary book. That gate is only fair because the book
## can be earned, which the test above proves; here we check the gate holds.
func _test_porter_needs_its_paper() -> void:
	var adapter: SandboxSessionAdapter = _adapter("market")
	var session = adapter.get("_session")
	session.run_state.calendar.advance_minutes(60)
	var offered := false
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if String(Dictionary(raw_action).get("kind", "")) == "job_shift":
			offered = true
	_expect(not offered, "the porter's shift was offered without the sanitary book")

	session.run_state.grant_qualification("qual_sanitary_book")
	var now_offered := false
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if String(Dictionary(raw_action).get("kind", "")) == "job_shift":
			now_offered = true
	_expect(now_offered, "the shift stayed shut even with the paper in hand")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M5 QUALIFICATION FLOW TESTS PASSED: 4/4")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 QUALIFICATION FLOW: %s" % failure)
	quit(1)
