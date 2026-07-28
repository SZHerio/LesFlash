extends SceneTree

const LegacySession := preload("res://game/first_day/first_day_session.gd")
const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const CityMapModels := preload("res://app/map/city_map_view_model.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _save_path := ""


func _init() -> void:
	_save_path = ProjectSettings.globalize_path(
		"res://.godot/.m3b_session_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_run_test("legacy and location-first starts remain separate", _test_start_contracts)
	_run_test("Luck and seed expose at least three starts", _test_start_variety)
	_run_test("map reads are pure", _test_map_reads_are_pure)
	_run_test("invalid travel is atomic", _test_invalid_travel_is_atomic)
	_run_test("confirmed travel advances once", _test_confirmed_travel)
	_run_test("ordinary location action advances once", _test_location_action)
	_run_test("map read-model groups transport and price", _test_map_view_model)
	_run_test("sandbox save round-trip survives action and travel", _test_save_round_trip)
	_run_test("matching temporary save promotes in-process", _test_matching_temporary_promotes)
	_run_test("different temporary save is never promoted", _test_different_temporary_is_rejected)
	_cleanup_save()

	if _failures.is_empty():
		print("M3B SESSION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3B SESSION TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)


func _test_start_contracts() -> void:
	var legacy = LegacySession.create(_build(4), 31_001)
	var sandbox = LegacySession.create_location_first(_build(4), 31_001)
	_expect(legacy != null and sandbox != null, "both constructors must create valid sessions")
	if legacy == null or sandbox == null:
		return
	_expect_equal(legacy.phase, "event", "legacy M2 constructor must retain its opening event")
	_expect(not legacy.current_event.is_empty(), "legacy opening event must remain present")
	_expect_equal(sandbox.phase, "map", "product constructor must start at the location")
	_expect_equal(sandbox.current_event, "", "product constructor must not force an event")
	_expect(sandbox.seen.is_empty(), "unseen opening event must not leak into history")
	_expect(bool(sandbox.validate().get("ok", false)), "location-first session must validate")


func _test_start_variety() -> void:
	var locations: Dictionary = {}
	for luck in [1, 4, 7, 10]:
		for seed in range(32_000, 32_024):
			var adapter = SandboxAdapter.create(_build(luck), seed) as SandboxSessionAdapter
			_expect(adapter != null, "sandbox adapter creation failed for Luck %d" % luck)
			if adapter != null:
				locations[adapter.get_location_id()] = true
	_expect(locations.size() >= 3, "Luck/seed sampling must reach at least three start points: %s" % str(locations.keys()))


func _test_map_reads_are_pure() -> void:
	var session = LegacySession.create_location_first(_build(4), 33_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var before: Dictionary = session.to_dict()
	adapter.get_city_map_model()
	adapter.get_city_map_model()
	var location_model: Dictionary = adapter.get_location_model()
	adapter.get_shell_model()
	_expect_equal(session.to_dict(), before, "map/location reads must not change time, RNG, revision or state")
	for raw_action in Array(location_model.get("actions", [])):
		if raw_action is Dictionary:
			_expect(String(raw_action.get("kind", "")) != "event", "events must not be permanent location buttons")


func _test_invalid_travel_is_atomic() -> void:
	var session = LegacySession.create_location_first(_build(4), 34_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var before: Dictionary = session.to_dict()
	var result := adapter.travel("missing_place", "walk")
	_expect(not bool(result.get("ok", true)), "unknown route must fail")
	_expect_equal(session.to_dict(), before, "failed travel must leave the whole session untouched")


func _test_confirmed_travel() -> void:
	var session = LegacySession.create_location_first(_build(4), 35_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var route := _first_available_route(adapter.get_city_map_model())
	_expect(not route.is_empty(), "start must expose an available route")
	if route.is_empty():
		return
	var before_time := int(session.run_state.calendar.elapsed_minutes)
	var before_revision: int = int(session.flow_revision)
	var destination := String(route.get("destination_id", ""))
	var mode := String(route.get("mode", "walk"))
	var result := adapter.travel(destination, mode)
	_expect(bool(result.get("ok", false)), "confirmed route must execute")
	_expect_equal(session.location, destination, "travel must change the base location")
	_expect_equal(session.phase, "map", "travel must return to free roam")
	_expect_equal(session.current_event, "", "travel alone must not force an event")
	_expect_equal(
		int(session.run_state.calendar.elapsed_minutes) - before_time,
		int(route.get("minutes", 0)),
		"travel must advance its displayed duration exactly once"
	)
	_expect_equal(session.flow_revision, before_revision + 1, "travel must advance flow revision once")


func _test_location_action() -> void:
	var session = LegacySession.create_location_first(_build(4), 36_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var action := _first_available_local_action(adapter.get_location_model())
	_expect(not action.is_empty(), "starting place must offer an ordinary action")
	if action.is_empty():
		return
	var before_time := int(session.run_state.calendar.elapsed_minutes)
	var before_revision: int = int(session.flow_revision)
	var result := adapter.perform_location_action(String(action.get("id", "")))
	_expect(bool(result.get("ok", false)), "available ordinary action must execute")
	_expect(not String(result.get("outcome", "")).is_empty(), "ordinary action must return a compact outcome")
	_expect_equal(
		int(session.run_state.calendar.elapsed_minutes) - before_time,
		int(action.get("minutes", 0)),
		"ordinary action must advance the advertised duration exactly once"
	)
	_expect_equal(session.flow_revision, before_revision + 1, "ordinary action must advance flow revision once")
	_expect_equal(session.phase, "map", "ordinary action must return to the location")


func _test_map_view_model() -> void:
	var session = LegacySession.create_location_first(_build(4), 37_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var before: Dictionary = session.to_dict()
	var model := CityMapModels.build(adapter.get_city_map_model(), false)
	_expect_equal(session.to_dict(), before, "view-model construction must be timeless")
	_expect(Array(model.get("nodes", [])).size() >= 6, "district map must keep at least six known locations")
	var mode_count := 0
	for raw_route in Array(model.get("routes", [])):
		if raw_route is Dictionary:
			mode_count += Array(raw_route.get("modes", [])).size()
	_expect(mode_count >= Array(adapter.get_city_map_model().get("routes", [])).size(), "transport options must survive grouping")


func _test_save_round_trip() -> void:
	_cleanup_save()
	var session = LegacySession.create_location_first(_build(4), 38_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var action := _first_available_local_action(adapter.get_location_model())
	if not action.is_empty():
		adapter.perform_location_action(String(action.get("id", "")))
	var route := _first_available_route(adapter.get_city_map_model())
	if not route.is_empty():
		adapter.travel(String(route.get("destination_id", "")), String(route.get("mode", "walk")))
	var expected: Dictionary = session.to_dict()
	var saved := adapter.save(_save_path)
	_expect(bool(saved.get("ok", false)), "sandbox state must save")
	var loaded := SandboxAdapter.load_session(_save_path)
	_expect(bool(loaded.get("ok", false)), "sandbox state must load")
	var restored = loaded.get("session")
	_expect(restored != null, "loaded save must reconstruct the underlying session")
	if restored != null:
		_expect_equal(restored.to_dict(), expected, "action and travel state must round-trip exactly")
		_expect(loaded.get("adapter") is SandboxSessionAdapter, "product load must restore the sandbox façade")


func _test_matching_temporary_promotes() -> void:
	_cleanup_save()
	var staged_path := _save_path + ".staged"
	_cleanup_path(staged_path)
	var session = LegacySession.create_location_first(_build(4), 39_001)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	_expect(bool(adapter.save(_save_path).get("ok", false)), "baseline primary save must succeed")
	var action := _first_available_local_action(adapter.get_location_model())
	if not action.is_empty():
		adapter.perform_location_action(String(action.get("id", "")))
	var expected: Dictionary = session.to_dict()
	_expect(bool(adapter.save(staged_path).get("ok", false)), "staged current save must succeed")
	var rename_error := DirAccess.rename_absolute(staged_path, _save_path + ".tmp")
	_expect_equal(rename_error, OK, "staged save must become a recoverable temporary")
	if rename_error != OK:
		_cleanup_path(staged_path)
		return
	var promoted := adapter.save(_save_path)
	_expect(
		bool(promoted.get("ok", false)),
		"matching temporary must promote without restart: %s" % str(promoted)
	)
	_expect(
		bool(promoted.get("recovered_pending_temporary", false)),
		"save result must report in-process temporary recovery"
	)
	var loaded := SandboxAdapter.load_session(_save_path)
	_expect(bool(loaded.get("ok", false)), "promoted primary must load")
	var restored = loaded.get("session")
	if restored != null:
		_expect_equal(restored.to_dict(), expected, "promoted primary must equal active committed state")
	_cleanup_path(staged_path)


func _test_different_temporary_is_rejected() -> void:
	_cleanup_save()
	var staged_path := _save_path + ".different"
	_cleanup_path(staged_path)
	var session = LegacySession.create_location_first(_build(4), 39_002)
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	session.flow_revision = 1_000_000_000
	_expect(bool(adapter.save(_save_path).get("ok", false)), "baseline primary save must succeed")
	_expect(bool(adapter.save(staged_path).get("ok", false)), "staged older save must succeed")
	var rename_error := DirAccess.rename_absolute(staged_path, _save_path + ".tmp")
	_expect_equal(rename_error, OK, "staged older save must become the pending temporary")
	if rename_error != OK:
		_cleanup_path(staged_path)
		return
	session.flow_revision += 1
	var rejected := adapter.save(_save_path)
	_expect(not bool(rejected.get("ok", true)), "numerically different temporary must be rejected")
	_expect_equal(
		String(rejected.get("code", "")),
		"pending_temporary_recovery",
		"different temporary must remain an explicit recovery decision"
	)
	_expect(
		FileAccess.file_exists(_save_path + ".tmp"),
		"rejected temporary must remain available for safe recovery"
	)
	_cleanup_path(staged_path)


func _first_available_route(model: Dictionary) -> Dictionary:
	for raw_route in Array(model.get("routes", [])):
		if raw_route is Dictionary and bool(raw_route.get("available", false)):
			return Dictionary(raw_route).duplicate(true)
	return {}


func _first_available_local_action(model: Dictionary) -> Dictionary:
	for raw_action in Array(model.get("actions", [])):
		if (
			raw_action is Dictionary
			and String(raw_action.get("kind", "")) == "local"
			and bool(raw_action.get("available", false))
		):
			return Dictionary(raw_action).duplicate(true)
	return {}


func _build(luck: int) -> Dictionary:
	var remaining := 18 - luck
	var strength := mini(10, remaining - 2)
	var charisma := mini(10, remaining - strength - 1)
	var intelligence := remaining - strength - charisma
	return {
		"strength": strength,
		"charisma": charisma,
		"intelligence": intelligence,
		"luck": luck,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if not _values_equal(actual, expected):
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current_test, message, str(expected), str(actual)])


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
	_cleanup_path(_save_path)


func _cleanup_path(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate := path + String(suffix)
		if not path.is_empty() and FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
