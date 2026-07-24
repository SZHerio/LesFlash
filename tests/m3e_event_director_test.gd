extends SceneTree

const CatalogScript := preload("res://game/events/event_catalog.gd")
const Validator := preload("res://game/events/event_content_validator.gd")
const ContextScript := preload("res://game/events/event_context.gd")
const Director := preload("res://game/events/event_director.gd")
const Simulator := preload("res://game/events/event_simulator.gd")
const Command := preload("res://game/events/event_command.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""
var _catalog: Dictionary = {}


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if bool(loaded.get("ok", false)):
		_catalog = loaded["catalog"]
	else:
		_failures.append("catalog setup — %s" % str(loaded.get("errors", [])))
	_run("catalog and authored exits validate", _test_catalog)
	_run("pool trace explains inclusion, exclusion and Luck", _test_trace)
	_run("preview preserves blocked reasons and is pure", _test_preview)
	_run("selection is deterministic and advances only event RNG", _test_selection)
	_run("low Luck produces more adverse encounters", _test_luck_distribution)
	_run("event option queues a deferred consequence atomically", _test_command)
	_run("cooldown excludes a previously seen card", _test_cooldown)
	if _failures.is_empty():
		print("M3E EVENT DIRECTOR TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3E EVENT DIRECTOR TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_catalog() -> void:
	_expect(not _catalog.is_empty(), "default catalog must load")
	if _catalog.is_empty():
		return
	var validation := Validator.validate(_catalog)
	_expect(bool(validation.get("ok", false)), "catalog must validate: %s" % str(validation.get("errors", [])))
	var cards: Array = _catalog.get("cards", [])
	_expect(cards.size() >= 30 and cards.size() <= 50, "M3E bank must contain 30–50 cards")
	for raw_card: Variant in cards:
		if not raw_card is Dictionary:
			continue
		var has_exit := false
		for raw_option: Variant in Array(raw_card.get("options", [])):
			if raw_option is Dictionary and Array(raw_option.get("conditions", [])).is_empty():
				has_exit = true
		_expect(has_exit, "card %s must have an unconditional exit" % raw_card.get("id", ""))


func _test_trace() -> void:
	var context := _context(_state(3))
	var analysis := Director.analyze(_catalog, context)
	_expect(bool(analysis.get("ok", false)), "analysis must accept EventContext")
	var included := 0
	var excluded := 0
	var luck_explained := false
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if not raw_trace is Dictionary:
			continue
		var trace: Dictionary = raw_trace
		if bool(trace.get("included", false)):
			included += 1
		else:
			excluded += 1
			_expect(not Array(trace.get("reasons", [])).is_empty(), "excluded card must explain why")
		if int(trace.get("luck_bias", 0)) != 0:
			luck_explained = (
				int(trace.get("luck_adjustment", 0))
				== int(trace.get("luck_bias", 0)) * int(trace.get("luck_delta", 0))
			)
	_expect(included > 0, "context must produce a non-empty pool")
	_expect(excluded > 0, "location/source filters must exclude some cards")
	_expect(luck_explained, "trace must expose the exact Luck adjustment")


func _test_preview() -> void:
	var state := _state(4)
	var context := _context(state)
	var card_id := _first_included_card(context, true)
	_expect(not card_id.is_empty(), "fixture needs a card with a blocked option")
	if card_id.is_empty():
		return
	var state_before := state.to_dict()
	var context_before := context.duplicate(true)
	var first := Director.preview(_catalog, card_id, context)
	var second := Director.preview(_catalog, card_id, context)
	_expect_equal(first, second, "preview must be deterministic")
	_expect_equal(context, context_before, "preview must not mutate context")
	_expect_equal(state.to_dict(), state_before, "preview must not mutate RunState")
	var blocked_found := false
	var exit_found := false
	for raw_option: Variant in Array(first.get("options", [])):
		if not raw_option is Dictionary:
			continue
		if bool(raw_option.get("available", false)):
			exit_found = true
		else:
			blocked_found = not Array(raw_option.get("blocked_reasons", [])).is_empty()
	_expect(blocked_found, "blocked option must retain its reasons")
	_expect(exit_found, "reachable card must expose an available exit")


func _test_selection() -> void:
	var state := _state(5)
	var context := _context(state)
	var event_rng := RngScript.new(835_021)
	var main_rng_before := state.rng.to_dict()
	var first := Director.select(_catalog, context, event_rng.to_dict())
	var second := Director.select(_catalog, context, event_rng.to_dict())
	_expect_equal(first.get("card_id"), second.get("card_id"), "same event RNG must select same card")
	_expect_equal(first.get("rng"), second.get("rng"), "same event RNG must advance identically")
	_expect(first.get("rng") != event_rng.to_dict(), "selection must advance the returned event RNG")
	_expect_equal(state.rng.to_dict(), main_rng_before, "event selection must not consume main RNG")


func _test_luck_distribution() -> void:
	var samples := 2_000
	var low := Simulator.simulate(_catalog, _context(_state(1)), 44_301, samples)
	var high := Simulator.simulate(_catalog, _context(_state(10)), 44_301, samples)
	_expect(bool(low.get("ok", false)) and bool(high.get("ok", false)), "simulations must complete")
	var low_adverse := int(Dictionary(low.get("tones", {})).get("adverse", 0))
	var high_adverse := int(Dictionary(high.get("tones", {})).get("adverse", 0))
	_expect(low_adverse > high_adverse, "low Luck must produce more adverse cards")
	_expect(low_adverse - high_adverse > samples / 12, "Luck effect must be material")


func _test_command() -> void:
	var state := _state(5)
	var context := _context(state)
	var target := _deferred_option(context)
	_expect(not target.is_empty(), "fixture needs an included unconditional deferred option")
	if target.is_empty():
		return
	var before := state.deferred_consequences.size()
	var result := Command.execute(
		state,
		_catalog,
		String(target.get("card_id", "")),
		String(target.get("option_id", "")),
		context
	)
	_expect(bool(result.get("ok", false)), "event command must succeed: %s" % result.get("error", ""))
	_expect_equal(state.deferred_consequences.size(), before + 1, "deferred effect must be queued once")
	_expect(not Array(result.get("queued_consequences", [])).is_empty(), "result must explain queued consequence")


func _test_cooldown() -> void:
	var context := _context(_state(5))
	var card_id := _first_included_card(context, false)
	_expect(not card_id.is_empty(), "fixture needs an included card")
	if card_id.is_empty():
		return
	var elapsed := int(Dictionary(context.get("calendar", {})).get("elapsed_minutes", 0))
	context["cooldowns"][card_id] = elapsed + 60
	var analysis := Director.analyze(_catalog, context)
	var trace := _trace_for(analysis, card_id)
	_expect(not bool(trace.get("included", true)), "active cooldown must exclude card")
	_expect(
		_has_reason(trace, "cooldown_active"),
		"cooldown exclusion must be visible in the trace"
	)


func _first_included_card(context: Dictionary, require_blocked_option: bool) -> String:
	var analysis := Director.analyze(_catalog, context)
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if not raw_trace is Dictionary or not bool(raw_trace.get("included", false)):
			continue
		var card_id := String(raw_trace.get("card_id", ""))
		if not require_blocked_option:
			return card_id
		var preview := Director.preview(_catalog, card_id, context)
		for raw_option: Variant in Array(preview.get("options", [])):
			if raw_option is Dictionary and not bool(raw_option.get("available", false)):
				return card_id
	return ""


func _deferred_option(context: Dictionary) -> Dictionary:
	var analysis := Director.analyze(_catalog, context)
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if not raw_trace is Dictionary or not bool(raw_trace.get("included", false)):
			continue
		var card_id := String(raw_trace.get("card_id", ""))
		var card := CatalogScript.card(_catalog, card_id)
		for raw_option: Variant in Array(card.get("options", [])):
			if not raw_option is Dictionary or not Array(raw_option.get("conditions", [])).is_empty():
				continue
			for raw_effect: Variant in Array(raw_option.get("effects", [])):
				if raw_effect is Dictionary and String(raw_effect.get("type", "")) == "deferred":
					return {"card_id": card_id, "option_id": String(raw_option.get("id", ""))}
	return {}


func _context(state: RunState) -> Dictionary:
	return ContextScript.build(
		state,
		{
			"kind": "search",
			"id": "underpass_service_yard_v1",
			"action_id": "inspect",
			"object_id": "waste_container",
		},
		{
			"location_id": "underpass",
			"era_id": "late_20th_century",
			"weather_id": "dry",
			"risk": {"score": 18, "noise": 4, "trespass": 1, "tags": ["search"]},
		}
	)


func _state(luck: int) -> RunState:
	var remaining := 18 - luck
	var strength := clampi(remaining - 2, 1, 10)
	var charisma := 1
	var intelligence := remaining - strength - charisma
	return RunState.new({
		"strength": strength,
		"charisma": charisma,
		"intelligence": intelligence,
		"luck": luck,
	}, 91_030 + luck)


func _trace_for(analysis: Dictionary, card_id: String) -> Dictionary:
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if raw_trace is Dictionary and String(raw_trace.get("card_id", "")) == card_id:
			return Dictionary(raw_trace)
	return {}


func _has_reason(trace: Dictionary, code: String) -> bool:
	for raw_reason: Variant in Array(trace.get("reasons", [])):
		if raw_reason is Dictionary and String(raw_reason.get("code", "")) == code:
			return true
	return false


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s — %s (expected=%s, actual=%s)" % [_current, message, str(expected), str(actual)]
		)
