extends SceneTree

const CatalogScript := preload("res://game/shelter/shelter_catalog.gd")
const Validator := preload("res://game/shelter/shelter_catalog_validator.gd")
const Resolver := preload("res://game/shelter/shelter_resolver.gd")
const CommandBuilder := preload("res://game/shelter/shelter_command_builder.gd")
const CalendarScript := preload("res://core/time/game_calendar.gd")
const RunStateScript := preload("res://core/state/run_state.gd")
const ActionTransaction := preload("res://core/rules/action_transaction.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""
var _catalog: Dictionary = {}


func _init() -> void:
	var loaded := CatalogScript.load_default()
	_expect_bootstrap(bool(loaded.get("ok", false)), "default shelter catalog must load: %s" % str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		_catalog = loaded["catalog"]
	_run_test("versioned Russian catalog", _test_catalog_contract)
	_run_test("strict catalog validation", _test_catalog_rejections)
	_run_test("location, time and price availability", _test_availability)
	_run_test("deterministic pure resolution", _test_determinism_and_purity)
	_run_test("confirmed atomic command", _test_confirmed_command)
	_run_test("civil date transitions", _test_date_transitions)

	if _failures.is_empty():
		print("M3F.2 SHELTER TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.2 SHELTER TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if before == _failures.size() else "FAIL: %s" % test_name)


func _expect_bootstrap(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("bootstrap — %s" % message)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current, message, str(expected), str(actual)])


func _test_catalog_contract() -> void:
	if _catalog.is_empty():
		return
	var validation := Validator.validate(_catalog)
	_expect(bool(validation.get("ok", false)), "catalog must validate: %s" % str(validation.get("errors", [])))
	_expect_equal(_catalog.get("schema_version"), 1, "schema version must be explicit")
	_expect_equal(_catalog.get("catalog_version"), 1, "catalog version must be explicit")
	_expect_equal(_catalog.get("currency_code"), "ARD", "only fictional currency code may be stored")
	var categories: Dictionary = {}
	for raw_option: Variant in Array(_catalog.get("options", [])):
		var option: Dictionary = raw_option
		categories[String(option["category_id"])] = true
		_expect(_has_cyrillic(String(option["title"])), "titles must be Russian")
		_expect(_has_cyrillic(String(option["description"])), "descriptions must be Russian")
	_expect_equal(categories.keys().size(), 3, "street, night shelter and paid room must all exist")
	for category_id: String in ["street", "night_shelter", "paid_room"]:
		_expect(categories.has(category_id), "missing shelter category %s" % category_id)
	_expect_equal(CatalogScript.options_for_location(_catalog, "station_square").size(), 2, "station must expose two distinct choices")
	_expect_equal(CatalogScript.options_for_location(_catalog, "underpass").size(), 1, "underpass must expose the street fallback")


func _test_catalog_rejections() -> void:
	if _catalog.is_empty():
		return
	var source_before := _catalog.duplicate(true)
	var duplicate := _catalog.duplicate(true)
	duplicate["options"][1]["shelter_id"] = duplicate["options"][0]["shelter_id"]
	_expect(not bool(Validator.validate(duplicate).get("ok", true)), "duplicate shelter IDs must be rejected")
	var real_currency := _catalog.duplicate(true)
	real_currency["currency_code"] = "RUB"
	_expect(not bool(Validator.validate(real_currency).get("ok", true)), "a real currency code must be rejected")
	var free_paid_room := _catalog.duplicate(true)
	free_paid_room["options"][2]["price_arden"] = 0
	_expect(not bool(Validator.validate(free_paid_room).get("ok", true)), "a paid room must have a positive price")
	var float_time := _catalog.duplicate(true)
	float_time["options"][0]["wake_minute"] = 390.0
	_expect(not bool(Validator.validate(float_time).get("ok", true)), "floating-point schedule values must be rejected")
	var script_payload := _catalog.duplicate(true)
	script_payload["options"][0]["execute"] = "res://bad.gd"
	_expect(not bool(Validator.validate(script_payload).get("ok", true)), "unknown executable-looking fields must be rejected")
	_expect_equal(_catalog, source_before, "validation must not mutate the source catalog")


func _test_availability() -> void:
	if _catalog.is_empty():
		return
	var street_context := _context("underpass", 0, 1980, 9, 1, 20 * 60, 12 * 60)
	var street := Resolver.resolve_for_location(_catalog, street_context)
	_expect(bool(street.get("ok", false)), "street options must resolve")
	_expect_equal(Array(street.get("options", [])).size(), 1, "only local shelter options may be listed")
	var street_option: Dictionary = street["options"][0]
	_expect(bool(street_option.get("available", false)), "street fallback must be free and available at night")
	_expect_equal(street_option.get("price_arden"), 0, "street fallback must be free")
	_expect_equal(street_option.get("duration_minutes"), 630, "20:00 to 06:30 must be 630 minutes")
	_expect_equal(street_option["wake_at"]["day"], 2, "street sleep must reach the next civil date")
	_expect_equal(street_option.get("wake_time_text"), "06:30", "wake time must have a stable display value")

	var station_context := _context("station_square", 0, 1980, 9, 1, 20 * 60, 12 * 60)
	var station := Resolver.resolve_for_location(_catalog, station_context)
	_expect_equal(Array(station.get("options", [])).size(), 2, "station must resolve both local choices")
	var night_room := _option(station, "shelter_municipal_night_room")
	var paid_room := _option(station, "shelter_station_safe_room")
	_expect(bool(night_room.get("available", false)), "free night shelter must be available before closing")
	_expect(not bool(paid_room.get("available", true)), "paid room must be blocked without money")
	_expect_equal(_reason_codes(paid_room), ["not_enough_money"], "money shortfall must have one exact reason")
	_expect_equal(paid_room["blocked_reasons"][0].get("shortfall_arden"), 100, "shortfall must be explicit")

	var midday := Resolver.resolve_one(
		_catalog,
		"shelter_underpass_niche",
		_context("underpass", 0, 1980, 9, 1, 12 * 60, 4 * 60)
	)
	_expect(not bool(midday["option"].get("available", true)), "sleep option must respect its check-in window")
	_expect("outside_check_in_window" in _reason_codes(midday["option"]), "closed window must explain the lock")


func _test_determinism_and_purity() -> void:
	if _catalog.is_empty():
		return
	var context := _context("station_square", 100, 1980, 9, 1, 19 * 60, 11 * 60)
	var catalog_before := _catalog.duplicate(true)
	var context_before := context.duplicate(true)
	var first := Resolver.resolve_for_location(_catalog, context)
	var second := Resolver.resolve_for_location(_catalog, context)
	_expect_equal(first, second, "same snapshots must resolve byte-equivalent shelter models")
	_expect_equal(_catalog, catalog_before, "resolver must not mutate catalog")
	_expect_equal(context, context_before, "resolver must not mutate context")
	var unknown := Resolver.resolve_one(_catalog, "shelter_missing", context)
	_expect_equal(unknown.get("code"), "unknown_shelter", "unknown stable ID must fail explicitly")
	var invalid_context := context.duplicate(true)
	invalid_context["money"] = 100.0
	_expect_equal(Resolver.resolve_for_location(_catalog, invalid_context).get("code"), "invalid_context", "float money must be rejected")


func _test_confirmed_command() -> void:
	if _catalog.is_empty():
		return
	var context := _context("station_square", 150, 1980, 9, 1, 20 * 60, 12 * 60)
	var context_before := context.duplicate(true)
	var catalog_before := _catalog.duplicate(true)
	var preview := CommandBuilder.prepare(
		_catalog,
		"shelter_station_safe_room",
		context,
		"sleep_paid_001",
		false
	)
	_expect_equal(preview.get("code"), "confirmation_required", "opening a sleep preview must not create a command")
	_expect(not preview.has("command"), "unconfirmed sleep must expose no executable effects")

	var prepared := CommandBuilder.prepare(
		_catalog,
		"shelter_station_safe_room",
		context,
		"sleep_paid_001",
		true
	)
	_expect(bool(prepared.get("ok", false)), "confirmed available sleep must prepare")
	var command: Dictionary = prepared.get("command", {})
	_expect_equal(command.get("command_kind"), "sleep", "command kind must be typed")
	_expect_equal(command.get("source_id"), "shelter_station_safe_room", "source ID must retain authorship")
	_expect_equal(command["expected"].get("location_id"), "station_square", "optimistic location must be captured")
	_expect_equal(command["expected"]["calendar_stamp"], context["calendar"]["stamp"], "optimistic calendar revision must be captured")
	_expect_equal(_effect_count(command, "advance_time"), 1, "sleep command must advance time exactly once")
	_expect_equal(_effect_count(command, "change_money"), 1, "paid sleep must charge exactly once")
	_expect_equal(_effect_count(command, "change_state"), 4, "safe room must carry its four authored meter effects")
	_expect_equal(_catalog, catalog_before, "command preparation must not mutate catalog")
	_expect_equal(context, context_before, "command preparation must not mutate detached context")

	var run = RunStateScript.new(_build(), 1_980_201)
	_expect(run.set_money(150), "test run must accept setup money")
	_expect(run.set_meter("health", 70), "test health setup must be valid")
	_expect(run.set_meter("energy", 20), "test energy setup must be valid")
	_expect(run.set_meter("tension", 50), "test tension setup must be valid")
	_expect(run.set_meter("mental_state", 40), "test mental state setup must be valid")
	run.calendar = CalendarScript.from_dict(context["calendar"])
	var applied = ActionTransaction.execute(run, command)
	_expect(applied.success, "prepared command must be compatible with the atomic actor transaction")
	_expect_equal(run.calendar.current_stamp()["day"], 2, "confirmed sleep must cross to the next date")
	_expect_equal(run.calendar.current_stamp()["minute_of_day"], 480, "safe room must wake at 08:00")
	_expect_equal(run.money, 50, "price must be charged atomically")
	_expect_equal(run.get_meter("health"), 72, "health effect must apply")
	_expect_equal(run.get_meter("energy"), 78, "energy effect must apply")
	_expect_equal(run.get_meter("tension"), 38, "tension effect must apply")
	_expect_equal(run.get_meter("mental_state"), 45, "mental effect must apply")

	var blocked := CommandBuilder.prepare(
		_catalog,
		"shelter_station_safe_room",
		_context("station_square", 99, 1980, 9, 1, 20 * 60, 12 * 60),
		"sleep_paid_blocked",
		true
	)
	_expect_equal(blocked.get("code"), "shelter_blocked", "insufficient money must prepare no command")
	_expect(not blocked.has("command"), "blocked sleep must contain no executable effects")


func _test_date_transitions() -> void:
	if _catalog.is_empty():
		return
	var month_end := Resolver.resolve_one(
		_catalog,
		"shelter_station_safe_room",
		_context("station_square", 100, 1980, 9, 30, 20 * 60, 29 * 1440 + 12 * 60)
	)
	_expect(bool(month_end.get("ok", false)), "month-end sleep must resolve")
	var wake: Dictionary = month_end["option"]["wake_at"]
	_expect_equal(wake.get("year"), 1980, "month transition must keep year")
	_expect_equal(wake.get("month"), 10, "September sleep must wake in October")
	_expect_equal(wake.get("day"), 1, "month transition must wake on the first")
	_expect_equal(wake.get("minute_of_day"), 480, "month transition must retain wake time")
	_expect(bool(month_end["option"].get("crosses_date", false)), "resolver must expose civil date transition")


func _context(
	location_id: String,
	money: int,
	year: int,
	month: int,
	day: int,
	minute_of_day: int,
	elapsed_minutes: int
) -> Dictionary:
	var calendar = CalendarScript.new({}, {
		"year": year,
		"month": month,
		"day": day,
		"minute_of_day": minute_of_day,
		"elapsed_minutes": elapsed_minutes,
	})
	return {
		"location_id": location_id,
		"money": money,
		"calendar": calendar.to_dict(),
	}


func _option(result: Dictionary, shelter_id: String) -> Dictionary:
	for raw_option: Variant in Array(result.get("options", [])):
		if raw_option is Dictionary and String(raw_option.get("shelter_id", "")) == shelter_id:
			return raw_option
	return {}


func _reason_codes(option: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_reason: Variant in Array(option.get("blocked_reasons", [])):
		if raw_reason is Dictionary:
			result.append(String(raw_reason.get("code", "")))
	return result


func _effect_count(command: Dictionary, effect_type: String) -> int:
	var result := 0
	for raw_effect: Variant in Array(command.get("effects", [])):
		if raw_effect is Dictionary and String(raw_effect.get("type", "")) == effect_type:
			result += 1
	return result


func _has_cyrillic(text: String) -> bool:
	for character: String in text:
		if (character >= "А" and character <= "я") or character in ["Ё", "ё"]:
			return true
	return false


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 5, "intelligence": 4, "luck": 4}
