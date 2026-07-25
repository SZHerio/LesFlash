class_name CityMapScreen
extends Control

signal travel_requested(destination_id: String, mode_id: String)
signal back_requested
signal travel_animation_finished

const CityMapCanvasScript = preload("res://ui/components/city_map_canvas.gd")

@onready var _layout: VBoxContainer = %Layout
@onready var _back_button: Button = %BackButton
@onready var _body_scroll: ScrollContainer = %BodyScroll
@onready var _district_label: Label = %DistrictLabel
@onready var _title_label: Label = %TitleLabel
@onready var _current_label: Label = %CurrentLabel
@onready var _map_canvas: CityMapCanvasScript = %MapCanvas
@onready var _trip_panel: PanelContainer = %TripPanel
@onready var _destination_label: Label = %DestinationLabel
@onready var _route_state: Label = %RouteState
@onready var _mode_picker: SegmentedRow = %ModePicker
@onready var _mode_meta_label: Label = %ModeMetaLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _confirm_button: Button = %ConfirmButton

var _model: Dictionary = {}
var _nodes_by_id: Dictionary = {}
var _current_id := ""
var _selected_destination_id := ""
var _mode_models: Array[Dictionary] = []
var _selected_mode_id := ""
var _reduced_motion := false
var _travel_animating := false
var _entrance_tween: Tween


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_map_canvas.destination_selected.connect(_on_destination_selected)
	_map_canvas.travel_animation_finished.connect(_on_travel_animation_finished)
	_mode_picker.option_selected.connect(_select_mode)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_show_empty_trip()


func present(view_model: Dictionary) -> void:
	_model = view_model.duplicate(true)
	_body_scroll.scroll_vertical = 0
	_reduced_motion = bool(view_model.get("reduced_motion", _reduced_motion))
	_district_label.text = _district_title(view_model).to_upper()
	_title_label.text = String(view_model.get("title", "Карта района"))

	_index_nodes(view_model.get("nodes", []))
	_current_id = _current_location_id(view_model.get("current_location", ""))
	if _current_id.is_empty():
		for node_id in _nodes_by_id:
			if bool(Dictionary(_nodes_by_id[node_id]).get("current", false)):
				_current_id = String(node_id)
				break
	_current_label.text = "Сейчас: %s" % _node_title(_current_id, "неизвестное место")

	_map_canvas.set_reduced_motion(_reduced_motion)
	_map_canvas.present({
		"current_location": _current_id,
		"nodes": view_model.get("nodes", []),
		"routes": view_model.get("routes", []),
	})

	var requested_destination := String(view_model.get("selected_destination_id", ""))
	if not requested_destination.is_empty() and _nodes_by_id.has(requested_destination):
		_on_destination_selected(requested_destination)
	elif not _nodes_by_id.has(_selected_destination_id) or _selected_destination_id == _current_id:
		_selected_destination_id = ""
		_show_empty_trip()
	else:
		_on_destination_selected(_selected_destination_id)
	_animate_entrance()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if is_node_ready():
		_map_canvas.set_reduced_motion(enabled)
		if enabled and _entrance_tween != null and _entrance_tween.is_valid():
			_entrance_tween.kill()
			_layout.modulate = Color.WHITE


func animate_travel(from_id: String, to_id: String) -> void:
	_travel_animating = true
	_set_controls_locked(true)
	_route_state.text = "●"
	_reason_label.text = "Поездка рассчитана. Показываем путь."
	_reason_label.visible = true
	_map_canvas.animate_travel(from_id, to_id)


func _on_destination_selected(destination_id: String) -> void:
	if _travel_animating or destination_id == _current_id or not _nodes_by_id.has(destination_id):
		return
	_selected_destination_id = destination_id
	_map_canvas.set_selected_destination(destination_id)
	_destination_label.text = _node_title(destination_id, "Неизвестное место")
	_present_route(_find_route(_current_id, destination_id))


func _present_route(route: Dictionary) -> void:
	_mode_picker.present([], "")
	_mode_models.clear()
	_selected_mode_id = ""
	if route.is_empty():
		_confirm_button.disabled = true
		_mode_meta_label.text = "Нет пути"
		_reason_label.text = "Из текущего места сюда пока нет известного маршрута."
		_reason_label.visible = true
		_route_state.text = "×"
		return

	for raw_mode in route.get("modes", []):
		if not raw_mode is Dictionary:
			continue
		var mode := Dictionary(raw_mode).duplicate(true)
		if String(mode.get("id", "")).is_empty():
			continue
		_mode_models.append(mode)
	if _mode_models.is_empty():
		var fallback_mode := route.duplicate(true)
		fallback_mode["id"] = String(route.get("mode_id", "route"))
		fallback_mode["transport"] = String(route.get("transport", "Маршрут"))
		_mode_models.append(fallback_mode)

	var first_available := ""
	for mode: Dictionary in _mode_models:
		if bool(mode.get("available", true)):
			first_available = String(mode["id"])
			break
	if first_available.is_empty():
		first_available = String(_mode_models[0]["id"])
	_mode_picker.present(_mode_options(), first_available)
	_select_mode(first_available)


## Icons make the choice readable at a glance; the label stays for anything the
## glyph cannot say and for a player who does not recognise it.
func _mode_options() -> Array:
	var options: Array = []
	for mode: Dictionary in _mode_models:
		options.append({
			"id": String(mode.get("id", "")),
			"title": _mode_title(mode),
			"icon": String(mode.get("id", "")),
			"enabled": bool(mode.get("available", true)),
		})
	return options


func _select_mode(mode_id: String) -> void:
	var mode := _find_mode(mode_id)
	if mode.is_empty():
		_selected_mode_id = ""
		_confirm_button.disabled = true
		return
	_mode_picker.select(mode_id)
	_selected_mode_id = String(mode.get("id", ""))
	var available := bool(mode.get("available", true))
	_mode_meta_label.text = _mode_meta(mode)
	_reason_label.text = String(mode.get("reason", mode.get("locked_reason", "")))
	_reason_label.visible = not available and not _reason_label.text.is_empty()
	_confirm_button.disabled = not available or _travel_animating
	_confirm_button.text = "Отправиться · %s" % _mode_title(mode)
	_route_state.text = "●" if available else "×"


func _on_confirm_pressed() -> void:
	if _confirm_button.disabled or _travel_animating:
		return
	if _selected_destination_id.is_empty() or _selected_mode_id.is_empty():
		return
	travel_requested.emit(_selected_destination_id, _selected_mode_id)


func _on_travel_animation_finished() -> void:
	_travel_animating = false
	_set_controls_locked(false)
	travel_animation_finished.emit()


func _set_controls_locked(locked: bool) -> void:
	_back_button.disabled = locked
	_mode_picker.set_locked(locked or _mode_models.is_empty())
	if locked:
		_confirm_button.disabled = true
	elif not _mode_models.is_empty():
		_select_mode(_selected_mode_id)


func _show_empty_trip() -> void:
	_map_canvas.set_selected_destination("")
	_destination_label.text = "Выберите место на карте"
	_mode_picker.present([], "")
	_mode_models.clear()
	_mode_meta_label.text = "Время и цена"
	_reason_label.text = "Сначала выберите точку назначения."
	_reason_label.visible = true
	_confirm_button.text = "Отправиться"
	_confirm_button.disabled = true
	_route_state.text = "○"


func _find_mode(mode_id: String) -> Dictionary:
	for mode: Dictionary in _mode_models:
		if String(mode.get("id", "")) == mode_id:
			return mode
	return {}


func _find_route(from_id: String, to_id: String) -> Dictionary:
	for raw_route in _model.get("routes", []):
		if not raw_route is Dictionary:
			continue
		var route := Dictionary(raw_route)
		var route_from := String(route.get("from", route.get("origin_id", from_id)))
		var route_to := String(route.get("to", route.get("destination_id", "")))
		if (
			(route_from == from_id and route_to == to_id)
			or (bool(route.get("bidirectional", false)) and route_from == to_id and route_to == from_id)
		):
			return route.duplicate(true)
	return {}


func _index_nodes(raw_nodes: Variant) -> void:
	_nodes_by_id.clear()
	if not raw_nodes is Array:
		return
	for raw_node in raw_nodes:
		if not raw_node is Dictionary:
			continue
		var node_id := String(raw_node.get("id", ""))
		if not node_id.is_empty():
			_nodes_by_id[node_id] = Dictionary(raw_node).duplicate(true)


func _district_title(view_model: Dictionary) -> String:
	var raw_district: Variant = view_model.get("district", view_model.get("district_title", "Район"))
	if raw_district is Dictionary:
		return String(raw_district.get("title", "Район"))
	return String(raw_district)


func _current_location_id(raw_current: Variant) -> String:
	if raw_current is Dictionary:
		return String(raw_current.get("id", ""))
	return String(raw_current)


func _node_title(node_id: String, fallback: String) -> String:
	if not _nodes_by_id.has(node_id):
		return fallback
	return String(Dictionary(_nodes_by_id[node_id]).get("title", fallback))


func _mode_title(mode: Dictionary) -> String:
	return String(mode.get("transport", mode.get("title", "Маршрут")))


func _mode_meta(mode: Dictionary) -> String:
	var parts: Array[String] = []
	var duration := _duration_text(mode)
	var cost := _cost_text(mode)
	if not duration.is_empty():
		parts.append(duration)
	if not cost.is_empty():
		parts.append(cost)
	return "\n".join(PackedStringArray(parts)) if not parts.is_empty() else "Без данных"


func _duration_text(mode: Dictionary) -> String:
	if mode.has("duration_text"):
		return String(mode.get("duration_text", ""))
	var raw_duration: Variant = mode.get("duration", "")
	if raw_duration is int or raw_duration is float:
		return "%d мин" % int(round(float(raw_duration)))
	return String(raw_duration)


func _cost_text(mode: Dictionary) -> String:
	if mode.has("cost_text"):
		return String(mode.get("cost_text", ""))
	var raw_cost: Variant = mode.get("cost", "")
	if raw_cost is int or raw_cost is float:
		var amount := int(round(float(raw_cost)))
		return "Бесплатно" if amount <= 0 else "%d ₽" % amount
	return String(raw_cost)


func _animate_entrance() -> void:
	if _reduced_motion:
		_layout.modulate = Color.WHITE
		return
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_layout.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_entrance_tween = create_tween()
	_entrance_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_entrance_tween.tween_property(_layout, "modulate", Color.WHITE, 0.22)
