extends SceneTree

const LegacySession := preload("res://game/run/run_session.gd")
const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""


func _init() -> void:
	_run_test("scheduled NPC actions compose into the location read-model", _test_presence_and_pure_reads)
	_run_test("NPC interaction crosses the session boundary once", _test_adapter_command)

	if _failures.is_empty():
		print("M3F.3 NPC SESSION INTEGRATION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.3 NPC SESSION INTEGRATION TESTS FAILED: %d failure(s) across %d test(s)" % [
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


func _test_presence_and_pure_reads() -> void:
	var session = _fresh_session("recycling_point", 43_301)
	_expect(session != null, "location-first session must be created")
	if session == null:
		return
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var before: Dictionary = session.to_dict()
	var location_model := adapter.get_location_model()
	var action := _npc_action(location_model, "npc_viktor_koren")
	_expect(not action.is_empty(), "Viktor must be visible at the recycling point during his shift")
	if not action.is_empty():
		_expect_equal(String(action.get("kind", "")), "npc", "dynamic action kind")
		_expect_equal(String(action.get("category_id", "")), "talk", "dynamic action category")
		_expect_equal(
			String(action.get("category_icon_id", "")),
			"action_talk",
			"dynamic action semantic icon"
		)
		var intent: Dictionary = Dictionary(action.get("intent", {}))
		var payload: Dictionary = Dictionary(intent.get("payload", {}))
		_expect_equal(
			String(payload.get("npc_id", "")),
			"npc_viktor_koren",
			"dynamic action must carry a typed NPC intent"
		)

	var npc_model := adapter.get_npc_model("npc_viktor_koren")
	_expect(bool(npc_model.get("ok", false)), "present NPC must expose an interaction model")
	_expect_equal(String(npc_model.get("name", "")), "Мартин Гордеев", "domain name must be adapted for the screen")
	_expect(
		not String(npc_model.get("role", "")).is_empty(),
		"domain role must be adapted for the screen"
	)
	_expect_equal(
		String(npc_model.get("portrait_path", "")),
		"res://assets/portraits/npc_viktor_koren.png",
		"screen model must resolve portrait art through the stable registry"
	)
	_expect(
		not String(npc_model.get("portrait_key", "")).is_empty(),
		"screen model must expose a stable portrait key"
	)
	_expect_equal(
		String(npc_model.get("portrait_crop_mode", "")),
		"focus_cover",
		"screen model must expose a stable portrait crop mode"
	)
	var portrait_focus: Dictionary = Dictionary(npc_model.get("portrait_focus", {}))
	_expect(
		float(portrait_focus.get("y", 1.0)) < 0.5,
		"screen model must preserve the authored face focus"
	)
	_expect_equal(
		int(npc_model.get("expected_revision", -1)),
		adapter.get_flow_revision(),
		"read-model must carry the flow revision returned with its intent"
	)
	var interaction := _first_available_interaction(npc_model)
	_expect(not interaction.is_empty(), "present NPC must have at least one available interaction")
	if not interaction.is_empty():
		_expect(interaction.has("enabled"), "screen-ready interaction must expose enabled instead of domain availability")
		var preview := adapter.preview_npc_interaction(
			"npc_viktor_koren",
			String(interaction.get("id", ""))
		)
		_expect(bool(preview.get("ok", false)), "available interaction preview must resolve")
	_expect_equal(
		session.to_dict(),
		before,
		"location, NPC model and preview reads must not mutate the session"
	)

	session.location = "market"
	_expect(
		_npc_action(adapter.get_location_model(), "npc_viktor_koren").is_empty(),
		"NPC must not leak into another location"
	)
	session.location = "recycling_point"
	session.settings["show_locked_options"] = true
	session.run_state.calendar.minute_of_day = 18 * 60
	session.run_state.calendar.elapsed_minutes = 10 * 60
	_expect(
		_npc_action(adapter.get_location_model(), "npc_viktor_koren").is_empty(),
		"an absent NPC must remain hidden outside the schedule even when locked options are shown"
	)


func _test_adapter_command() -> void:
	var session = _fresh_session("recycling_point", 43_302)
	_expect(session != null, "command session must be created")
	if session == null:
		return
	var adapter := SandboxAdapter.new(session) as SandboxSessionAdapter
	var model := adapter.get_npc_model("npc_viktor_koren")
	var interaction := _first_available_interaction(model)
	_expect(not interaction.is_empty(), "command test needs an available interaction")
	if interaction.is_empty():
		return
	var interaction_id := String(interaction.get("id", ""))
	var preview := adapter.preview_npc_interaction("npc_viktor_koren", interaction_id)
	_expect(bool(preview.get("ok", false)), "command preview must resolve")
	if not bool(preview.get("ok", false)):
		return
	var duration := int(Dictionary(preview.get("definition", {})).get("duration_minutes", 0))
	var before_revision := adapter.get_flow_revision()
	var before_elapsed := int(session.run_state.calendar.elapsed_minutes)
	var before_state: Dictionary = session.to_dict()
	var result := adapter.execute_npc_interaction(
		"npc_viktor_koren",
		interaction_id,
		before_revision
	)
	_expect(bool(result.get("ok", false)), "available NPC interaction must execute: %s" % str(result))
	if not bool(result.get("ok", false)):
		return
	_expect(bool(result.get("mutated", false)), "successful NPC command must report a mutation")
	_expect(result.get("transaction", null) is Dictionary, "successful NPC command must expose its transaction")
	_expect_equal(
		adapter.get_flow_revision(),
		before_revision + 1,
		"adapter must advance flow revision exactly once"
	)
	_expect_equal(
		int(result.get("flow_revision", -1)),
		adapter.get_flow_revision(),
		"command result must expose the committed flow revision"
	)
	_expect_equal(
		int(session.run_state.calendar.elapsed_minutes) - before_elapsed,
		duration,
		"command must advance the duration advertised by the domain model exactly once"
	)
	_expect(not _values_equal(session.to_dict(), before_state), "successful adapter command must commit state")

	var after_success: Dictionary = session.to_dict()
	var duplicate := adapter.execute_npc_interaction(
		"npc_viktor_koren",
		interaction_id,
		before_revision
	)
	_expect(bool(duplicate.get("ok", false)), "retry of the committed intent must be idempotent")
	_expect_equal(
		String(duplicate.get("code", "")),
		"already_applied",
		"retry must reach the domain command ledger"
	)
	_expect_equal(
		adapter.get_flow_revision(),
		before_revision + 1,
		"idempotent retry must not advance flow revision"
	)
	_expect_equal(session.to_dict(), after_success, "idempotent retry must leave the session untouched")

	var stale := adapter.execute_npc_interaction(
		"npc_viktor_koren",
		"npc_interaction_viktor_clear_yard",
		before_revision
	)
	_expect(not bool(stale.get("ok", true)), "stale NPC intent must fail")
	_expect_equal(
		String(stale.get("code", "")),
		"stale_flow_revision",
		"stale NPC intent must have an actionable conflict code"
	)
	_expect_equal(session.to_dict(), after_success, "stale NPC intent must be fully atomic")


func _fresh_session(location_id: String, seed: int) -> Object:
	var session = LegacySession.create_location_first({
		"strength": 4,
		"charisma": 5,
		"intelligence": 5,
		"luck": 4,
	}, seed)
	if session != null:
		session.location = location_id
	return session


func _npc_action(location_model: Dictionary, npc_id: String) -> Dictionary:
	for raw_action: Variant in Array(location_model.get("actions", [])):
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		var intent: Dictionary = Dictionary(action.get("intent", {}))
		var payload: Dictionary = Dictionary(intent.get("payload", {}))
		if String(action.get("kind", "")) == "npc" and String(payload.get("npc_id", "")) == npc_id:
			return action.duplicate(true)
	return {}


func _first_available_interaction(model: Dictionary) -> Dictionary:
	for raw_interaction: Variant in Array(model.get("interactions", [])):
		if raw_interaction is Dictionary and bool(Dictionary(raw_interaction).get(
			"enabled",
			Dictionary(raw_interaction).get("available", false)
		)):
			return Dictionary(raw_interaction).duplicate(true)
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if not _values_equal(actual, expected):
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current_test,
			message,
			str(expected),
			str(actual),
		])


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
		for key: Variant in expected:
			if not actual.has(key) or not _values_equal(actual[key], expected[key]):
				return false
		return true
	if actual is Array:
		if actual.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			if not _values_equal(actual[index], expected[index]):
				return false
		return true
	return actual == expected
