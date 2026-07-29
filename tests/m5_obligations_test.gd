extends SceneTree

## M5 stage 6: what he owes, and by when.
##
## This is the thing that makes a month different from a week. Everything else
## the hero does is a decision about today; an obligation is a decision he made
## a week ago, arriving to be paid for whether today suits or not.
##
## What has to hold: a room is cheaper than paying nightly but binds him to a
## date, the date arrives whether or not he opens the ledger, three misses end
## the arrangement, and none of it can be outrun.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const Housing = preload("res://game/housing/housing_catalog.gd")
const Obligations = preload("res://game/obligations/obligation_state.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const ROOM := "room_station_lodging"

var _failures: Array[String] = []


func _init() -> void:
	_test_a_room_must_beat_paying_nightly()
	_test_taking_a_room_costs_and_binds()
	_test_the_day_arrives_whether_he_looks_or_not()
	_test_paying_moves_the_date()
	_test_three_misses_end_it()
	_test_the_ledger_survives_a_save()
	_test_a_rented_room_is_a_bed()
	_finish()


func _adapter(location_id: String = "station_square") -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
		return null
	var session = adapter.get("_session")
	session.location = location_id
	if "base_location" in session:
		session.base_location = location_id
	session.phase = "map"
	return adapter


## Moves the clock the way a lived week would. The survival marker moves with
## it: the session refuses to clone when the calendar and the body disagree.
func _let_days_pass(session: Object, days: int) -> void:
	session.run_state.calendar.advance_minutes(days * 1440)
	var survival = session.get("survival_state")
	if survival != null:
		survival.processed_elapsed_minutes = int(session.run_state.calendar.elapsed_minutes)


## An arrangement that is not cheaper than paying as you go is a worse deal with
## a due date attached, and nobody would ever take it.
func _test_a_room_must_beat_paying_nightly() -> void:
	var loaded := Housing.load_default()
	_expect(bool(loaded.get("ok", false)), "the housing catalog must load: %s" % str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]
	for raw_room: Variant in Array(catalog.get("rooms", [])):
		var room: Dictionary = raw_room
		@warning_ignore("integer_division")
		var nightly := int(room["rent_ard"]) / int(room["rent_every_days"])
		_expect(
			nightly < Housing.NIGHTLY_ROOM_PRICE,
			"%s costs %d a night against %d for paying as you go" % [
				String(room["id"]), nightly, Housing.NIGHTLY_ROOM_PRICE,
			]
		)
	var overpriced: Dictionary = catalog.duplicate(true)
	Dictionary(Array(overpriced["rooms"])[0])["rent_ard"] = 5_000
	_expect(
		not bool(Housing.validate(overpriced).get("ok", true)),
		"a room dearer than paying nightly was accepted"
	)


func _test_taking_a_room_costs_and_binds() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.money = 100
	_expect(
		not bool(adapter.take_room(ROOM).get("ok", true)),
		"a room was taken without the deposit"
	)
	session.run_state.money = 1_000
	var before := int(session.run_state.money)
	var taken: Dictionary = adapter.take_room(ROOM)
	_expect(bool(taken.get("ok", false)), "the room was refused: %s" % str(taken))
	if not bool(taken.get("ok", false)):
		return
	_expect(int(session.run_state.money) < before, "deposit and first rent were never paid")
	var ledger := adapter.get_obligation_ledger()
	_expect_equal(ledger.size(), 1, "taking a room did not put anything in the ledger")
	if ledger.is_empty():
		return
	_expect_equal(String(Dictionary(ledger[0]).get("kind", "")), Obligations.RENT, "the debt is not rent")
	_expect(
		int(Dictionary(ledger[0]).get("days_left", 0)) > 0,
		"the rent was due the moment it was taken on"
	)
	_expect(
		not bool(adapter.take_room(ROOM).get("ok", true)),
		"the same room was rented twice"
	)


## The point of the whole stage: he cannot get away with not looking.
func _test_the_day_arrives_whether_he_looks_or_not() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.money = 1_000
	adapter.take_room(ROOM)
	# Six days: the rent falls due on the fifth, and a run ends on the seventh.
	_let_days_pass(session, 6)
	var due: Dictionary = adapter.settle_what_is_due()
	_expect(bool(due.get("ok", false)), "the reckoning failed: %s" % str(due))
	_expect(
		Array(due.get("missed", [])).size() == 1,
		"a week passed and the rent day did not arrive"
	)
	var ledger := adapter.get_obligation_ledger()
	_expect_equal(
		int(Dictionary(ledger[0]).get("missed", 0)),
		1,
		"the missed day was not recorded against him"
	)


func _test_paying_moves_the_date() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.money = 1_000
	adapter.take_room(ROOM)
	var obligation_id := Housing.rent_obligation_id(ROOM)
	var before := int(session.run_state.money)
	var paid: Dictionary = adapter.pay_obligation(obligation_id)
	_expect(bool(paid.get("ok", false)), "paying the rent failed: %s" % str(paid))
	if not bool(paid.get("ok", false)):
		return
	_expect(int(session.run_state.money) < before, "the rent was not handed over")
	var ledger := adapter.get_obligation_ledger()
	_expect_equal(ledger.size(), 1, "paying rent ended the arrangement")
	_expect(
		int(Dictionary(ledger[0]).get("days_left", 0)) >= 9,
		"paying did not push the next rent day a full period out"
	)
	# And he cannot pay what he does not have.
	session.run_state.money = 0
	_expect(
		not bool(adapter.pay_obligation(obligation_id).get("ok", true)),
		"rent was paid out of an empty pocket"
	)


func _test_three_misses_end_it() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.money = 1_000
	adapter.take_room(ROOM)
	var obligation_id := Housing.rent_obligation_id(ROOM)
	var obligations: ObligationState = session.get("obligation_state")
	var broken := false
	for miss: int in Obligations.MISSES_BEFORE_BROKEN:
		broken = obligations.miss(obligation_id)
	_expect(broken, "three missed rent days did not end the arrangement")
	_expect(obligations.is_broken(obligation_id), "the room was not lost")
	_expect(
		not bool(adapter.pay_obligation(obligation_id).get("ok", true)),
		"he paid rent on a room he no longer has"
	)
	_expect(
		not bool(adapter.take_room(ROOM).get("ok", true)),
		"he moved straight back into the room he was thrown out of"
	)


func _test_the_ledger_survives_a_save() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.money = 1_000
	adapter.take_room(ROOM)
	var restored = session.clone()
	_expect(restored != null, "a session owing rent failed to clone")
	if restored != null:
		_expect(
			restored.obligation_state.has(Housing.rent_obligation_id(ROOM)),
			"the rent was forgotten on reload"
		)
	var saved: Dictionary = session.to_dict()
	saved.erase("obligation_state")
	var older = session.get_script().from_dict(saved)
	_expect(older != null, "a save written before anything came due no longer opens")
	if older != null:
		_expect_equal(
			older.obligation_state.records.size(),
			0,
			"migration invented a debt nobody took on"
		)


## Renting has to buy something, or it is a due date with nothing attached. The
## bed the room points at stops costing money while the arrangement is live, and
## the list and the confirmed sleep must agree about that.
func _test_a_rented_room_is_a_bed() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	var loaded := Housing.load_default()
	if not bool(loaded.get("ok", false)):
		return
	var room := Housing.find(Dictionary(loaded["catalog"]), ROOM)
	var shelter_id := String(room.get("shelter_id", ""))
	session.run_state.money = 1_000
	adapter.take_room(ROOM)
	var found := false
	for raw_option: Variant in adapter.available_shelters():
		var option: Dictionary = raw_option
		if String(option.get("id", "")) != shelter_id:
			continue
		found = true
		_expect_equal(
			int(option.get("price_arden", -1)),
			0,
			"the bed he already pays rent on was charged for again"
		)
	_expect(found, "the room he rents does not appear as somewhere to sleep")

	# And when the arrangement ends, the bed is somebody else's again.
	var obligations: ObligationState = session.get("obligation_state")
	for _miss: int in Obligations.MISSES_BEFORE_BROKEN:
		obligations.miss(Housing.rent_obligation_id(ROOM))
	for raw_option: Variant in adapter.available_shelters():
		var option: Dictionary = raw_option
		if String(option.get("id", "")) == shelter_id:
			_expect(
				int(option.get("price_arden", 0)) > 0 or bool(option.get("locked", false)),
				"a room he was thrown out of is still free to him"
			)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 OBLIGATIONS TESTS PASSED: 7/7")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 OBLIGATIONS: %s" % failure)
	quit(1)
