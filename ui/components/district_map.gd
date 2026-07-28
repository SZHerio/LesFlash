class_name DistrictMap
extends Control

## Lightweight, touch-first map for the first-day district.
## Spatial coordinates belong to presentation only; gameplay routes always come
## from RunSession.get_map_model().

signal location_selected(location_id: String)

const LOCATION_POSITIONS := {
	"station_square": Vector2(0.25, 0.18),
	"underpass": Vector2(0.22, 0.51),
	"market": Vector2(0.50, 0.34),
	"recycling_point": Vector2(0.79, 0.24),
	"clinic_yard": Vector2(0.49, 0.76),
	"embankment": Vector2(0.80, 0.72),
}

const MAP_BACKGROUND := Color("#17201f")
const MAP_GRID := Color("#30403d")
const ROUTE_AVAILABLE := Color("#91b99e")
const ROUTE_LOCKED := Color("#586461")
const LOCATION_FILL := Color("#d8d0bd")
const LOCATION_TEXT := Color("#f0eadc")
const CURRENT_FILL := Color("#d48a58")
const SELECTED_RING := Color("#f2c06b")

var _model: Dictionary = {}
var _selected_location := ""
var _pulse := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 310.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)


func set_map_model(value: Dictionary) -> void:
	_model = value.duplicate(true)
	if not _has_location(_selected_location):
		_selected_location = ""
	queue_redraw()


func set_selected_location(location_id: String) -> void:
	_selected_location = location_id if _has_location(location_id) else ""
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, 2.0)
	queue_redraw()


func _draw() -> void:
	var map_rect := Rect2(Vector2(8.0, 8.0), Vector2(maxf(size.x - 16.0, 1.0), maxf(size.y - 16.0, 1.0)))
	draw_style_box(_map_style(), map_rect)
	_draw_grid(map_rect)
	_draw_routes(map_rect)
	_draw_locations(map_rect)


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var pointer := Vector2.ZERO
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		pointer = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		pointer = event.position
	if not pressed:
		return

	var map_rect := Rect2(Vector2(8.0, 8.0), Vector2(maxf(size.x - 16.0, 1.0), maxf(size.y - 16.0, 1.0)))
	var nearest_id := ""
	var nearest_distance := 42.0
	for raw_location in _model.get("locations", []):
		if not raw_location is Dictionary:
			continue
		var location_id := String(raw_location.get("id", ""))
		var distance := pointer.distance_to(_location_position(location_id, map_rect))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = location_id
	if nearest_id.is_empty():
		return
	_selected_location = nearest_id
	queue_redraw()
	location_selected.emit(nearest_id)
	accept_event()


func _draw_grid(map_rect: Rect2) -> void:
	for step in range(1, 5):
		var x := map_rect.position.x + map_rect.size.x * float(step) / 5.0
		draw_line(Vector2(x, map_rect.position.y + 8.0), Vector2(x, map_rect.end.y - 8.0), MAP_GRID, 1.0, true)
	for step in range(1, 4):
		var y := map_rect.position.y + map_rect.size.y * float(step) / 4.0
		draw_line(Vector2(map_rect.position.x + 8.0, y), Vector2(map_rect.end.x - 8.0, y), MAP_GRID, 1.0, true)


func _draw_routes(map_rect: Rect2) -> void:
	var origin_id := String(_model.get("current_location_id", ""))
	if origin_id.is_empty():
		return
	var origin := _location_position(origin_id, map_rect)
	var destination_availability: Dictionary = {}
	for raw_route in _model.get("routes", []):
		if not raw_route is Dictionary:
			continue
		var destination := String(raw_route.get("destination_id", ""))
		if destination.is_empty():
			continue
		destination_availability[destination] = bool(destination_availability.get(destination, false)) or bool(raw_route.get("available", false))
	for destination in destination_availability:
		var target := _location_position(String(destination), map_rect)
		var colour := ROUTE_AVAILABLE if bool(destination_availability[destination]) else ROUTE_LOCKED
		draw_line(origin, target, Color("#0b1110"), 7.0, true)
		draw_line(origin, target, colour, 3.0, true)


func _draw_locations(map_rect: Rect2) -> void:
	var font := get_theme_default_font()
	var font_size := maxi(get_theme_default_font_size() - 3, 12)
	for raw_location in _model.get("locations", []):
		if not raw_location is Dictionary:
			continue
		var location_id := String(raw_location.get("id", ""))
		var title := String(raw_location.get("title", location_id))
		var current := bool(raw_location.get("current", false))
		var point := _location_position(location_id, map_rect)
		if location_id == _selected_location:
			draw_circle(point, 26.0, Color(SELECTED_RING, 0.18), true, -1.0, true)
			draw_arc(point, 25.0, 0.0, TAU, 48, SELECTED_RING, 2.0, true)
		draw_circle(point, 19.0, Color("#0e1514"), true, -1.0, true)
		draw_circle(point, 15.0, CURRENT_FILL if current else LOCATION_FILL, true, -1.0, true)
		if current:
			var pulse_radius := 21.0 + sin(_pulse * PI) * 2.0
			draw_arc(point, pulse_radius, 0.0, TAU, 40, Color(CURRENT_FILL, 0.80), 2.0, true)
			draw_circle(point, 4.5, Color("#fff5df"), true, -1.0, true)
		var label_width := minf(160.0, map_rect.size.x * 0.40)
		draw_string(
			font,
			Vector2(point.x - label_width * 0.5, point.y + 38.0),
			title,
			HORIZONTAL_ALIGNMENT_CENTER,
			label_width,
			font_size,
			LOCATION_TEXT
		)


func _location_position(location_id: String, map_rect: Rect2) -> Vector2:
	var normalized: Vector2 = LOCATION_POSITIONS.get(location_id, Vector2(0.5, 0.5))
	var inset := Vector2(28.0, 30.0)
	var usable := Vector2(maxf(map_rect.size.x - inset.x * 2.0, 1.0), maxf(map_rect.size.y - inset.y * 2.0, 1.0))
	return map_rect.position + inset + normalized * usable


func _has_location(location_id: String) -> bool:
	if location_id.is_empty():
		return false
	for raw_location in _model.get("locations", []):
		if raw_location is Dictionary and String(raw_location.get("id", "")) == location_id:
			return true
	return false


func _map_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = MAP_BACKGROUND
	style.border_color = Color("#52645f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	return style
