extends SceneTree

## M5 stage 3: two districts the hero has to hear about and pay to reach.
##
## The claims that matter: a district he has not heard of is *absent* from his
## map rather than shown and refused, a line that has stopped for the night
## cannot be caught, and Riverside on its own is still a complete game — a run
## that never finds the bus must not be a broken one.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const Content = preload("res://game/district/district_content.gd")
const Routes = preload("res://game/district/district_routes.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_the_city_has_three_districts()
	_test_riverside_is_complete_on_its_own()
	_test_an_unheard_of_district_is_absent()
	_test_hearing_about_it_puts_it_on_the_map()
	_test_a_line_that_has_stopped_cannot_be_caught()
	_test_a_line_costs_a_fare()
	_finish()


func _adapter() -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
	return adapter


func _test_the_city_has_three_districts() -> void:
	var districts := Content.districts()
	_expect_equal(districts.size(), 3, "the city must hold three districts")
	for district: Dictionary in districts:
		_expect(
			Array(district.get("location_ids", [])).size() >= 3,
			"%s has fewer than three places" % String(district.get("id", ""))
		)
	_expect_equal(Content.locations().size(), CityPlaces.PLACES.size(), "catalog and city list must agree")


## Every place must be reachable from every other, counting the lines. A district
## you can enter and not leave is worse than one that does not exist.
func _test_riverside_is_complete_on_its_own() -> void:
	var reach := Routes.every_place_is_reachable()
	_expect(
		bool(reach.get("ok", false)),
		"some places cannot be reached: %s" % str(reach.get("unreachable", []))
	)
	# And Riverside alone must still hold a shift, a shop and a bed.
	for place_id: String in CityPlaces.RIVERSIDE_PLACE_IDS:
		_expect(CityPlaces.district_of(place_id) == CityPlaces.RIVERSIDE, "%s left Riverside" % place_id)


## Rule 3.4: not greyed out with an explanation — gone.
func _test_an_unheard_of_district_is_absent() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.location = "station_square"
	if "base_location" in session:
		session.base_location = "station_square"
	session.run_state.calendar.minute_of_day = 10 * 60
	for raw_route: Variant in Array(adapter.get_city_map_model().get("routes", [])):
		_expect(
			String(Dictionary(raw_route).get("destination_id", "")) != "bus_depot",
			"the depot was on the map before the hero had heard of it"
		)
	# Confirming it anyway must fail rather than quietly work.
	_expect(
		not bool(adapter.travel("bus_depot", "bus").get("ok", true)),
		"the hero travelled to a district he does not know about"
	)


func _test_hearing_about_it_puts_it_on_the_map() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.location = "station_square"
	if "base_location" in session:
		session.base_location = "station_square"
	session.run_state.calendar.minute_of_day = 10 * 60
	var asked: Dictionary = adapter.perform_location_action("action_station_ask_about_lines")
	_expect(bool(asked.get("ok", false)), "asking the drivers failed: %s" % str(asked))
	_expect(
		session.run_state.has_knowledge("district_zavokzalny"),
		"asking about the lines taught nothing"
	)
	var found := false
	for raw_route: Variant in Array(adapter.get_city_map_model().get("routes", [])):
		if String(Dictionary(raw_route).get("destination_id", "")) == "bus_depot":
			found = true
	_expect(found, "the depot stayed off the map after the hero heard about it")


func _test_a_line_that_has_stopped_cannot_be_caught() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.location = "station_square"
	if "base_location" in session:
		session.base_location = "station_square"
	session.run_state.knowledge["district_zavokzalny"] = 1
	# Half past three in the morning: the depot line does not run until six.
	session.run_state.calendar.minute_of_day = 3 * 60 + 30
	for raw_route: Variant in Array(adapter.get_city_map_model().get("routes", [])):
		_expect(
			String(Dictionary(raw_route).get("destination_id", "")) != "bus_depot",
			"a bus that is not running was offered at half past three"
		)
	_expect(
		not bool(adapter.travel("bus_depot", "bus").get("ok", true)),
		"the hero caught a bus that had stopped for the night"
	)


func _test_a_line_costs_a_fare() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.location = "station_square"
	if "base_location" in session:
		session.base_location = "station_square"
	session.run_state.knowledge["district_zavokzalny"] = 1
	session.run_state.calendar.minute_of_day = 10 * 60
	session.run_state.money = 0
	_expect(
		not bool(adapter.travel("bus_depot", "bus").get("ok", true)),
		"a hero with no money rode for free"
	)
	session.run_state.money = 200
	var before := int(session.run_state.money)
	var rode: Dictionary = adapter.travel("bus_depot", "bus")
	_expect(bool(rode.get("ok", false)), "the fare was paid and the bus still refused: %s" % str(rode))
	if not bool(rode.get("ok", false)):
		return
	_expect(int(session.run_state.money) < before, "the ride cost nothing")
	_expect_equal(String(session.get("location")), "bus_depot", "the bus did not arrive")
	# And there is no walking back: a line is a line.
	var walked: Dictionary = adapter.travel("station_square", "walk")
	_expect(not bool(walked.get("ok", true)), "the hero walked between districts")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 DISTRICTS TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 DISTRICTS: %s" % failure)
	quit(1)
