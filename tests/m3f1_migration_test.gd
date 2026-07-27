extends SceneTree

const RunSave := preload("res://core/save/run_state_save.gd")
const FirstDaySessionScript := preload("res://game/first_day/first_day_session.gd")
const FirstDayMigration := preload("res://game/first_day/first_day_session_migration.gd")
const FirstDaySave := preload("res://game/first_day/first_day_save.gd")
const EventContextScript := preload("res://game/events/event_context.gd")
const EventCatalogScript := preload("res://game/events/event_catalog.gd")
const SearchCatalog := preload("res://game/search/search_zone_catalog.gd")
const SearchGenerator := preload("res://game/search/search_snapshot_generator.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")

const RUN_V2_FIXTURE := "res://tests/fixtures/run_state_envelope_v2.json"
const SESSION_V4_FIXTURE := "res://tests/fixtures/m3f1_session_v4.json"

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("new life starts in 1980 with exact renamed state", _test_fresh_start)
	_run("previous RunState envelope migrates without changing 1970", _test_run_state_fixture)
	_run("previous session envelope migrates every schema level", _test_session_fixture)
	_run("ambiguous morale migration fails without mutation", _test_ambiguous_meter)
	_run("EventContext v1 migrates exactly to v2", _test_event_context_migration)
	_run("active and archived encounter contexts migrate inside search", _test_nested_context_migration)
	_run("legacy event catalog becomes current data in memory", _test_event_catalog_migration)
	if _failures.is_empty():
		print("M3F.1 MIGRATION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.1 MIGRATION TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_fresh_start() -> void:
	var state := _state()
	var stamp := state.calendar.current_stamp()
	_expect_equal(stamp["year"], 1980, "fresh calendar year")
	_expect_equal(stamp["month"], 9, "fresh calendar month")
	_expect_equal(stamp["day"], 1, "fresh calendar day")
	_expect_equal(stamp["minute_of_day"], 480, "fresh start time")
	_expect_equal(state.get_age_years(), 18, "fresh age")
	_expect_equal(state.birth_date["year"], 1962, "birth year follows fresh calendar")
	_expect(state.meters.has("mental_state"), "current meter exists")
	_expect(not state.meters.has("morale"), "legacy meter is absent")
	_expect_equal(state.money, 0, "no starting money")
	_expect(InventoryStateScript.all_stacks(state.inventory).is_empty(), "no starting items")
	var session := FirstDaySessionScript.create_location_first(_build(), 1_980_111)
	_expect(session != null, "fresh sandbox session starts")
	if session != null:
		_expect_equal(session.world_state.metrics.size(), 5, "fresh session receives world defaults")
		_expect_equal(session.world_state.process_stage("process_recycling_inspection"), "latent", "fresh process starts at latent")


func _test_run_state_fixture() -> void:
	var source := _read_json(RUN_V2_FIXTURE)
	var before := JSON.stringify(source)
	var migration := RunState.migrate_serialized(Dictionary(source.get("run_state", {})))
	_expect(bool(migration.get("ok", false)), "RunState v3 migrates: %s" % str(migration))
	_expect_equal(JSON.stringify(source), before, "migration does not mutate parsed source")
	if not bool(migration.get("ok", false)):
		return
	var migrated: Dictionary = migration["data"]
	_expect_equal(migrated.get("save_version"), 4, "RunState reaches v4")
	_expect_equal(migrated["meters"].get("mental_state"), 50, "meter value is exact")
	_expect(not migrated["meters"].has("morale"), "legacy key removed")
	_expect_equal(migrated["calendar"]["stamp"]["year"], 1970, "recorded year is preserved")
	_expect_equal(migrated["birth_date"]["year"], 1952, "recorded birth date is preserved")
	_expect_equal(migrated["rng"]["seed"], "1970180001", "RNG seed is preserved")
	var loaded := RunSave.load_state(ProjectSettings.globalize_path(RUN_V2_FIXTURE))
	_expect(bool(loaded.get("ok", false)), "previous envelope loads")
	_expect_equal(loaded.get("source_schema_version"), 2, "source envelope version is reported")
	_expect_equal(loaded.get("source_run_state_version"), 3, "source state version is reported")
	if bool(loaded.get("ok", false)):
		_expect_equal(loaded["state"].calendar.current_stamp()["year"], 1970, "loaded run remains in 1970")


func _test_session_fixture() -> void:
	var source := _read_json(SESSION_V4_FIXTURE)
	var before := JSON.stringify(source)
	var migration := FirstDayMigration.migrate_envelope(source)
	_expect(bool(migration.get("ok", false)), "v4 envelope migrates: %s" % str(migration))
	_expect_equal(JSON.stringify(source), before, "session migration deep-copies its source")
	if not bool(migration.get("ok", false)):
		return
	var data: Dictionary = migration["data"]
	_expect_equal(data.get("schema_version"), 5, "envelope reaches v5")
	_expect_equal(data["session"].get("session_version"), 5, "session reaches v5")
	_expect_equal(data["session"]["run_state"].get("save_version"), 4, "nested RunState reaches v4")
	_expect_equal(data["session"]["run_state"]["calendar"]["stamp"]["year"], 1970, "legacy calendar is preserved")
	_expect(data["session"].has("world_state"), "world state is added")
	_expect(data["session"].has("social_state"), "social state is added")
	_expect_equal(data["session"].get("applied_command_ids"), {}, "command ledger starts empty")
	var loaded := FirstDaySave.load_session(ProjectSettings.globalize_path(SESSION_V4_FIXTURE))
	_expect(bool(loaded.get("ok", false)), "previous full envelope loads: %s" % str(loaded))
	_expect_equal(loaded.get("source_schema_version"), 4, "source envelope reported")
	_expect_equal(loaded.get("source_session_version"), 4, "source session reported")
	_expect_equal(loaded.get("source_run_state_version"), 3, "source RunState reported")


func _test_ambiguous_meter() -> void:
	var source := _state().to_dict()
	source["save_version"] = 3
	source["meters"]["morale"] = source["meters"]["mental_state"]
	var before := source.duplicate(true)
	var migration := RunState.migrate_serialized(source)
	_expect(not bool(migration.get("ok", true)), "ambiguous state is rejected")
	_expect_equal(migration.get("code"), "ambiguous_mental_state", "failure is diagnostic")
	_expect_equal(source, before, "failed migration leaves source intact")


func _test_event_context_migration() -> void:
	var current := _context(_state())
	var legacy := _as_event_context_v1(current)
	var before := legacy.duplicate(true)
	var migration := EventContextScript.migrate_serialized(legacy)
	_expect(bool(migration.get("ok", false)), "EventContext v1 migrates: %s" % str(migration))
	_expect_equal(legacy, before, "EventContext source is unchanged")
	if not bool(migration.get("ok", false)):
		return
	var migrated: Dictionary = migration["data"]
	_expect_equal(migrated.get("schema_version"), 2, "context reaches v2")
	_expect_equal(migrated["actor"]["meters"].get("mental_state"), 50, "context meter is exact")
	_expect_equal(migrated["world"], {"revision": 0, "facts": {}, "metrics": {}, "processes": {}}, "legacy world is explicit and empty")
	_expect(bool(EventContextScript.validate(migrated).get("ok", false)), "migrated context validates")


func _test_nested_context_migration() -> void:
	var loaded := SearchCatalog.load_default()
	_expect(bool(loaded.get("ok", false)), "search template loads")
	if not bool(loaded.get("ok", false)):
		return
	var session := FirstDaySessionScript.create_location_first(_build(), 19_803)
	_expect(session != null, "legacy session fixture starts")
	if session == null:
		return
	var template: Dictionary = loaded["template"]
	var generated := SearchGenerator.generate(template, 19_803, 1, {"luck": 4})
	_expect(bool(generated.get("ok", false)), "search snapshot generates")
	if not bool(generated.get("ok", false)):
		return
	var zone_id := String(template["id"])
	var snapshot: Dictionary = generated["snapshot"]
	var legacy_context := _as_event_context_v1(_context(session.run_state))
	snapshot["pending_encounter"] = {"card_id": "yard_noise", "context": legacy_context}
	var replaced := session.replace_search_state(
		{"kind": "search", "id": zone_id, "snapshot": snapshot},
		{zone_id: snapshot.duplicate(true)}
	)
	_expect(bool(replaced.get("ok", false)), "nested fixture is a valid search session")
	if not bool(replaced.get("ok", false)):
		return
	var legacy_session := session.to_dict()
	legacy_session["session_version"] = 4
	legacy_session.erase("world_state")
	legacy_session.erase("social_state")
	legacy_session.erase("applied_command_ids")
	legacy_session["run_state"] = _as_run_state_v3(legacy_session["run_state"])
	var before := legacy_session.duplicate(true)
	var migration := FirstDayMigration.migrate_session(legacy_session)
	_expect(bool(migration.get("ok", false)), "nested contexts migrate: %s" % str(migration))
	_expect_equal(legacy_session, before, "nested migration is non-destructive")
	if not bool(migration.get("ok", false)):
		return
	var migrated: Dictionary = migration["data"]
	_expect_equal(migrated["active_activity"]["snapshot"]["pending_encounter"]["context"]["schema_version"], 2, "active context reaches v2")
	_expect_equal(migrated["search_zone_states"][zone_id]["pending_encounter"]["context"]["schema_version"], 2, "archived context reaches v2")


func _test_event_catalog_migration() -> void:
	var loaded := EventCatalogScript.load_default()
	_expect(bool(loaded.get("ok", false)), "legacy source catalog loads through migration")
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]
	_expect_equal(catalog.get("schema_version"), 2, "runtime event catalog is v2")
	_expect(int(catalog.get("cards", []).size()) <= 100, "v2 budget allows at most 100 cards")
	for raw_card: Variant in Array(catalog.get("cards", [])):
		var card: Dictionary = raw_card
		_expect(card.has("family_id") and card.has("max_occurrences") and card.has("causal_category"), "v2 card metadata is complete")


func _context(state: RunState) -> Dictionary:
	return EventContextScript.build(state, {
		"kind": "search", "id": "underpass_service_yard_v1", "action_id": "inspect", "object_id": "waste_container",
	}, {
		"location_id": "underpass", "era_id": "ard_1980", "weather_id": "dry",
		"relationships": {"npc_viktor_koren": {"trust": 0, "respect": 0, "affinity": 0, "fear": 0}},
	})


func _as_event_context_v1(current: Dictionary) -> Dictionary:
	var legacy := current.duplicate(true)
	legacy["schema_version"] = 1
	legacy.erase("world")
	legacy.erase("npc_memories")
	legacy.erase("commitments")
	legacy["actor"]["meters"]["morale"] = legacy["actor"]["meters"]["mental_state"]
	legacy["actor"]["meters"].erase("mental_state")
	return legacy


func _as_run_state_v3(current: Dictionary) -> Dictionary:
	var legacy := current.duplicate(true)
	legacy["save_version"] = 3
	legacy["meters"]["morale"] = legacy["meters"]["mental_state"]
	legacy["meters"].erase("mental_state")
	return legacy


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "fixture cannot be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_expect(false, "fixture is invalid JSON: %s" % path)
		return {}
	return parsed


func _state() -> RunState:
	return RunState.new(_build(), 1_980_180_001)


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 5, "luck": 4}


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_expect(false, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
