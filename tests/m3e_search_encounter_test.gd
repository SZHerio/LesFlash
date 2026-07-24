extends SceneTree

## M3D ↔ M3E seam: a search that raises enough attention must produce a real,
## answerable encounter, and answering it must be atomic, idempotent and must
## hand the zone back to the player.

const SessionScript := preload("res://game/first_day/first_day_session.gd")
const SaveScript := preload("res://game/first_day/first_day_save.gd")
const Service := preload("res://game/search/search_session_service.gd")
const Encounter := preload("res://game/events/search_encounter_command.gd")
const RiskResolver := preload("res://game/search/search_risk_resolver.gd")

const ZONE_ID := "underpass_service_yard"
const ZONE_LOCATION_ID := "underpass"
## Slipping through the market fence costs 8 trespass, which crosses the
## threshold in a single decision.
const TRESPASS_OBJECT := "market_fence"
const TRESPASS_APPROACH := "slip_through"

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _save_path := "user://m3e_search_encounter_test.json"


func _init() -> void:
	_run_test("crossing the risk threshold queues an answerable card", _test_queued)
	_run_test("a pending encounter holds back new decisions only", _test_guard)
	_run_test("answering is atomic, idempotent and relieves risk", _test_resolve)
	_run_test("a blocked option changes nothing and keeps its reason", _test_blocked)
	_run_test("an answered card goes on cooldown and is remembered", _test_cooldown)
	_run_test("a pending encounter survives save and load", _test_persistence)

	if _failures.is_empty():
		print("M3E SEARCH ENCOUNTER TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3E SEARCH ENCOUNTER TESTS FAILED: %d failure(s) across %d test(s)" % [
		_failures.size(),
		_tests_run,
	])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)


func _test_queued() -> void:
	var session := _session_with_encounter(92_001)
	if session == null:
		return
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var encounter: Dictionary = snapshot.get("pending_encounter", {})
	_expect_equal(encounter.get("status"), "pending", "encounter must be queued")
	_expect(
		not String(encounter.get("card_id", "")).is_empty(),
		"a queued encounter must already own its card"
	)
	var pending := Encounter.pending(session)
	_expect_ok(pending, "pending read model must resolve")
	_expect(bool(pending.get("active", false)), "read model must report an active encounter")
	var preview: Dictionary = pending.get("preview", {})
	_expect_equal(
		preview.get("card_id"),
		encounter.get("card_id"),
		"preview must describe the stored card"
	)
	var options: Array = preview.get("options", [])
	_expect(options.size() >= 2, "an encounter must offer a real choice")
	var available := 0
	for raw_option: Variant in options:
		if raw_option is Dictionary and bool(raw_option.get("available", false)):
			available += 1
	_expect(available >= 1, "a reachable card must always keep one available exit")


func _test_guard() -> void:
	var session := _session_with_encounter(92_002)
	if session == null:
		return
	var before := session.to_dict()
	var blocked := Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"guard:interact"
	)
	_expect_equal(
		blocked.get("code"),
		"encounter_pending",
		"a new decision must wait for the answer"
	)
	_expect_equal(session.to_dict(), before, "the refused decision must change nothing")
	var quick := Service.quick_search(session, "guard:quick")
	_expect_equal(
		quick.get("code"),
		"encounter_pending",
		"quick search must wait for the answer too"
	)
	var moved := Service.plan_move(session, "open_dumpster", "guard:move")
	_expect_ok(moved, "walking away must stay available")
	var finished := Service.finish_search(session, "guard:finish")
	_expect_ok(finished, "leaving the zone must never be blocked")


func _test_resolve() -> void:
	var session := _session_with_encounter(92_003)
	if session == null:
		return
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var risk_before := int(Dictionary(snapshot.get("risk", {})).get("score", 0))
	var option := _first_available_option_model(session)
	var option_id := String(option.get("id", ""))
	if option_id.is_empty():
		_expect(false, "fixture must expose an available option")
		return
	var expected_minutes := 0
	for raw_effect: Variant in Array(option.get("effects", [])):
		if raw_effect is Dictionary and String(raw_effect.get("type", "")) == "advance_time":
			expected_minutes += int(raw_effect.get("minutes", 0))
	var minutes_before := int(session.run_state.calendar.elapsed_minutes)
	var journal_before := session.run_state.journal.size()
	var result := Encounter.resolve(session, option_id, "resolve:1")
	_expect_ok(result, "answering must commit")
	if not bool(result.get("ok", false)):
		return
	_expect(bool(result.get("encounter_resolved", false)), "result must report resolution")
	var after: Dictionary = session.active_activity["snapshot"]
	_expect(
		Dictionary(after.get("pending_encounter", {})).is_empty(),
		"an answered encounter must be cleared"
	)
	_expect_equal(
		int(session.run_state.calendar.elapsed_minutes) - minutes_before,
		expected_minutes,
		"answering must spend exactly the time its answer declares"
	)
	_expect_equal(
		session.run_state.journal.size(),
		journal_before + 1,
		"answering must leave exactly one journal entry"
	)
	var risk_after := int(Dictionary(after.get("risk", {})).get("score", 0))
	_expect(risk_after < risk_before, "answering must discharge some attention")
	_expect(
		risk_after < RiskResolver.ENCOUNTER_THRESHOLD,
		"risk must fall back under the threshold so it can build again"
	)
	var committed := session.to_dict()
	var retry := Encounter.resolve(session, option_id, "resolve:1")
	_expect_equal(retry.get("code"), "duplicate_command", "answering must be idempotent")
	_expect_equal(session.to_dict(), committed, "a retry must not apply effects twice")
	var interaction := Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"resolve:after"
	)
	_expect(
		String(interaction.get("code", "")) != "encounter_pending",
		"the zone must be playable again after the answer"
	)


func _test_blocked() -> void:
	var session := _session_with_encounter(92_004, {
		"strength": 8, "charisma": 1, "intelligence": 8, "luck": 1
	})
	if session == null:
		return
	var pending := Encounter.pending(session)
	var blocked_id := ""
	for raw_option: Variant in Array(Dictionary(pending.get("preview", {})).get("options", [])):
		if raw_option is Dictionary and not bool(raw_option.get("available", false)):
			blocked_id = String(raw_option.get("id", ""))
			_expect(
				not Array(raw_option.get("blocked_reasons", [])).is_empty(),
				"a closed answer must keep its reason"
			)
			break
	if blocked_id.is_empty():
		return
	var before := session.to_dict()
	var result := Encounter.resolve(session, blocked_id, "blocked:1")
	_expect_equal(result.get("code"), "option_blocked", "a closed answer must be refused")
	_expect_equal(session.to_dict(), before, "a refused answer must change nothing")


func _test_cooldown() -> void:
	var session := _session_with_encounter(92_005)
	if session == null:
		return
	var card_id := String(
		Dictionary(session.active_activity["snapshot"].get("pending_encounter", {})).get(
			"card_id",
			""
		)
	)
	var option_id := _first_available_option(session)
	if option_id.is_empty():
		return
	_expect_ok(Encounter.resolve(session, option_id, "cooldown:1"), "answer must commit")
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var cooldowns: Dictionary = snapshot.get("encounter_cooldowns", {})
	_expect(cooldowns.has(card_id), "an answered card must record a cooldown")
	_expect(
		int(cooldowns.get(card_id, 0)) > int(session.run_state.calendar.elapsed_minutes),
		"the cooldown must still be in the future"
	)
	var history: Array = snapshot.get("encounter_history", [])
	_expect(history.size() == 1, "answering must record exactly one history fact")


func _test_persistence() -> void:
	var session := _session_with_encounter(92_006)
	if session == null:
		return
	var expected := session.to_dict()
	_expect(
		bool(SaveScript.save_session(session, _save_path).get("ok", false)),
		"session with a pending encounter must save"
	)
	var loaded := SaveScript.load_session(_save_path)
	_expect_ok(loaded, "session with a pending encounter must load")
	var restored = loaded.get("session")
	if restored == null:
		return
	_expect_equal(restored.to_dict(), expected, "a pending encounter must round-trip exactly")
	var pending := Encounter.pending(restored)
	_expect(
		bool(pending.get("active", false)),
		"the restored run must still owe the same answer"
	)
	_expect_equal(
		Dictionary(pending.get("preview", {})).get("card_id"),
		Dictionary(Encounter.pending(session).get("preview", {})).get("card_id"),
		"the card must not be re-rolled by a reload"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))


func _session_with_encounter(
	seed: int,
	build: Dictionary = {}
) -> FirstDaySession:
	var selected := _build() if build.is_empty() else build
	var session := SessionScript.create_location_first(selected, seed)
	if session == null:
		_expect(false, "session must start")
		return null
	session.location = ZONE_LOCATION_ID
	if not bool(Service.begin_search(session, ZONE_ID, "begin:%d" % seed).get("ok", false)):
		_expect(false, "search fixture must begin")
		return null
	if not _move_to(session, TRESPASS_OBJECT, "risk:%d" % seed):
		return null
	var result := Service.confirm_interaction(
		session,
		TRESPASS_OBJECT,
		TRESPASS_APPROACH,
		"risk:%d:interact" % seed
	)
	_expect_ok(result, "trespass decision must commit")
	if not bool(result.get("ok", false)):
		return null
	if Dictionary(session.active_activity["snapshot"].get("pending_encounter", {})).is_empty():
		_expect(false, "the fixture decision must raise a real encounter")
		return null
	return session


func _first_available_option(session: FirstDaySession) -> String:
	return String(_first_available_option_model(session).get("id", ""))


func _first_available_option_model(session: FirstDaySession) -> Dictionary:
	var pending := Encounter.pending(session)
	for raw_option: Variant in Array(Dictionary(pending.get("preview", {})).get("options", [])):
		if raw_option is Dictionary and bool(raw_option.get("available", false)):
			return Dictionary(raw_option).duplicate(true)
	return {}


func _move_to(session: FirstDaySession, object_id: String, prefix: String) -> bool:
	var plan := Service.plan_move(session, object_id, "%s:plan" % prefix)
	_expect_ok(plan, "movement plan for %s" % object_id)
	if not bool(plan.get("ok", false)):
		return false
	var path: Array = Dictionary(plan["path"]).get("points", [])
	var result := Service.checkpoint_move(
		session,
		path.back(),
		path.size() - 1,
		true,
		"%s:checkpoint" % prefix
	)
	_expect_ok(result, "movement checkpoint for %s" % object_id)
	return bool(result.get("ok", false))


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 6, "intelligence": 4, "luck": 3}


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s: %s" % [message, str(result)])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current_test,
			message,
			str(expected),
			str(actual),
		])
