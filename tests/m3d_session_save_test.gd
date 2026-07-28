extends SceneTree

const SessionScript := preload("res://game/run/run_session.gd")
const MigrationScript := preload("res://game/run/run_session_migration.gd")
const SaveScript := preload("res://game/run/run_save.gd")
const CatalogScript := preload("res://game/search/search_zone_catalog.gd")
const GeneratorScript := preload("res://game/search/search_snapshot_generator.gd")
const LocationActionService := preload("res://game/location/location_action_service.gd")
const LocationActionCommand := preload("res://game/location/location_action_command.gd")

const V3_FIXTURE := "res://tests/fixtures/m3c_session_v3.json"
const SAVE_PATH := "user://m3d_session_v4_test.json"

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _template: Dictionary = {}


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if bool(loaded.get("ok", false)):
		_template = Dictionary(loaded["template"]).duplicate(true)
	else:
		_failures.append("catalog bootstrap — %s" % str(loaded.get("errors", [])))
	_run_test("real M3C v3 fixture migrates without mutation", _test_v3_fixture)
	_run_test("current session round-trips exactly", _test_current_round_trip)
	_run_test("explicit search survives save and load", _test_search_survives_load)
	_run_test("corrupted active and archived snapshots fail closed", _test_corruption)
	_run_test("legacy phases retain their activity meanings", _test_legacy_phases)
	_run_test("search blocks normal commands centrally", _test_standard_action_guard)
	_run_test("replace_from commits only a valid complete session", _test_replace_from)
	_cleanup()

	if _failures.is_empty():
		print("M3D SESSION SAVE TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3D SESSION SAVE TESTS FAILED: %d failure(s) across %d test(s)" % [
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


func _test_v3_fixture() -> void:
	var source := _read_json(V3_FIXTURE)
	var before := JSON.stringify(source)
	var migration := MigrationScript.migrate_envelope(source)
	_expect(bool(migration.get("ok", false)), "v3 envelope must migrate: %s" % str(migration))
	_expect_equal(JSON.stringify(source), before, "migration must deep-copy its input")
	_expect_equal(migration.get("source_schema_version"), 3, "source envelope version")
	_expect_equal(migration.get("source_session_version"), 3, "source session version")
	_expect_equal(migration.get("source_run_state_version"), 3, "RunState must remain v3")
	if not bool(migration.get("ok", false)):
		return
	var migrated: Dictionary = migration["data"]
	_expect_equal(migrated.get("schema_version"), MigrationScript.CURRENT_VERSION, "envelope must reach the current version")
	_expect_equal(migrated["session"].get("session_version"), MigrationScript.CURRENT_VERSION, "session must reach the current version")
	_expect(migrated["session"].has("survival_state"), "migration must add survival state")
	_expect_equal(
		migrated["session"].get("active_activity"),
		GameSession.empty_activity(),
		"legacy redundant activity must become an empty explicit activity"
	)
	_expect_equal(migrated["session"].get("search_zone_states"), {}, "v3 starts with no zones")
	var restored := SessionScript.from_dict(source["session"])
	_expect(restored != null, "v3 session must reconstruct")
	if restored != null:
		_expect_equal(restored.run_state.get_item_count("legacy_mystery"), 4, "inventory survives v3→v4")
	var loaded := SaveScript.load_session(ProjectSettings.globalize_path(V3_FIXTURE))
	_expect(bool(loaded.get("ok", false)), "real v3 envelope must load through RunSave")
	_expect_equal(loaded.get("source_schema_version"), 3, "load reports v3 envelope")
	_expect_equal(loaded.get("source_session_version"), 3, "load reports v3 session")


func _test_current_round_trip() -> void:
	var session := SessionScript.create_location_first(_build(), 53_001)
	_expect(session != null, "session must start")
	if session == null:
		return
	_expect_equal(session.active_activity, GameSession.empty_activity(), "new run explicit activity")
	_expect_equal(session.search_zone_states, {}, "new run zone archive")
	var serialized: Dictionary = session.to_dict()
	var restored := SessionScript.from_dict(serialized)
	_expect(restored != null, "current dictionary must deserialize")
	if restored != null:
		_expect_equal(restored.to_dict(), serialized, "dictionary round-trip must be exact")
	_cleanup()
	var saved := SaveScript.save_session(session, SAVE_PATH)
	_expect(bool(saved.get("ok", false)), "current envelope must save: %s" % str(saved))
	var loaded := SaveScript.load_session(SAVE_PATH)
	_expect(bool(loaded.get("ok", false)), "current envelope must load: %s" % str(loaded))
	_expect(not bool(loaded.get("migrated", true)), "current envelope is not migrated")
	_expect_equal(loaded.get("schema_version"), MigrationScript.CURRENT_VERSION, "current envelope version")
	_expect_equal(loaded.get("source_session_version"), MigrationScript.CURRENT_VERSION, "current session version")
	_expect_equal(loaded.get("source_run_state_version"), GameRules.SAVE_VERSION, "RunState version is unchanged")


func _test_search_survives_load() -> void:
	var session := _session_with_search(53_002)
	if session == null:
		return
	var expected := session.to_dict()
	_cleanup()
	var saved := SaveScript.save_session(session, SAVE_PATH)
	_expect(bool(saved.get("ok", false)), "search session must save: %s" % str(saved))
	var loaded := SaveScript.load_session(SAVE_PATH)
	_expect(bool(loaded.get("ok", false)), "search session must load: %s" % str(loaded))
	if not bool(loaded.get("ok", false)):
		return
	var restored = loaded["session"]
	_expect_equal(restored.to_dict(), expected, "active search snapshot must round-trip exactly")
	_expect_equal(restored.phase, "map", "search must not become a legacy phase")
	_expect_equal(restored.get_active_activity().get("kind"), "search", "search remains explicit")
	_expect_equal(
		restored.search_zone_states.get(String(_template.get("id", ""))),
		session.active_activity["snapshot"],
		"archived zone snapshot survives"
	)


func _test_corruption() -> void:
	var session := _session_with_search(53_003)
	if session == null:
		return
	var corrupted_active := session.to_dict()
	corrupted_active["active_activity"]["snapshot"]["template_version"] = 99
	_expect(
		SessionScript.from_dict(corrupted_active) == null,
		"snapshot with a mismatched template version must fail"
	)
	var corrupted_archive := session.to_dict()
	var zone_id := String(_template.get("id", ""))
	corrupted_archive["active_activity"] = GameSession.empty_activity()
	corrupted_archive["search_zone_states"][zone_id]["template_version"] = 99
	_expect(
		SessionScript.from_dict(corrupted_archive) == null,
		"corrupted archived snapshot must fail"
	)
	var source_copy := corrupted_archive.duplicate(true)
	var migration := MigrationScript.migrate_session(corrupted_archive)
	_expect(not bool(migration.get("ok", true)), "current corrupted session must fail migration")
	_expect_equal(corrupted_archive, source_copy, "failed validation must not mutate source")


func _test_legacy_phases() -> void:
	var event_session := SessionScript.create(_build(), 53_004)
	_expect(event_session != null, "legacy event fixture must start")
	if event_session != null:
		var expected_event := event_session.get_active_activity()
		var restored_event := SessionScript.from_dict(_as_v3(event_session))
		_expect(restored_event != null, "legacy event session must migrate")
		if restored_event != null:
			_expect_equal(restored_event.active_activity, GameSession.empty_activity(), "event is not explicit")
			_expect_equal(restored_event.get_active_activity(), expected_event, "event meaning survives")

	var shelter_session := SessionScript.create_location_first(_build(), 53_006)
	_expect(shelter_session != null, "legacy shelter fixture must start")
	if shelter_session != null:
		shelter_session.phase = "shelter"
		var expected_shelter := shelter_session.get_active_activity()
		var restored_shelter := SessionScript.from_dict(_as_v3(shelter_session))
		_expect(restored_shelter != null, "legacy shelter session must migrate")
		if restored_shelter != null:
			_expect_equal(restored_shelter.get_active_activity(), expected_shelter, "shelter meaning survives")


func _test_standard_action_guard() -> void:
	var session := _session_with_search(53_007)
	if session == null:
		return
	_expect_equal(session.select_event().get("code"), "search_active", "events are blocked")
	_expect_equal(session.travel("market", "walk").get("code"), "search_active", "travel is blocked")
	_expect_equal(session.wait_until_evening().get("code"), "search_active", "waiting is blocked")
	_expect_equal(session.choose_shelter("underpass_niche").get("code"), "search_active", "shelter is blocked")
	var actions := LocationActionService.get_actions(
		session,
		session.location,
		{"include_blocked": true}
	)
	var available_id := ""
	for raw_action: Variant in actions:
		if raw_action is Dictionary and bool(raw_action.get("available", false)):
			available_id = String(raw_action.get("id", ""))
			break
	_expect(not available_id.is_empty(), "location must expose an action fixture")
	if not available_id.is_empty():
		var result := LocationActionCommand.execute(session, available_id)
		_expect_equal(result.get("code"), "search_active", "local action is blocked centrally")


func _test_replace_from() -> void:
	var target := SessionScript.create_location_first(_build(), 53_008)
	var source := _session_with_search(53_009)
	_expect(target != null and source != null, "replace fixtures must start")
	if target == null or source == null:
		return
	_expect(target.replace_from(source), "valid complete session must replace")
	_expect_equal(target.to_dict(), source.to_dict(), "replace copies every serialized field")
	var before := target.to_dict()
	source.active_activity["snapshot"]["template_version"] = 999
	_expect(not target.replace_from(source), "invalid source must be rejected")
	_expect_equal(target.to_dict(), before, "failed replace must be atomic")


func _session_with_search(seed: int) -> RunSession:
	if _template.is_empty():
		_expect(false, "search template must load")
		return null
	var session := SessionScript.create_location_first(_build(), seed)
	_expect(session != null, "search session must start")
	if session == null:
		return null
	var generated := GeneratorScript.generate(
		_template,
		seed,
		1,
		{"luck": session.run_state.get_characteristic("luck")}
	)
	_expect(bool(generated.get("ok", false)), "search snapshot must generate")
	if not bool(generated.get("ok", false)):
		return null
	var zone_id := String(_template["id"])
	var snapshot: Dictionary = Dictionary(generated["snapshot"]).duplicate(true)
	var replaced := session.replace_search_state(
		{"kind": "search", "id": zone_id, "snapshot": snapshot},
		{zone_id: snapshot}
	)
	_expect(bool(replaced.get("ok", false)), "search state must commit")
	return session if bool(replaced.get("ok", false)) else null


func _as_v3(session: RunSession) -> Dictionary:
	var result := session.to_dict()
	result["session_version"] = 3
	result["active_activity"] = session.get_active_activity()
	result.erase("search_zone_states")
	result.erase("world_state")
	result.erase("social_state")
	result.erase("survival_state")
	result.erase("applied_command_ids")
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return Dictionary(parsed).duplicate(true) if parsed is Dictionary else {}


func _cleanup() -> void:
	var base := ProjectSettings.globalize_path(SAVE_PATH)
	for suffix in ["", ".tmp", ".bak"]:
		var path := base + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5}


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
