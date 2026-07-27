extends SceneTree

const WorldCatalog := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)
const WorldFactory := preload("res://game/content/world_state_factory.gd")
const SessionTransaction := preload(
	"res://game/session/session_command_transaction.gd"
)
const GameSessionScript := preload("res://app/session/game_session.gd")

const PROCESS_ID := "process_recycling_inspection"

var _catalog: Dictionary = {}
var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	var loaded := WorldCatalog.load_default()
	if bool(loaded.get("ok", false)):
		_catalog = Dictionary(loaded.get("catalog", {})).duplicate(true)
	else:
		_failures.append("bootstrap — %s" % str(loaded.get("errors", [])))
	_run("confirmed time advances the process inside one session commit", _test_commit)
	_run("autonomous planning failure rolls the whole command back", _test_rollback)
	if _failures.is_empty():
		print("M3F.4 WORLD PROCESS SESSION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.4 WORLD PROCESS SESSION TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_commit() -> void:
	var session := _session()
	if session == null:
		return
	var result := SessionTransaction.execute(session, {
		"command_id": "m3f4_wait_for_notice",
		"source_id": "m3f4_time_fixture",
		"title": "Переждать сутки",
		"conditions": [],
		"effects": [{"type": "advance_time", "minutes": 1440}],
	}, {"world_definitions": _catalog})
	_expect(bool(result.get("ok", false)), "timed command succeeds")
	_expect_equal(session.run_state.calendar.elapsed_minutes, 1440, "time commits")
	_expect_equal(session.world_state.process_stage(PROCESS_ID), "warning", "process commits")
	var autonomous: Dictionary = result.get("autonomous_world_process", {})
	_expect(bool(autonomous.get("advanced", false)), "result exposes autonomous transition")
	_expect_equal(autonomous.get("to_stage_id"), "warning", "result exposes target stage")
	var committed := session.to_dict()
	var duplicate := SessionTransaction.execute(session, {
		"command_id": "m3f4_wait_for_notice",
		"source_id": "duplicate_must_not_run",
		"conditions": [],
		"effects": [{"type": "advance_time", "minutes": 1440}],
	}, {"world_definitions": _catalog})
	_expect_equal(duplicate.get("code"), "already_applied", "retry is idempotent")
	_expect_equal(session.to_dict(), committed, "retry changes neither time nor world")


func _test_rollback() -> void:
	var session := _session()
	if session == null:
		return
	var before := session.to_dict()
	var invalid_catalog := _catalog.duplicate(true)
	var process: Dictionary = Array(invalid_catalog["processes"])[0]
	process.erase("advance_mode")
	var result := SessionTransaction.execute(session, {
		"command_id": "m3f4_invalid_autonomous_plan",
		"source_id": "m3f4_failure_fixture",
		"title": "Некорректный проход времени",
		"conditions": [],
		"effects": [{"type": "advance_time", "minutes": 1440}],
	}, {"world_definitions": invalid_catalog})
	_expect(not bool(result.get("ok", true)), "invalid process contract rejects command")
	_expect_equal(
		result.get("code"),
		"autonomous_world_process_failed",
		"failure crosses the typed integration boundary"
	)
	_expect_equal(session.to_dict(), before, "time, world and command ledger roll back together")


func _session() -> GameSession:
	if _catalog.is_empty():
		_expect(false, "world catalog must load")
		return null
	var run_state := RunState.new({
		"strength": 5,
		"charisma": 4,
		"intelligence": 5,
		"luck": 4,
	}, 1_980_104)
	var world := WorldFactory.from_catalog(_catalog, run_state.calendar.current_stamp())
	if world == null:
		_expect(false, "world factory creates state")
		return null
	var session := GameSessionScript.new(
		run_state,
		"recycling_point",
		{},
		world,
		SocialState.fresh(),
		{}
	)
	_expect(bool(session.validate().get("ok", false)), "session fixture validates")
	return session


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_expect(false, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
