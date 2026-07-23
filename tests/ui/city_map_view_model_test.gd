extends SceneTree

const CityMapModels := preload("res://app/map/city_map_view_model.gd")


func _init() -> void:
	var raw := {
		"district_id": "riverside_central",
		"district_title": "Приречный район",
		"current_location_id": "station_square",
		"locations": [
			{"id": "station_square", "title": "Вокзальная площадь", "known": true},
			{"id": "clinic_yard", "title": "Двор поликлиники", "known": true},
		],
		"routes": [
			{
				"from_location_id": "station_square",
				"destination_id": "clinic_yard",
				"mode": "walk",
				"mode_title": "Пешком",
				"minutes": 32,
				"price": 0,
				"available": true,
				"reasons": [],
			},
			{
				"from_location_id": "station_square",
				"destination_id": "clinic_yard",
				"mode": "bus",
				"mode_title": "Автобус",
				"minutes": 10,
				"price": 8,
				"available": false,
				"reasons": [{"message": "Не хватает денег"}],
			},
		],
	}
	var before := raw.duplicate(true)
	var model := CityMapModels.build(raw, true)
	if raw != before:
		_fail("builder mutated its domain read-model")
		return
	if not bool(model.get("reduced_motion", false)):
		_fail("reduced-motion preference was lost")
		return
	var routes: Array = model.get("routes", [])
	if routes.size() != 1 or Array(Dictionary(routes[0]).get("modes", [])).size() != 2:
		_fail("transport variants were not grouped into one route")
		return
	var modes: Array = Dictionary(routes[0]).get("modes", [])
	if String(Dictionary(modes[0]).get("duration", "")) != "32 мин":
		_fail("walking duration was not formatted")
		return
	if String(Dictionary(modes[1]).get("cost", "")) != "8 ₽":
		_fail("bus price was not formatted")
		return
	if String(Dictionary(modes[1]).get("reason", "")) != "Не хватает денег":
		_fail("locked transport reason was lost")
		return
	var nodes: Array = model.get("nodes", [])
	var node_position: Variant = Dictionary(nodes[0]).get("position") if not nodes.is_empty() else null
	if nodes.size() != 2 or not (node_position is Vector2):
		_fail("map nodes have no stable presentation coordinates")
		return
	print("M3B CITY MAP VIEW-MODEL TEST PASSED: pure grouping, price, duration and reasons")
	quit(0)


func _fail(message: String) -> void:
	push_error("M3B CITY MAP VIEW-MODEL FAILED: %s" % message)
	quit(1)
