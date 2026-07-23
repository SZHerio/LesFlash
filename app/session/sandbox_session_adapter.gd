class_name SandboxSessionAdapter
extends FirstDaySessionAdapter

## Product-facing session façade for the location-first sandbox.
##
## The inherited adapter keeps the verified M2 commands available for legacy
## saves. New runs and read models use the M3B contract: the location is the
## base screen, ordinary events are not exposed as permanent action buttons,
## and travel is described before it is confirmed.

const LegacySessionScript := preload("res://game/first_day/first_day_session.gd")
const LegacySaveScript := preload("res://game/first_day/first_day_save.gd")
const FirstDayContentScript := preload("res://game/first_day/first_day_content.gd")
const LocationActions := preload("res://game/location/location_action_service.gd")
const LocationActionCommand := preload("res://game/location/first_day_location_action_command.gd")


static func create(characteristics: Dictionary, seed: int) -> RefCounted:
	var session := LegacySessionScript.create_location_first(characteristics, seed)
	if session == null:
		return null
	var adapter_script: Script = load("res://app/session/sandbox_session_adapter.gd")
	return adapter_script.new(session)


static func load_session(path: String = FirstDaySave.DEFAULT_SAVE_PATH) -> Dictionary:
	var result: Dictionary = LegacySaveScript.load_session(path)
	if bool(result.get("ok", false)):
		var adapter_script: Script = load("res://app/session/sandbox_session_adapter.gd")
		result["adapter"] = adapter_script.new(result.get("session"))
	return result


func start_new_run(characteristics: Dictionary, seed: int) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _session.start_new_location_first(characteristics, seed)


func get_location_model() -> Dictionary:
	var model := super.get_location_model()
	var sandbox_actions: Array = []
	var include_blocked := bool(_session.settings.get("show_locked_options", false))
	for raw_action in LocationActions.get_actions(
		_session,
		_session.location,
		{"include_blocked": include_blocked}
	):
		if not raw_action is Dictionary:
			continue
		var action := Dictionary(raw_action).duplicate(true)
		var risk := String(action.get("risk", "нет")).strip_edges()
		action["kind"] = "local"
		action["minutes"] = int(action.get("duration_minutes", 0))
		action["meta"] = ["Риск: %s" % risk.capitalize()] if risk != "нет" else ["Без риска"]
		sandbox_actions.append(action)
	for raw_action in Array(model.get("actions", [])):
		if raw_action is Dictionary and String(raw_action.get("kind", "")) != "event":
			var inherited_action := Dictionary(raw_action).duplicate(true)
			if String(inherited_action.get("kind", "")) == "wait":
				inherited_action["description"] = "Перейти к вечерним делам и подготовке ночлега."
			sandbox_actions.append(inherited_action)
	model["actions"] = sandbox_actions
	return model


func perform_location_action(action_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return LocationActionCommand.execute(_session, action_id)


func get_city_map_model() -> Dictionary:
	if _session == null:
		return {}
	var raw_model: Dictionary = _session.get_map_model()
	var locations: Array = []
	for raw_location in Array(raw_model.get("locations", [])):
		if not raw_location is Dictionary:
			continue
		var location_model := Dictionary(raw_location).duplicate(true)
		location_model["known"] = true
		locations.append(location_model)
	var routes: Array = []
	var origin := String(raw_model.get("current_location_id", _session.location))
	for raw_route in Array(raw_model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route := Dictionary(raw_route).duplicate(true)
		var destination := String(route.get("destination_id", ""))
		var mode := String(route.get("mode", "walk"))
		route["from_location_id"] = origin
		route["option_id"] = "%s:%s:%s" % [origin, destination, mode]
		route["price"] = _route_price(origin, destination, mode)
		routes.append(route)
	var district: Dictionary = FirstDayContentScript.district()
	return {
		"district_id": String(district.get("id", "")),
		"district_title": String(district.get("title", "Город")),
		"district_description": String(district.get("description", "")),
		"current_location_id": origin,
		"locations": locations,
		"routes": routes,
		"calendar": Dictionary(raw_model.get("calendar", {})).duplicate(true),
	}


func travel(destination: String, mode: String = "walk") -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	var selected_route := _find_map_route(destination, mode)
	var result := super.travel(destination, mode)
	if bool(result.get("ok", false)) and not selected_route.is_empty():
		result["route_option_id"] = String(selected_route.get("option_id", ""))
		result["mode"] = mode
		result["minutes"] = int(selected_route.get("minutes", 0))
		result["price"] = int(selected_route.get("price", 0))
	return result


func _find_map_route(destination: String, mode: String) -> Dictionary:
	for raw_route in Array(get_city_map_model().get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		if (
			String(route.get("destination_id", "")) == destination
			and String(route.get("mode", "walk")) == mode
		):
			return route.duplicate(true)
	return {}


func _route_price(origin: String, destination: String, mode: String) -> int:
	if mode != "bus":
		return 0
	var place: Dictionary = FirstDayContentScript.location(origin)
	for raw_route in Array(place.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var route_destination := String(
			route.get("destination_id", route.get("destination", route.get("to", "")))
		)
		if route_destination == destination:
			return maxi(int(route.get("fare", 0)), 0)
	return 0


func _missing_sandbox_session() -> Dictionary:
	return {
		"ok": false,
		"code": "missing_session",
		"error": "FirstDaySession is not attached.",
	}
