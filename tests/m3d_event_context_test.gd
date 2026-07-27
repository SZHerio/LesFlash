extends SceneTree

const EventContextScript := preload("res://game/events/event_context.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("build is complete and does not consume RNG", _test_build)
	_run("external items are excluded", _test_external_items)
	_run("context is a deep snapshot", _test_deep_copy)
	_run("malformed JSON values are rejected", _test_json_safety)
	if _failures.is_empty():
		print("M3D EVENT CONTEXT TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3D EVENT CONTEXT TESTS FAILED: %d failure(s)" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_build() -> void:
	var state := _state()
	state.add_item("scrap_wire", 2)
	var rng_before := state.rng.to_dict()
	var context := _context(state)
	_expect(not context.is_empty(), "valid context must build")
	_expect(bool(EventContextScript.validate(context).get("ok", false)), "built context must validate")
	_expect_equal(state.rng.to_dict(), rng_before, "context build must not consume run RNG")
	_expect_equal(context["actor"]["items"].get("scrap_wire", 0), 2, "carried count must be exposed")
	_expect_equal(context["risk"]["noise"], 7, "search risk must be preserved")


func _test_external_items() -> void:
	var state := _state()
	state.inventory = InventoryStateScript.ensure_external_container(
		state.inventory,
		"search:yard:ground",
		"На земле"
	)
	var addition := InventoryStateScript.add_item(
		state.inventory,
		"plastic_bottle",
		3,
		100,
		"search:yard:ground",
		5,
		true
	)
	_expect(bool(addition.get("ok", false)), "ground fixture must be created")
	if bool(addition.get("ok", false)):
		state.inventory = addition["inventory"]
	var context := _context(state)
	_expect(
		not Dictionary(context["actor"]["items"]).has("plastic_bottle"),
		"items on the ground must not count as actor possessions"
	)


func _test_deep_copy() -> void:
	var state := _state()
	state.knowledge["yard_hint"] = 1
	var world := _world()
	world["relationships"] = {"caretaker": {"trust": 2, "respect": 0, "affinity": 0, "fear": 0}}
	var context := EventContextScript.build(state, _source(), world)
	context["actor"]["knowledge"]["yard_hint"] = 99
	context["relationships"]["caretaker"]["trust"] = -50
	_expect_equal(state.knowledge["yard_hint"], 1, "actor data must be copied")
	_expect_equal(world["relationships"]["caretaker"]["trust"], 2, "world data must be copied")


func _test_json_safety() -> void:
	var context := _context(_state())
	context["cooldowns"][4] = "bad key"
	var validation := EventContextScript.validate(context)
	_expect(not bool(validation.get("ok", true)), "non-string keys must be rejected")
	context = _context(_state())
	context["cooldowns"]["unsafe"] = GameRules.JSON_SAFE_INTEGER_MAX + 1
	validation = EventContextScript.validate(context)
	_expect(not bool(validation.get("ok", true)), "inexact integers must be rejected")


func _context(state: RunState) -> Dictionary:
	return EventContextScript.build(state, _source(), _world())


func _source() -> Dictionary:
	return {
		"kind": "search",
		"id": "underpass_service_yard",
		"action_id": "force_locker",
		"object_id": "service_locker",
	}


func _world() -> Dictionary:
	return {
		"location_id": "underpass",
		"era_id": "late_20th_century",
		"weather_id": "dry",
		"risk": {"score": 12, "noise": 7, "trespass": 3, "tags": ["noise"]},
	}


func _state() -> RunState:
	return RunState.new({
		"strength": 5,
		"charisma": 4,
		"intelligence": 5,
		"luck": 4,
	}, 72_301)


func _expect(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failures.append("%s — %s" % [_current, message])
