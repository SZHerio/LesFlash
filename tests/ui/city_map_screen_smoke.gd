extends SceneTree

const CityMapScreenScene = preload("res://ui/screens/city_map/city_map_screen.tscn")
const CityMapScreenScript = preload("res://ui/screens/city_map/city_map_screen.gd")
const CityMapCanvasScript = preload("res://ui/components/city_map_canvas.gd")
const UiTheme = preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]
const OUTPUT_DIR := "res://docs/qa/m3a"

var _failures: Array[String] = []
var _travel_destination := ""
var _travel_mode := ""
var _back_requests := 0
var _animation_finishes := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise_size(test_size)
	if _failures.is_empty():
		print("M3B CITY MAP UI SMOKE PASSED: 360x640 and 540x960")
		quit(0)
		return
	for failure in _failures:
		push_error("M3B CITY MAP UI: %s" % failure)
	quit(1)


func _exercise_size(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.name = "CityMapViewport_%dx%d" % [test_size.x, test_size.y]
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var screen := CityMapScreenScene.instantiate() as CityMapScreenScript
	_require(screen != null, "%s CityMapScreen could not be instantiated" % test_size)
	if screen == null:
		viewport.queue_free()
		return
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.travel_requested.connect(_on_travel_requested)
	screen.back_requested.connect(_on_back_requested)
	screen.travel_animation_finished.connect(_on_animation_finished)
	viewport.add_child(screen)
	screen.present(_preview_model())
	for _frame in range(8):
		await process_frame

	_check_layout(screen, test_size)
	await _select_destination(screen, "market")
	_check_available_route(screen)
	if test_size == TEST_SIZES[0]:
		await _check_intents_and_animation(screen)
	else:
		await _check_standard_animation(screen)
	await _capture(viewport, test_size)

	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_layout(screen: CityMapScreenScript, test_size: Vector2i) -> void:
	_require(absf(screen.size.x - test_size.x) <= 2.0, "%s screen width is %.1f" % [test_size, screen.size.x])
	_require(absf(screen.size.y - test_size.y) <= 2.0, "%s screen height is %.1f" % [test_size, screen.size.y])
	var canvas := screen.get_node("%MapCanvas") as CityMapCanvasScript
	var trip_panel := screen.get_node("%TripPanel") as Control
	_require(canvas != null and canvas.size.x >= test_size.x - 60.0, "%s map is too narrow" % test_size)
	_require(canvas != null and canvas.size.y >= 200.0, "%s map is too short: %.1f" % [test_size, canvas.size.y])
	_require(canvas != null and not canvas.is_processing(), "%s idle map redraws every frame" % test_size)
	_require(trip_panel != null and trip_panel.size.y >= 154.0, "%s trip panel is too short" % test_size)
	for button_name in ["BackButton", "ConfirmButton"]:
		var button := screen.get_node("%%%s" % button_name) as BaseButton
		_require(button != null and button.size.x >= 48.0 and button.size.y >= 48.0, "%s %s touch target is too small" % [test_size, button_name])
	var modes := screen.get_node("%ModePicker") as SegmentedRow
	for child in modes.get_children():
		var segment := child as BaseButton
		_require(
			segment != null and segment.size.x >= 48.0 and segment.size.y >= 48.0,
			"%s transport segment touch target is too small" % test_size
		)
	if canvas != null:
		for node_id in ["market", "embankment", "clinic_yard"]:
			var touch_rect: Rect2 = canvas.get_node_touch_rect(node_id)
			_require(touch_rect.size.x >= 48.0 and touch_rect.size.y >= 48.0, "%s map node %s touch target is too small" % [test_size, node_id])


func _select_destination(screen: CityMapScreenScript, destination_id: String) -> void:
	var canvas := screen.get_node("%MapCanvas") as CityMapCanvasScript
	var point := canvas.get_node_position(destination_id)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	canvas.call("_gui_input", down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	up.pressed = false
	canvas.call("_gui_input", up)
	await process_frame


func _check_available_route(screen: CityMapScreenScript) -> void:
	var destination_label := screen.get_node("%DestinationLabel") as Label
	var picker := screen.get_node("%ModePicker") as SegmentedRow
	var confirm := screen.get_node("%ConfirmButton") as Button
	_require(destination_label.text == "Центральный рынок", "destination selection did not update the trip panel")
	_require(picker.get_child_count() == 2, "route should expose two transport modes")
	_require(picker.selected_id() == "walk", "first available transport mode was not selected")
	_require(
		picker.get_child(0).size.y >= 48.0 and picker.get_child(1).size.y >= 48.0,
		"transport choice must be visible without opening anything"
	)
	_require(not confirm.disabled, "available route left confirmation disabled")
	_require(confirm.text.contains("Пешком"), "confirmation does not name the selected transport")
	var meta := screen.get_node("%ModeMetaLabel") as Label
	_require(meta.text == "18 мин\nБесплатно", "numeric route duration or cost was not formatted for the player")


func _check_intents_and_animation(screen: CityMapScreenScript) -> void:
	_travel_destination = ""
	_travel_mode = ""
	_back_requests = 0
	_animation_finishes = 0

	var picker := screen.get_node("%ModePicker") as SegmentedRow
	var confirm := screen.get_node("%ConfirmButton") as Button
	var reason := screen.get_node("%ReasonLabel") as Label
	picker.option_selected.emit("tram")
	_require(confirm.disabled, "locked transport mode can still be confirmed")
	_require(reason.visible and reason.text.contains("маршрут"), "locked transport mode does not explain its reason")

	picker.option_selected.emit("walk")
	confirm.pressed.emit()
	_require(_travel_destination == "market", "travel intent lost the destination id")
	_require(_travel_mode == "walk", "travel intent lost the mode id")

	var back_button := screen.get_node("%BackButton") as Button
	back_button.pressed.emit()
	_require(_back_requests == 1, "back intent was not emitted")

	screen.set_reduced_motion(true)
	screen.animate_travel("station_square", "market")
	await process_frame
	await process_frame
	_require(_animation_finishes == 1, "reduced-motion travel did not finish deterministically")
	_require(_travel_destination == "market" and _travel_mode == "walk", "animation emitted an extra gameplay command")
	_require(not back_button.disabled, "controls stayed locked after travel animation")


func _check_standard_animation(screen: CityMapScreenScript) -> void:
	_animation_finishes = 0
	screen.set_reduced_motion(false)
	screen.animate_travel("station_square", "market")
	var back_button := screen.get_node("%BackButton") as Button
	_require(back_button.disabled, "travel controls did not lock during path animation")
	await create_timer(0.85).timeout
	_require(_animation_finishes == 1, "standard travel animation did not emit its completion signal")
	_require(not back_button.disabled, "standard travel animation left controls locked")


func _capture(viewport: SubViewport, test_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		print("M3B CITY MAP UI RENDER SKIPPED: headless display")
		return
	var texture := viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path := "%s/city_map_%dx%d.png" % [OUTPUT_DIR, test_size.x, test_size.y]
	var error := image.save_png(path)
	_require(error == OK, "could not save %s (error %d)" % [path, error])


func _preview_model() -> Dictionary:
	return {
		"district": {"id": "riverside", "title": "Приречный район"},
		"title": "Карта района",
		"current_location": {"id": "station_square", "title": "Вокзальная площадь"},
		"reduced_motion": false,
		"nodes": [
			{"id": "station_square", "title": "Вокзальная площадь", "position": Vector2(0.16, 0.20), "current": true, "known": true},
			{"id": "underpass", "title": "Старый переход", "position": Vector2(0.15, 0.54), "known": true},
			{"id": "market", "title": "Центральный рынок", "position": Vector2(0.49, 0.30), "known": true},
			{"id": "recycling_point", "title": "Пункт приёма", "position": Vector2(0.82, 0.18), "known": true},
			{"id": "clinic_yard", "title": "Двор поликлиники", "position": Vector2(0.48, 0.78), "known": true},
			{"id": "embankment", "title": "Набережная", "position": Vector2(0.82, 0.70), "known": true},
		],
		"routes": [
			{
				"from": "station_square",
				"to": "market",
				"bidirectional": true,
				"modes": [
					{"id": "walk", "transport": "Пешком", "duration": 18, "cost": 0, "available": true},
					{"id": "tram", "transport": "Трамвай", "duration": "7 мин", "cost": "12 ₽", "available": false, "reason": "На этом маршруте трамвай ещё не ходит."},
				],
			},
			{
				"from": "station_square",
				"to": "underpass",
				"bidirectional": true,
				"modes": [{"id": "walk", "transport": "Пешком", "duration": "9 мин", "cost": "Бесплатно", "available": true}],
			},
			{
				"from": "market",
				"to": "recycling_point",
				"bidirectional": true,
				"modes": [{"id": "walk", "transport": "Пешком", "duration": "14 мин", "cost": "Бесплатно", "available": true}],
			},
			{
				"from": "underpass",
				"to": "clinic_yard",
				"bidirectional": true,
				"modes": [{"id": "walk", "transport": "Пешком", "duration": "16 мин", "cost": "Бесплатно", "available": true}],
			},
			{
				"from": "clinic_yard",
				"to": "embankment",
				"bidirectional": true,
				"modes": [{"id": "walk", "transport": "Пешком", "duration": "12 мин", "cost": "Бесплатно", "available": true}],
			},
		],
	}


func _on_travel_requested(destination_id: String, mode_id: String) -> void:
	_travel_destination = destination_id
	_travel_mode = mode_id


func _on_back_requested() -> void:
	_back_requests += 1


func _on_animation_finished() -> void:
	_animation_finishes += 1


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
