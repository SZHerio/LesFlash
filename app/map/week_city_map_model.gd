class_name WeekCityMapModel
extends RefCounted

const DistrictContentScript := preload("res://game/district/district_content.gd")


static func build(session: Object) -> Dictionary:
	if session == null or not session.has_method("get_map_model"):
		return {}
	var raw_model: Dictionary = session.call("get_map_model")
	var locations: Array = []
	for raw_location: Variant in Array(raw_model.get("locations", [])):
		if not raw_location is Dictionary:
			continue
		var location_model := Dictionary(raw_location).duplicate(true)
		location_model["known"] = true
		locations.append(location_model)
	var routes: Array = []
	var origin := String(raw_model.get("current_location_id", session.get("location")))
	for raw_route: Variant in Array(raw_model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route := Dictionary(raw_route).duplicate(true)
		var destination := String(route.get("destination_id", ""))
		var mode := String(route.get("mode", "walk"))
		# Rule 3.4: a district the hero has never heard of is simply not on his
		# map. Not greyed out with "you do not know about this yet" — absent.
		if not CityPlaces.is_known(session.get("run_state"), CityPlaces.district_of(destination)):
			continue
		# Likewise a line that has stopped for the night: the board shows what is
		# running, and a timetable is something the world tells you, not the UI.
		if not _line_is_running(session, origin, destination):
			continue
		route["from_location_id"] = origin
		route["option_id"] = "%s:%s:%s" % [origin, destination, mode]
		route["price"] = _route_price(origin, destination, mode)
		routes.append(route)
	var district: Dictionary = DistrictContentScript.district()
	return {
		"district_id": String(district.get("id", "")),
		"district_title": String(district.get("title", "Город")),
		"district_description": String(district.get("description", "")),
		"current_location_id": origin,
		"locations": locations,
		"routes": routes,
		"calendar": Dictionary(raw_model.get("calendar", {})).duplicate(true),
	}


## Whether the scheduled line towards this place is running at the moment. Roads
## that are simply walked always are.
static func _line_is_running(session: Object, origin: String, destination: String) -> bool:
	var run_state: RunState = session.get("run_state")
	if run_state == null:
		return true
	for raw_route: Variant in DistrictContentScript.routes_from(origin):
		if not raw_route is Dictionary:
			continue
		if String(Dictionary(raw_route).get("destination_id", "")) != destination:
			continue
		return RunSession.route_is_running(
			Dictionary(raw_route),
			int(run_state.calendar.minute_of_day)
		)
	return true


static func find_route(model: Dictionary, destination: String, mode: String) -> Dictionary:
	for raw_route: Variant in Array(model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		if (
			String(route.get("destination_id", "")) == destination
			and String(route.get("mode", "walk")) == mode
		):
			return route.duplicate(true)
	return {}


static func _route_price(origin: String, destination: String, mode: String) -> int:
	if mode != "bus":
		return 0
	var place: Dictionary = DistrictContentScript.location(origin)
	for raw_route: Variant in Array(place.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var route_destination := String(
			route.get("destination_id", route.get("destination", route.get("to", "")))
		)
		if route_destination == destination:
			return maxi(int(route.get("fare", 0)), 0)
	return 0
