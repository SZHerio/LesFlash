class_name CityMapViewModel
extends RefCounted

const UiModels := preload("res://app/ui_model_factory.gd")
const CurrencyTextScript := preload("res://app/presentation/currency_text.gd")
const MAP_POSITIONS := {
	"station_square": Vector2(0.18, 0.18),
	"underpass": Vector2(0.17, 0.52),
	"market": Vector2(0.49, 0.31),
	"recycling_point": Vector2(0.82, 0.18),
	"clinic_yard": Vector2(0.48, 0.78),
	"embankment": Vector2(0.82, 0.69),
}
const MAP_LABELS := {
	"station_square": "Вокзал",
	"underpass": "Переход",
	"market": "Рынок",
	"recycling_point": "Приёмка",
	"clinic_yard": "Клиника",
	"embankment": "Река",
}
const COMPACT_LABEL_OFFSETS := {
	"station_square": Vector2(0.0, -25.0),
	"underpass": Vector2(-38.0, -25.0),
	"market": Vector2(0.0, 36.0),
	"recycling_point": Vector2(0.0, -25.0),
	"clinic_yard": Vector2(-20.0, 36.0),
	"embankment": Vector2(38.0, 5.0),
}
const PLACE_ICON_IDS := {
	"station_square": &"place_station",
	"underpass": &"place_underpass",
	"market": &"place_market",
	"recycling_point": &"place_recycling",
	"clinic_yard": &"place_clinic",
	"embankment": &"place_embankment",
}
const TRANSPORT_ICON_IDS := {
	"walk": &"transport_walk",
	"bus": &"transport_bus",
	"tram": &"transport_tram",
}


static func build(raw_model: Dictionary, reduced_motion: bool) -> Dictionary:
	var current_id := String(raw_model.get("current_location_id", ""))
	var nodes: Array = []
	var current_location: Dictionary = {}
	for raw_location in Array(raw_model.get("locations", [])):
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = raw_location
		var location_id := String(location.get("id", ""))
		if location_id.is_empty():
			continue
		var node := {
			"id": location_id,
			"title": String(location.get("title", location_id)),
			"map_title": String(MAP_LABELS.get(location_id, location.get("title", location_id))),
			"compact_label_offset": COMPACT_LABEL_OFFSETS.get(location_id, Vector2(0.0, 36.0)),
			"position": MAP_POSITIONS.get(location_id, Vector2(0.5, 0.5)),
			"known": bool(location.get("known", true)),
			"current": location_id == current_id,
			"place_icon_id": StringName(location.get(
				"place_icon_id",
				PLACE_ICON_IDS.get(location_id, &"")
			)),
		}
		nodes.append(node)
		if location_id == current_id:
			current_location = node.duplicate(true)

	var grouped_routes: Dictionary = {}
	for raw_route in Array(raw_model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var origin := String(route.get("from_location_id", current_id))
		var destination := String(route.get("destination_id", ""))
		var mode_id := String(route.get("mode", "walk"))
		if origin.is_empty() or destination.is_empty() or mode_id.is_empty():
			continue
		var route_key := "%s>%s" % [origin, destination]
		if not grouped_routes.has(route_key):
			grouped_routes[route_key] = {
				"from": origin,
				"to": destination,
				"bidirectional": false,
				"modes": [],
			}
		var grouped: Dictionary = grouped_routes[route_key]
		var minutes := maxi(int(route.get("minutes", 1)), 1)
		var price := maxi(int(route.get("price", 0)), 0)
		var modes: Array = grouped["modes"]
		modes.append({
			"id": mode_id,
			"icon_id": StringName(route.get(
				"icon_id",
				TRANSPORT_ICON_IDS.get(mode_id, &"")
			)),
			"transport": String(route.get("mode_title", "Пешком" if mode_id == "walk" else mode_id)),
			"duration_minutes": minutes,
			"price": price,
			"duration": "%d мин" % minutes,
			"cost": "Бесплатно" if price == 0 else CurrencyTextScript.compact(price),
			"meta_tokens": _mode_meta_tokens(minutes, price),
			"available": bool(route.get("available", true)),
			"reason": UiModels.reason_text(route.get("reasons", [])),
		})
		grouped["modes"] = modes
		grouped_routes[route_key] = grouped

	return {
		"district": {
			"id": String(raw_model.get("district_id", "")),
			"title": String(raw_model.get("district_title", "Город")),
		},
		"title": "Карта района",
		"current_location": current_location,
		"nodes": nodes,
		"routes": grouped_routes.values(),
		"reduced_motion": reduced_motion,
	}


static func _mode_meta_tokens(minutes: int, price: int) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = [{
		"kind": &"time",
		"icon_id": &"meta_time",
		"text": "%d мин" % minutes,
		"accessible_text": "Время в пути: %d минут" % minutes,
	}]
	if price <= 0:
		tokens.append({
			"kind": &"money",
			"icon_id": &"",
			"text": "Бесплатно",
			"accessible_text": "Проезд бесплатный",
		})
	else:
		tokens.append({
			"kind": &"money",
			"icon_id": &"currency_arden_compact",
			"text": str(price),
			"accessible_text": CurrencyTextScript.full(price),
		})
	return tokens
