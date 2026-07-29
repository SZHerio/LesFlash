extends SceneTree

## Content stage 1: winter, the seasons and the night.
##
## The claim that matters is not that a season exists. It is that the difference
## between a corner and a bed stops being about comfort: a July night under the
## pipes is survivable and a January one is not, and every coat and hundred ard
## spent on a room becomes a decision rather than a habit.
##
## And the other half — that some work and some places exist only at one time of
## the year or one time of night, so the calendar is an economy and not weather.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const ShelterService = preload("res://game/shelter/shelter_session_service.gd")
const ActionCatalog = preload("res://game/sandbox/sandbox_action_catalog.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const NICHE := "shelter_underpass_niche"
const PAID_ROOM := "shelter_station_safe_room"

var _failures: Array[String] = []


func _init() -> void:
	_test_the_year_is_described_completely()
	_test_a_month_knows_its_season()
	_test_winter_bites_the_street_and_not_the_room()
	_test_some_work_exists_only_in_winter()
	_test_some_work_exists_only_at_night()
	_test_nothing_necessary_hides_behind_a_season()
	_finish()


func _adapter(location_id: String) -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
		return null
	var session = adapter.get("_session")
	session.location = location_id
	if "base_location" in session:
		session.base_location = location_id
	session.phase = "map"
	return adapter


func _test_the_year_is_described_completely() -> void:
	var validation := Season.validate()
	_expect(
		bool(validation.get("ok", false)),
		"the year does not add up: %s" % str(validation.get("errors", []))
	)


func _test_a_month_knows_its_season() -> void:
	_expect_equal(Season.of_month(1), Season.WINTER, "January is not winter")
	_expect_equal(Season.of_month(7), Season.SUMMER, "July is not summer")
	_expect_equal(Season.of_month(10), Season.AUTUMN, "October is not autumn")
	_expect(Season.is_cold(Season.WINTER), "winter is not cold")
	_expect(not Season.is_cold(Season.SUMMER), "summer is cold")
	_expect(
		Season.cold_basis_points(Season.WINTER) > Season.cold_basis_points(Season.AUTUMN),
		"January is no worse than October"
	)


## The whole point of the stage.
func _test_winter_bites_the_street_and_not_the_room() -> void:
	var adapter: SandboxSessionAdapter = _adapter("underpass")
	if adapter == null:
		return
	var session = adapter.get("_session")
	var summer := _night_harm(session, 7, NICHE)
	var winter := _night_harm(session, 1, NICHE)
	_expect(
		winter > summer,
		"a January night in the niche costs no more than a July one (%d against %d)" % [winter, summer]
	)

	# A room is exposed to nothing, so the month must not reach it at all.
	var station: SandboxSessionAdapter = _adapter("station_square")
	if station == null:
		return
	var room_session = station.get("_session")
	var summer_room := _night_harm(room_session, 7, PAID_ROOM)
	var winter_room := _night_harm(room_session, 1, PAID_ROOM)
	_expect_equal(
		winter_room,
		summer_room,
		"the weather reached a bed under a roof"
	)
	# And that is what makes the room worth its price in February.
	_expect(
		winter - summer > winter_room - summer_room,
		"winter does not widen the gap between a corner and a bed"
	)


## What one night in a place takes out of him, as a single number: everything
## harmful in its meter effects added up.
func _night_harm(session: Object, month: int, shelter_id: String) -> int:
	session.run_state.calendar.month = month
	var resolved: Dictionary = ShelterService.options(session)
	if not bool(resolved.get("ok", false)):
		_failures.append("shelter options failed in month %d: %s" % [month, str(resolved.get("error", ""))])
		return 0
	for raw_option: Variant in Array(resolved.get("options", [])):
		var option: Dictionary = raw_option
		if String(option.get("shelter_id", "")) != shelter_id:
			continue
		var harm := 0
		var effects: Dictionary = Dictionary(option.get("meter_effects", {}))
		for meter_id: String in ["health", "mental_state"]:
			harm += maxi(-int(effects.get(meter_id, 0)), 0)
		harm += maxi(int(effects.get("tension", 0)), 0)
		return harm
	_failures.append("%s was not offered in month %d" % [shelter_id, month])
	return 0


func _test_some_work_exists_only_in_winter() -> void:
	var adapter: SandboxSessionAdapter = _adapter("recycling_point")
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.calendar.month = 7
	_expect(
		not _offers(adapter, "action_yard_clear_snow"),
		"snow was cleared in July"
	)
	session.run_state.calendar.month = 1
	_expect(
		_offers(adapter, "action_yard_clear_snow"),
		"there is no snow work in January"
	)


func _test_some_work_exists_only_at_night() -> void:
	var adapter: SandboxSessionAdapter = _adapter("night_canteen")
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.calendar.minute_of_day = 13 * 60
	_expect(
		not _offers(adapter, "action_canteen_night_shift"),
		"the night shift was offered at one in the afternoon"
	)
	session.run_state.calendar.minute_of_day = 1 * 60
	_expect(
		_offers(adapter, "action_canteen_night_shift"),
		"the night canteen wants no help at one in the morning"
	)


## Content principle: nothing necessary may sit behind a capability or a date.
## A season is the harshest gate there is — it lasts months — so the things a
## week cannot do without must never be behind one.
func _test_nothing_necessary_hides_behind_a_season() -> void:
	var loaded := ActionCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		_failures.append("the action catalog does not load")
		return
	var seasonal_categories: Dictionary = {}
	var all_categories: Dictionary = {}
	for raw_action: Variant in Array(Dictionary(loaded["catalog"]).get("actions", [])):
		var action: Dictionary = raw_action
		var category := String(action.get("category_id", ""))
		all_categories[category] = int(all_categories.get(category, 0)) + 1
		for raw_requirement: Variant in Array(action.get("requirements", [])):
			if String(Dictionary(raw_requirement).get("type", "")) == "season":
				seasonal_categories[category] = int(seasonal_categories.get(category, 0)) + 1
	for category: String in ["food", "shelter", "trade"]:
		if not all_categories.has(category):
			continue
		_expect(
			int(seasonal_categories.get(category, 0)) < int(all_categories[category]),
			"everything of kind %s is locked behind a season" % category
		)


func _offers(adapter: Object, action_id: String) -> bool:
	for raw_action: Variant in Array(Dictionary(adapter.get_location_model()).get("actions", [])):
		var action: Dictionary = raw_action
		if String(action.get("id", "")) == action_id and bool(action.get("available", false)):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M6 SEASONS TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M6 SEASONS: %s" % failure)
	quit(1)
