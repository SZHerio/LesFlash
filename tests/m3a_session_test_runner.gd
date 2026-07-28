extends SceneTree

const GameSessionScript := preload("res://app/session/game_session.gd")
const FirstDaySessionAdapterScript := preload("res://app/session/first_day_session_adapter.gd")
const M2SessionMigrationScript := preload("res://game/first_day/first_day_session_migration.gd")
const FirstDaySessionScript := preload("res://game/first_day/first_day_session.gd")
const FirstDaySaveScript := preload("res://game/first_day/first_day_save.gd")

const V1_FIXTURE_PATH := "res://tests/fixtures/m2_first_day_v1.json"
const GAME_SESSION_V4_FIXTURE_PATH := "res://tests/fixtures/game_session_v4.json"

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _save_path := ""


func _init() -> void:
	_save_path = ProjectSettings.globalize_path(
		"res://.godot/.m3a_session_test_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_run_test("generic GameSession round-trip", _test_generic_session_round_trip)
	_run_test("physical GameSession v4 fixture migrates", _test_game_session_v4_fixture)
	_run_test("shell and location models are pure", _test_read_models_are_pure)
	_run_test("M2 commands remain available through adapter", _test_adapter_commands)
	_run_test("location actions expose completion reasons", _test_location_action_reasons)
	_run_test("RunState v1 migrates explicitly", _test_run_state_v1_migration)
	_run_test("FirstDaySession v1 migrates explicitly", _test_session_v1_migration)
	_run_test("real M2 v1 JSON migrates without data loss", _test_real_v1_json_fixture)
	_run_test("contract mismatches are rejected", _test_contract_mismatch_rejected)
	_run_test("v2 save round-trip reports versions", _test_v2_save_round_trip)
	_cleanup_save()

	if _failures.is_empty():
		print("M3A SESSION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3A SESSION TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var failures_before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == failures_before else "FAIL: %s" % test_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if not _values_equal(actual, expected):
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current_test, message, str(expected), str(actual)])


func _test_generic_session_round_trip() -> void:
	var state := RunState.new(_build(), 7_001)
	var session := GameSessionScript.new(state, "market")
	_expect(session.set_location_view_model({
		"id": "market",
		"title": "Рынок",
		"description": "Торговые ряды",
		"background_key": "market",
		"tags": ["trade"],
		"actions": [{"id": "look", "kind": "event"}],
	}), "location view-model must be accepted")
	_expect(session.begin_activity("search", "market_search", {"hero": {"x": 4, "y": 7}}), "activity must start")
	var serialized := session.to_dict()
	_expect_equal(serialized.get("session_version"), 5, "GameSession must serialize as v5")
	_expect(serialized.has("survival_state"), "GameSession v5 must persist survival state")
	var shell := session.get_shell_model()
	_expect_equal(shell.get("contract_version"), 5, "shell model must expose GameSession v5")
	var restored := GameSessionScript.from_dict(serialized)
	_expect(restored != null, "generic session must deserialize")
	if restored == null:
		return
	_expect_equal(restored.to_dict(), session.to_dict(), "generic session data must round-trip")
	_expect_equal(restored.active_activity.get("kind"), "search", "activity kind must survive")
	_expect_equal(restored.base_location, "market", "base location must survive")
	var previous := serialized.duplicate(true)
	previous["session_version"] = 4
	previous.erase("survival_state")
	var migrated_previous := GameSessionScript.from_dict(previous)
	_expect(migrated_previous != null, "GameSession v4 must migrate to v5 defaults")
	if migrated_previous != null:
		_expect_equal(
			migrated_previous.survival_state.processed_elapsed_minutes,
			state.calendar.elapsed_minutes,
			"migrated survival state must start at the recorded calendar"
		)
	_expect(session.set_base_location("underpass"), "base location must be changeable")
	var changed_location: Dictionary = session.get_location_model()
	_expect_equal(changed_location.get("id"), "underpass", "changed model must use the new location id")
	_expect_equal(changed_location.get("title"), "underpass", "stale location title must be cleared")
	_expect(Array(changed_location.get("actions", [])).is_empty(), "stale location actions must be cleared")


func _test_game_session_v4_fixture() -> void:
	var file := FileAccess.open(GAME_SESSION_V4_FIXTURE_PATH, FileAccess.READ)
	_expect(file != null, "physical GameSession v4 fixture must be readable")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "physical GameSession v4 fixture must contain a JSON object")
	if not parsed is Dictionary:
		return
	var source: Dictionary = Dictionary(parsed).duplicate(true)
	_expect_equal(source.get("session_version"), 4.0, "fixture must remain a physical v4 payload")
	_expect(not source.has("survival_state"), "v4 fixture must predate SurvivalState")
	var migrated := GameSessionScript.from_dict(source)
	_expect(migrated != null, "physical GameSession v4 fixture must migrate")
	if migrated == null:
		return
	_expect_equal(migrated.to_dict().get("session_version"), 5, "migrated session must serialize as v5")
	_expect_equal(migrated.base_location, "market", "migration must preserve the base location")
	_expect(
		migrated.applied_command_ids.has("fixture:command"),
		"migration must preserve the command ledger"
	)
	var migrated_timestamp: Dictionary = Dictionary(
		migrated.applied_command_ids["fixture:command"]
	).get("applied_at", {})
	_expect(
		typeof(migrated_timestamp.get("year")) == TYPE_INT,
		"JSON command timestamps must normalize back to integers"
	)
	_expect_equal(
		migrated.survival_state.processed_elapsed_minutes,
		migrated.run_state.calendar.elapsed_minutes,
		"migration must initialize survival at the recorded calendar"
	)
	_expect_equal(source.get("session_version"), 4.0, "migration must not mutate the physical fixture")


func _test_read_models_are_pure() -> void:
	var legacy = FirstDaySessionScript.create(_build(), 7_002)
	_expect(legacy != null, "M2 session must be created")
	if legacy == null:
		return
	var adapter := FirstDaySessionAdapterScript.new(legacy)
	var before: Dictionary = legacy.to_dict()
	var map_model: Dictionary = legacy.get_map_model()
	var shell: Dictionary = adapter.get_shell_model()
	var location: Dictionary = adapter.get_location_model()
	adapter.get_flow_model()
	adapter.get_current_event_model()
	adapter.get_summary_model()
	_expect_equal(legacy.to_dict(), before, "read models must not mutate legacy session or RNG")
	_expect_equal(shell.get("base_location_id"), legacy.location, "shell must expose base location")
	_expect_equal(location.get("id"), legacy.location, "location model must expose current location")
	_expect(typeof(location.get("actions", null)) == TYPE_ARRAY, "location model must expose actions")
	_expect_equal(shell.get("active_activity"), legacy.get_active_activity(), "shell activity must match serialized activity")
	for raw_location in Array(map_model.get("locations", [])):
		_expect(raw_location is Dictionary and raw_location.has("description"), "every map location must expose description")
	for raw_event in Array(map_model.get("events", [])):
		_expect(raw_event is Dictionary and raw_event.has("reasons"), "every map event must expose reasons")
		if raw_event is Dictionary:
			var action := _find_action(location, String(raw_event.get("id", "")))
			_expect_equal(action.get("reasons", null), raw_event.get("reasons", null), "adapter must preserve event reasons")


func _test_adapter_commands() -> void:
	var legacy = FirstDaySessionScript.create(_build(), 7_003)
	_expect(legacy != null, "M2 session must be created")
	if legacy == null:
		return
	var adapter := FirstDaySessionAdapterScript.new(legacy)
	_expect(adapter.set_setting("font_scale", 2.0), "adapter must accept the supported 200% font scale")
	_expect_equal(float(legacy.settings.get("font_scale", 0.0)), 2.0, "200% font scale must survive the compatibility contract")
	var model: Dictionary = adapter.get_current_event_model()
	var choice_id := _first_available_choice(model)
	_expect(not choice_id.is_empty(), "opening event must have an available choice")
	if choice_id.is_empty():
		return
	var revision_before := adapter.get_flow_revision()
	var result: Dictionary = adapter.resolve_choice(choice_id)
	_expect(bool(result.get("ok", false)), "adapter must delegate resolve_choice")
	_expect(adapter.get_flow_revision() > revision_before, "delegated command must advance flow revision")
	_expect_equal(adapter.get_location_id(), legacy.location, "adapter location getter must stay in sync")


func _test_location_action_reasons() -> void:
	var legacy = FirstDaySessionScript.create(_build(), 7_008)
	_expect(legacy != null, "M2 session must be created")
	if legacy == null:
		return
	legacy.phase = "map"
	legacy.current_event = ""
	legacy.location = "recycling_point"
	legacy.completed = []
	var adapter := FirstDaySessionAdapterScript.new(legacy)
	var wait_action := _find_action(adapter.get_location_model(), "wait_until_evening")
	_expect(not wait_action.is_empty(), "early map state must expose wait action")
	_expect(not String(wait_action.get("description", "")).is_empty(), "locked wait must expose description")
	_expect(not Array(wait_action.get("reasons", [])).is_empty(), "locked wait must expose structured reasons")
	# The M2 quiz is gone, so the legacy adapter must no longer offer it. The
	# modern shift is surfaced by the week facade instead.
	_expect(
		_find_action(adapter.get_location_model(), "recycling_shift").is_empty(),
		"the removed legacy shift must not appear as an action"
	)


func _test_run_state_v1_migration() -> void:
	var state := RunState.new(_build(), 7_004)
	state.add_item("legacy_item", 2)
	state.set_knowledge_level("known_place", 3)
	var legacy: Dictionary = _downgrade_run_state(state.to_dict(), 1)
	var source_copy: Dictionary = legacy.duplicate(true)
	var migration := RunState.migrate_serialized(legacy)
	_expect(bool(migration.get("ok", false)), "RunState v1 migration must succeed")
	_expect(bool(migration.get("migrated", false)), "RunState v1 migration must be reported")
	_expect_equal(migration.get("source_version"), 1, "source RunState version must be reported")
	_expect_equal(legacy, source_copy, "migration must not mutate source dictionary")
	var restored := RunState.from_dict(legacy)
	_expect(restored != null, "RunState.from_dict must accept v1 through migration")
	if restored != null:
		_expect_equal(
			_downgrade_run_state(restored.to_dict(), 1),
			source_copy,
			"RunState fields must survive v1 migration"
		)


func _test_session_v1_migration() -> void:
	var session = FirstDaySessionScript.create(_build(), 7_005)
	_expect(session != null, "M2 session must be created")
	if session == null:
		return
	var legacy := _downgrade_session(session.to_dict())
	var source_copy: Dictionary = legacy.duplicate(true)
	var migration := M2SessionMigrationScript.migrate_session(legacy)
	_expect(bool(migration.get("ok", false)), "session v1 migration must succeed")
	_expect(bool(migration.get("migrated", false)), "session v1 migration must be reported")
	_expect_equal(migration.get("source_session_version"), 1, "source session version must be reported")
	_expect_equal(migration.get("source_run_state_version"), 1, "source RunState version must be reported")
	_expect_equal(legacy, source_copy, "session migration must not mutate source dictionary")
	var restored := FirstDaySessionScript.from_dict(legacy)
	_expect(restored != null, "FirstDaySession.from_dict must accept v1")
	if restored != null:
		_expect_equal(_downgrade_session(restored.to_dict()), source_copy, "legacy session fields must survive")


func _test_real_v1_json_fixture() -> void:
	var file := FileAccess.open(V1_FIXTURE_PATH, FileAccess.READ)
	_expect(file != null, "v1 JSON fixture must be readable")
	if file == null:
		return
	var payload := file.get_as_text()
	file = null
	var parser := JSON.new()
	_expect_equal(parser.parse(payload), OK, "v1 fixture must contain valid JSON")
	if parser.data == null or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var original: Dictionary = Dictionary(parser.data).duplicate(true)
	_cleanup_save()
	var destination := FileAccess.open(_save_path, FileAccess.WRITE)
	_expect(destination != null, "v1 fixture copy must be writable")
	if destination == null:
		return
	destination.store_string(payload)
	destination.flush()
	destination = null
	var loaded: Dictionary = FirstDaySaveScript.load_session(_save_path)
	_expect(bool(loaded.get("ok", false)), "real v1 envelope must load: %s" % String(loaded.get("error", "")))
	_expect(bool(loaded.get("migrated", false)), "full-chain migration must be reported")
	_expect_equal(loaded.get("source_schema_version"), 1, "source envelope version must be reported")
	_expect_equal(loaded.get("source_session_version"), 1, "source session version must be reported")
	_expect_equal(loaded.get("source_run_state_version"), 1, "source state version must be reported")
	var restored = loaded.get("session")
	_expect(restored != null, "migrated fixture must reconstruct a session")
	if restored == null:
		return
	_expect_equal(restored.location, original["session"]["location"], "legacy location must survive")
	_expect_equal(restored.current_event, original["session"]["current_event"], "legacy event must survive")
	_expect_equal(restored.run_state.meters["mental_state"], original["session"]["run_state"]["meters"]["morale"], "legacy morale value becomes mental_state exactly")
	_expect_equal(restored.get_active_activity().get("id"), "clinic_blister", "active event must migrate")
	_expect_equal(restored.run_state.journal.size(), 3, "legacy journal must be retained")
	var source_after := FileAccess.open(_save_path, FileAccess.READ)
	_expect(source_after != null, "migrated source must remain readable")
	if source_after != null:
		var after_parser := JSON.new()
		_expect_equal(after_parser.parse(source_after.get_as_text()), OK, "source save must remain valid JSON")
		_expect_equal(after_parser.data, original, "loading must not rewrite the v1 source JSON")
		source_after = null


func _test_contract_mismatch_rejected() -> void:
	var session = FirstDaySessionScript.create(_build(), 7_006)
	_expect(session != null, "M2 session must be created")
	if session == null:
		return
	var mismatch: Dictionary = session.to_dict()
	mismatch["base_location"] = "different_location"
	var source_copy := mismatch.duplicate(true)
	var migration := M2SessionMigrationScript.migrate_session(mismatch)
	_expect(not bool(migration.get("ok", true)), "location mismatch must be rejected")
	_expect_equal(mismatch, source_copy, "failed migration must not mutate source")
	_expect(FirstDaySessionScript.from_dict(mismatch) == null, "deserializer must reject mismatched contract")


func _test_v2_save_round_trip() -> void:
	_cleanup_save()
	var session = FirstDaySessionScript.create(_build(), 7_007)
	_expect(session != null, "M2 session must be created")
	if session == null:
		return
	var expected: Dictionary = session.to_dict()
	var saved: Dictionary = FirstDaySaveScript.save_session(session, _save_path)
	_expect(bool(saved.get("ok", false)), "current session must save")
	var loaded: Dictionary = FirstDaySaveScript.load_session(_save_path)
	_expect(bool(loaded.get("ok", false)), "current session must load")
	_expect(not bool(loaded.get("migrated", true)), "current save must not report migration")
	_expect_equal(loaded.get("schema_version"), M2SessionMigrationScript.CURRENT_VERSION, "current envelope version must be current")
	_expect_equal(loaded.get("source_session_version"), M2SessionMigrationScript.CURRENT_VERSION, "current session version must be current")
	_expect_equal(loaded.get("source_run_state_version"), GameRules.SAVE_VERSION, "current state version must be current")
	var restored = loaded.get("session")
	_expect(restored != null, "loaded current session must exist")
	if restored != null:
		_expect_equal(restored.to_dict(), expected, "current session must round-trip exactly")


func _downgrade_session(current: Dictionary) -> Dictionary:
	var result := current.duplicate(true)
	result["session_version"] = 1
	result.erase("base_location")
	result.erase("active_activity")
	result.erase("search_zone_states")
	result.erase("world_state")
	result.erase("social_state")
	result.erase("survival_state")
	result.erase("applied_command_ids")
	if result.get("run_state") is Dictionary:
		result["run_state"] = _downgrade_run_state(result["run_state"], 1)
	return result


func _downgrade_run_state(current: Dictionary, version: int) -> Dictionary:
	var result := current.duplicate(true)
	result["save_version"] = version
	var legacy_inventory: Dictionary = {}
	if result.get("inventory", {}) is Dictionary:
		var inventory: Dictionary = result["inventory"]
		for group_name in ["containers", "external_containers"]:
			var group: Dictionary = inventory.get(group_name, {})
			for container_value in group.values():
				if not container_value is Dictionary:
					continue
				for stack_value in Array(container_value.get("stacks", [])):
					if not stack_value is Dictionary:
						continue
					var item_id := String(stack_value.get("item_id", ""))
					legacy_inventory[item_id] = (
						int(legacy_inventory.get(item_id, 0))
						+ int(stack_value.get("quantity", 0))
					)
	result["inventory"] = legacy_inventory
	if result.get("skills", {}) is Dictionary:
		result["skills"].erase("search")
	if result.get("meters", {}) is Dictionary and result["meters"].has("mental_state"):
		result["meters"]["morale"] = result["meters"]["mental_state"]
		result["meters"].erase("mental_state")
	return result


func _first_available_choice(model: Dictionary) -> String:
	for value in Array(model.get("options", [])):
		if value is Dictionary and not bool(value.get("locked", false)):
			return String(value.get("id", ""))
	return ""


func _find_action(model: Dictionary, action_id: String) -> Dictionary:
	for value in Array(model.get("actions", [])):
		if value is Dictionary and String(value.get("id", "")) == action_id:
			return Dictionary(value)
	return {}


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 5, "intelligence": 4, "luck": 4}


func _values_equal(actual: Variant, expected: Variant) -> bool:
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	if actual_type in [TYPE_INT, TYPE_FLOAT] and expected_type in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(actual), float(expected))
	if actual_type != expected_type:
		return false
	if actual is Dictionary:
		if actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not _values_equal(actual[key], expected[key]):
				return false
		return true
	if actual is Array:
		if actual.size() != expected.size():
			return false
		for index in range(expected.size()):
			if not _values_equal(actual[index], expected[index]):
				return false
		return true
	return actual == expected


func _cleanup_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = _save_path + String(suffix)
		if not _save_path.is_empty() and FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
