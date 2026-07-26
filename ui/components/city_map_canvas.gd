class_name CityMapCanvas
extends Control

signal destination_selected(destination_id: String)
signal travel_animation_finished

const Palette = preload("res://ui/theme/palette.gd")
const CityMapGeometry = preload("res://ui/components/city_map_geometry.gd")
const Motion := preload("res://ui/theme/motion.gd")
const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")
const MapNodeHotspotScript := preload("res://ui/components/map_node_hotspot.gd")
const MapHotspotLayerScript := preload("res://ui/components/map_hotspot_layer.gd")

const TOUCH_RADIUS := 28.0

@onready var _hotspot_layer: MapHotspotLayerScript = %HotspotLayer

var _geometry := CityMapGeometry.new()
var _selected_id := ""
var _hovered_id := ""
var _focused_id := ""
var _pressed_id := ""
var _reduced_motion := false
var _travel_active := false
var _travel_from := ""
var _travel_to := ""
var _travel_progress := 0.0
var _travel_tween: Tween


func _ready() -> void:
	accessibility_name = "Карта района"
	accessibility_description = "Известные места города и доступные маршруты."
	resized.connect(_sync_hotspot_layer)
	_hotspot_layer.destination_requested.connect(_select_destination)
	_hotspot_layer.hovered_changed.connect(_on_hotspot_hovered)
	_hotspot_layer.focused_changed.connect(_on_hotspot_focused)
	_sync_hotspot_layer()
	queue_redraw()


func present(model: Dictionary) -> void:
	_geometry.present(model)
	if not _geometry.is_selectable(_selected_id):
		_selected_id = ""
	_hovered_id = ""
	_focused_id = ""
	_pressed_id = ""
	_sync_hotspot_layer()
	queue_redraw()


func set_selected_destination(destination_id: String) -> void:
	_selected_id = destination_id if _geometry.is_selectable(destination_id) else ""
	if is_node_ready():
		_hotspot_layer.set_selected(_selected_id)
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	queue_redraw()


func animate_travel(from_id: String, to_id: String) -> void:
	if _travel_tween != null and _travel_tween.is_valid():
		_travel_tween.kill()
	_travel_from = from_id
	_travel_to = to_id
	_travel_progress = 0.0
	_travel_active = _geometry.nodes_by_id.has(from_id) and _geometry.nodes_by_id.has(to_id)
	if is_node_ready():
		_hotspot_layer.set_locked(_travel_active)
	if not _travel_active or from_id == to_id:
		_set_travel_progress(1.0)
		call_deferred("_finish_travel_animation")
		return

	_travel_tween = Motion.play_method(
		_travel_tween,
		self,
		_set_travel_progress,
		0.0,
		1.0,
		Motion.JOURNEY,
		_reduced_motion,
		Motion.Shape.TRAVEL
	)
	# Reduced motion jumps the trip to its end, so the completion the screen is
	# waiting for has to be raised by hand rather than by the tween.
	if _travel_tween == null:
		call_deferred("_finish_travel_animation")
	else:
		_travel_tween.tween_callback(_finish_travel_animation)


func get_node_position(node_id: String) -> Vector2:
	return _node_position(node_id, _map_rect())


func get_node_touch_rect(node_id: String) -> Rect2:
	return Rect2(get_node_position(node_id) - Vector2.ONE * TOUCH_RADIUS, Vector2.ONE * TOUCH_RADIUS * 2.0)


func get_node_icon_id(node_id: String) -> StringName:
	var node_model: Variant = _geometry.nodes_by_id.get(node_id, {})
	return StringName(node_model.get("place_icon_id", &"")) if node_model is Dictionary else &""


func get_node_hotspot(node_id: String) -> MapNodeHotspotScript:
	return _hotspot_layer.hotspot(node_id) if is_node_ready() else null


func _draw() -> void:
	var map_rect := _map_rect()
	_draw_ground(map_rect)
	_draw_routes(map_rect)
	_draw_nodes(map_rect)
	_draw_hero(map_rect)


func _draw_ground(map_rect: Rect2) -> void:
	draw_rect(map_rect, Color("#101917"), true)
	draw_rect(map_rect, Color("#53635e"), false, 1.0)

	for step in range(1, 7):
		var x := map_rect.position.x + map_rect.size.x * float(step) / 7.0
		draw_line(
			Vector2(x, map_rect.position.y + 8.0),
			Vector2(x, map_rect.end.y - 8.0),
			Color("#263632"),
			1.0,
			true
		)
	for step in range(1, 5):
		var y := map_rect.position.y + map_rect.size.y * float(step) / 5.0
		draw_line(
			Vector2(map_rect.position.x + 8.0, y),
			Vector2(map_rect.end.x - 8.0, y),
			Color("#263632"),
			1.0,
			true
		)

	var river_points := PackedVector2Array([
		Vector2(map_rect.position.x - 8.0, map_rect.position.y + map_rect.size.y * 0.78),
		Vector2(map_rect.position.x + map_rect.size.x * 0.30, map_rect.position.y + map_rect.size.y * 0.69),
		Vector2(map_rect.position.x + map_rect.size.x * 0.62, map_rect.position.y + map_rect.size.y * 0.77),
		Vector2(map_rect.end.x + 8.0, map_rect.position.y + map_rect.size.y * 0.66),
	])
	draw_polyline(river_points, Color("#0a1112"), 20.0, true)
	draw_polyline(river_points, Color("#24454a"), 13.0, true)
	draw_polyline(river_points, Color("#47747a"), 1.5, true)


func _draw_routes(map_rect: Rect2) -> void:
	for route in _geometry.routes:
		var from_id := _geometry.route_endpoint(route, "from")
		var to_id := _geometry.route_endpoint(route, "to")
		if not _geometry.node_is_known(from_id) or not _geometry.node_is_known(to_id):
			continue
		var from_point := _node_position(from_id, map_rect)
		var to_point := _node_position(to_id, map_rect)
		var available := _geometry.route_available(route)
		var selected := (
			(from_id == _geometry.current_id and to_id == _selected_id)
			or (to_id == _geometry.current_id and from_id == _selected_id)
		)
		var route_color := Color("#53625e")
		if available:
			route_color = Palette.GREEN
		if selected:
			route_color = Palette.GOLD
		draw_line(from_point, to_point, Color("#080d0c"), 8.0 if selected else 6.0, true)
		draw_line(from_point, to_point, route_color, 3.2 if selected else 2.0, true)


func _draw_nodes(map_rect: Rect2) -> void:
	var font := get_theme_default_font()
	# Map labels are spatial annotations, while the selected place is repeated
	# as accessible UI text below. Clamp them so 200% text does not make labels
	# collide and obscure the actual touch targets.
	var font_size := clampi(get_theme_default_font_size() - 3, 12, 16)
	for node_model in _geometry.nodes:
		var node_id := String(node_model.get("id", ""))
		var known := bool(node_model.get("known", true))
		var point := _node_position(node_id, map_rect)
		var selected := node_id == _selected_id
		var highlighted := (
			selected
			or node_id == _hovered_id
			or node_id == _focused_id
			or node_id == _pressed_id
		)
		if highlighted:
			var ring_color := Palette.GOLD if selected else Palette.GREEN_BRIGHT
			draw_circle(point, 28.0, Color(ring_color, 0.15))
			draw_arc(point, 26.0, 0.0, TAU, 40, ring_color, 2.0, true)

		draw_circle(point, 20.0, Color("#09100f"))
		draw_circle(point, 15.0, Palette.PANEL_LIGHT if known else Color("#26302e"))
		draw_arc(point, 15.0, 0.0, TAU, 32, Palette.BORDER, 1.5, true)
		if not known:
			draw_string(font, point + Vector2(-4.0, 5.0), "?", HORIZONTAL_ALIGNMENT_CENTER, 8.0, font_size, Palette.FAINT)
			continue
		var icon_texture := IconRegistryScript.texture(
			StringName(node_model.get("place_icon_id", &""))
		)
		if icon_texture != null:
			var icon_colour := Palette.GOLD if selected else Palette.GREEN_BRIGHT if highlighted else Palette.MUTED
			draw_texture_rect(
				icon_texture,
				Rect2(point - Vector2(12.0, 12.0), Vector2(24.0, 24.0)),
				false,
				icon_colour
			)

		var node_title := String(node_model.get("map_title", node_model.get("title", node_id)))
		var narrow_map := map_rect.size.x < 380.0
		var title_lines: Array[String] = []
		if narrow_map:
			title_lines = _geometry.label_lines(node_title, 15)
		else:
			title_lines.append(node_title)
		var label_width := minf(148.0, map_rect.size.x * (0.35 if narrow_map else 0.34))
		var line_height := float(font_size + 2)
		var label_center_x := point.x
		var label_y := point.y + 37.0
		var compact_offset: Variant = node_model.get("compact_label_offset", null)
		if narrow_map and compact_offset is Vector2:
			label_center_x += compact_offset.x
			label_y = point.y + compact_offset.y
		else:
			var label_above := point.y > map_rect.position.y + map_rect.size.y * 0.48
			if node_id == _geometry.current_id and point.y > map_rect.position.y + 44.0:
				label_above = true
			if selected:
				label_above = false
			if label_above:
				label_y = point.y - 29.0 - line_height * float(title_lines.size() - 1)
		for line_index in range(title_lines.size()):
			draw_string(
				font,
				Vector2(label_center_x - label_width * 0.5, label_y + line_height * line_index),
				title_lines[line_index],
				HORIZONTAL_ALIGNMENT_CENTER,
				label_width,
				font_size,
				Palette.TEXT
			)


func _draw_hero(map_rect: Rect2) -> void:
	if _geometry.current_id.is_empty() or not _geometry.nodes_by_id.has(_geometry.current_id):
		return
	var point := _node_position(_geometry.current_id, map_rect)
	if _travel_active:
		point = _node_position(_travel_from, map_rect).lerp(_node_position(_travel_to, map_rect), _travel_progress)
	draw_circle(point, 23.0, Color(Palette.GOLD, 0.14))
	draw_circle(point, 11.0, Color("#f5ead4"))
	draw_circle(point, 6.0, Palette.RUST)
	draw_line(point + Vector2(0.0, 8.0), point + Vector2(0.0, 17.0), Color("#f5ead4"), 3.0, true)


func _gui_input(event: InputEvent) -> void:
	if _travel_active:
		return
	if event is InputEventMouseMotion:
		_hovered_id = _node_at(event.position)
		queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed_id = _node_at(event.position)
		else:
			var released_id := _node_at(event.position)
			if not _pressed_id.is_empty() and released_id == _pressed_id:
				_select_destination(released_id)
			_pressed_id = ""
		queue_redraw()
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pressed_id = _node_at(event.position)
		else:
			var released_id := _node_at(event.position)
			if not _pressed_id.is_empty() and released_id == _pressed_id:
				_select_destination(released_id)
			_pressed_id = ""
		queue_redraw()
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			var target := _hovered_id if _geometry.is_selectable(_hovered_id) else _geometry.first_selectable_id()
			_select_destination(target)
			accept_event()


func _select_destination(destination_id: String) -> void:
	if not _geometry.is_selectable(destination_id):
		return
	_selected_id = destination_id
	_hovered_id = destination_id
	_hotspot_layer.set_selected(_selected_id)
	queue_redraw()
	destination_selected.emit(destination_id)


func _sync_hotspot_layer() -> void:
	if not is_node_ready():
		return
	var models: Array[Dictionary] = []
	for node_model: Dictionary in _geometry.nodes:
		var node_id := String(node_model.get("id", ""))
		if not _geometry.is_selectable(node_id):
			continue
		models.append({
			"id": node_id,
			"title": String(node_model.get("title", node_id)),
			"center": get_node_position(node_id),
		})
	_hotspot_layer.present(models, _selected_id, _travel_active)


func _on_hotspot_hovered(node_id: String) -> void:
	_hovered_id = node_id
	queue_redraw()


func _on_hotspot_focused(node_id: String) -> void:
	_focused_id = node_id
	queue_redraw()


func _node_at(pointer: Vector2) -> String:
	var nearest_id := ""
	var nearest_distance := TOUCH_RADIUS
	for node_model in _geometry.nodes:
		var node_id := String(node_model.get("id", ""))
		if not _geometry.is_selectable(node_id):
			continue
		var distance := pointer.distance_to(get_node_position(node_id))
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = node_id
	return nearest_id


func _node_position(node_id: String, map_rect: Rect2) -> Vector2:
	return _geometry.node_position(node_id, map_rect)


func _map_rect() -> Rect2:
	return Rect2(Vector2(4.0, 4.0), Vector2(maxf(size.x - 8.0, 1.0), maxf(size.y - 8.0, 1.0)))


func _set_travel_progress(value: float) -> void:
	_travel_progress = value
	queue_redraw()


func _finish_travel_animation() -> void:
	_travel_active = false
	_travel_progress = 1.0
	if is_node_ready():
		_hotspot_layer.set_locked(false)
	queue_redraw()
	travel_animation_finished.emit()
