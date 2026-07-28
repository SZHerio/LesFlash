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
