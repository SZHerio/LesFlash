extends SceneTree

const LocationScreenScene = preload("res://ui/screens/location/location_screen.tscn")
const BottomNavigationScene = preload("res://ui/components/bottom_navigation.tscn")
const UiTheme = preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]
const OUTPUT_DIR := "res://docs/qa/m3a"

var _failures: Array[String] = []
var _last_action_id := ""
var _last_action_model: Dictionary = {}
var _last_status_id := ""
var _last_tab_id := ""
var _settings_requests := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for preview_size in TEST_SIZES:
		await _exercise_size(preview_size)
	if _failures.is_empty():
		print("M3 LOCATION UI SMOKE PASSED: 360x640 and 540x960")
		quit(0)
		return
	for failure in _failures:
		push_error("M3 LOCATION UI: %s" % failure)
	quit(1)


func _exercise_size(preview_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.name = "LocationViewport_%dx%d" % [preview_size.x, preview_size.y]
	viewport.size = preview_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var frame := VBoxContainer.new()
	frame.name = "LocationPreview_%dx%d" % [preview_size.x, preview_size.y]
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.theme = UiTheme
	frame.add_theme_constant_override("separation", 0)
	viewport.add_child(frame)

	var location_screen := LocationScreenScene.instantiate() as Control
	_require(location_screen != null, "%s LocationScreen could not be instantiated" % preview_size)
	if location_screen == null:
		root.remove_child(viewport)
		viewport.queue_free()
		return
	location_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_screen.connect("action_requested", _on_action_requested)
	location_screen.connect("status_requested", _on_status_requested)
	location_screen.connect("settings_requested", _on_settings_requested)
	frame.add_child(location_screen)

	var navigation := BottomNavigationScene.instantiate() as PanelContainer
	_require(navigation != null, "%s BottomNavigation could not be instantiated" % preview_size)
	if navigation == null:
		root.remove_child(viewport)
		viewport.queue_free()
		return
	navigation.connect("tab_requested", _on_tab_requested)
	frame.add_child(navigation)

	await process_frame
	location_screen.call("present", _preview_model(preview_size == TEST_SIZES[0]))
	if preview_size == TEST_SIZES[0]:
		var health_glyph := location_screen.get_node("%HealthGlyph") as StatusGlyph
		_require(
			is_equal_approx(float(health_glyph.get("_display_value")), 75.0),
			"StatusGlyph did not start its animation from the real pre-change value"
		)
	navigation.call("set_reduced_motion", preview_size != TEST_SIZES[0])
	navigation.call("present", {"active_tab": "place"})
	for _frame_index in range(8):
		await process_frame

	_check_layout(frame, location_screen, navigation, preview_size)
	await _capture_preview(viewport, preview_size)
	if preview_size == TEST_SIZES[0]:
		await _check_signals(location_screen, navigation)
		await process_frame
		var detail := location_screen.get_node_or_null("%StatusDetail") as Control
		_require(detail != null and detail.visible, "status detail did not open after StatusGlyph activation")

	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_layout(
	frame: VBoxContainer,
	location_screen: Control,
	navigation: PanelContainer,
	preview_size: Vector2i
) -> void:
	_require(absf(frame.size.x - preview_size.x) <= 2.0, "%s frame width is %.1f" % [preview_size, frame.size.x])
	_require(absf(frame.size.y - preview_size.y) <= 2.0, "%s frame height is %.1f" % [preview_size, frame.size.y])
	_require(location_screen.size.y >= 400.0, "%s location content is too short: %.1f" % [preview_size, location_screen.size.y])
	_require(navigation.size.y >= 58.0, "%s navigation touch height is too small" % preview_size)
	_require(navigation.position.y + navigation.size.y <= preview_size.y + 2.0, "%s navigation is clipped" % preview_size)

	var scroll := location_screen.get_node_or_null("%LocationScroll") as ScrollContainer
	var actions := location_screen.get_node_or_null("%ActionsList") as VBoxContainer
	var actions_count := location_screen.get_node_or_null("%ActionsCount") as Label
	_require(scroll != null and scroll.size.y >= 100.0, "%s scroll viewport is unusable" % preview_size)
	_require(actions != null and actions.get_child_count() == 5, "%s expected five action rows" % preview_size)
	_require(actions_count != null and actions_count.text == "4 доступно", "%s available action count is inaccurate" % preview_size)

	for glyph_name in ["HealthGlyph", "HungerGlyph", "EnergyGlyph", "TensionGlyph", "MoraleGlyph"]:
		var glyph := location_screen.get_node_or_null("%%%s" % glyph_name) as Control
		_require(glyph != null and glyph.size.x >= 48.0 and glyph.size.y >= 92.0, "%s %s touch target is too small" % [preview_size, glyph_name])


func _check_signals(location_screen: Control, navigation: PanelContainer) -> void:
	_last_action_id = ""
	_last_action_model.clear()
	_last_status_id = ""
	_last_tab_id = ""
	_settings_requests = 0

	var actions := location_screen.get_node("%ActionsList") as VBoxContainer
	var first_action := actions.get_child(0) as BaseButton
	first_action.pressed.emit()
	_require(_last_action_id == "look_around", "action intent did not preserve the action id")
	_require(String(_last_action_model.get("title", "")) == "Осмотреться", "action intent did not include its view-model")

	var scroll := location_screen.get_node("%LocationScroll") as ScrollContainer
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	var health := location_screen.get_node("%HealthGlyph") as BaseButton
	health.pressed.emit()
	_require(_last_status_id == "health", "StatusGlyph did not emit the status id")
	await process_frame
	await process_frame
	var detail := location_screen.get_node("%StatusDetail") as Control
	_require(scroll.get_global_rect().intersects(detail.get_global_rect()), "opened status detail remained outside the scroll viewport")

	var header := location_screen.get_node("%GameHeader") as Control
	var settings := header.get_node("%SettingsButton") as BaseButton
	settings.pressed.emit()
	_require(_settings_requests == 1, "header settings intent was not relayed")

	var map_button := navigation.get_node("%MapButton") as BaseButton
	map_button.pressed.emit()
	_require(_last_tab_id == "map", "bottom navigation did not emit the selected tab")


func _capture_preview(viewport: SubViewport, preview_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		print("M3 LOCATION UI RENDER SKIPPED: headless display")
		return
	var viewport_texture := viewport.get_texture()
	if viewport_texture == null:
		print("M3 LOCATION UI RENDER SKIPPED: viewport texture unavailable")
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		print("M3 LOCATION UI RENDER SKIPPED: renderer returned no pixels")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path := "%s/location_%dx%d.png" % [OUTPUT_DIR, preview_size.x, preview_size.y]
	var error := image.save_png(path)
	if error == OK:
		print("M3 LOCATION UI RENDERED: %s" % path)
	else:
		_failures.append("could not save %s (error %d)" % [path, error])


func _preview_model(animated: bool) -> Dictionary:
	return {
		"district_title": "Приречный район",
		"location_title": "Вокзальная площадь",
		"date_text": "12 сентября 1974",
		"time_text": "08:20",
		"money": 0,
		"background_key": "riverside_station_square_day",
		"psyche_intensity": 0.16,
		"description": "Утренний поток людей растекается от вокзала к остановкам. В запахе мокрого камня смешались кофе, дым и речной ветер.",
		"context_tags": ["Утро", "Людно", "Прохладно"],
		"reduced_motion": not animated,
		"statuses": [
			{"id": "health", "title": "Здоровье", "value": 72, "delta": -3, "detail": "Ссадины обработаны, но плечо всё ещё ноет после ночи.", "forecast": "При дальнейшем ухудшении тяжёлая работа станет недоступна."},
			{"id": "hunger", "title": "Голод", "value": 39, "delta": 5, "detail": "Есть хочется, но это пока не мешает обычным действиям.", "forecast": "Сильный голод увеличит расход энергии."},
			{"id": "energy", "title": "Энергия", "value": 58, "delta": -6, "detail": "Сил хватит на несколько коротких дел.", "forecast": "Отдых или еда помогут восстановиться."},
			{"id": "tension", "title": "Напряжение", "value": 44, "delta": 2, "detail": "Шум площади мешает расслабиться.", "forecast": "Высокое напряжение сузит спокойные варианты ответа."},
			{"id": "morale", "title": "Мораль", "value": 61, "delta": 4, "detail": "Новый день пока кажется управляемым.", "forecast": "Поддержка и удачные решения укрепят состояние."},
		],
		"actions": [
			{"id": "look_around", "title": "Осмотреться", "description": "Понять ритм площади и заметить доступные возможности.", "time_text": "5 мин", "risk_text": "Без риска", "variant": "accent"},
			{"id": "search", "title": "Искать полезное", "description": "Зайти за служебные павильоны и внимательно осмотреть территорию.", "time_text": "От 10 мин", "energy_text": "Энергия −4", "risk_text": "Риск: средний"},
			{"id": "ask_worker", "title": "Поговорить с носильщиком", "description": "Расспросить о подработке и безопасных местах поблизости.", "time_text": "15 мин", "risk_text": "Риск: низкий"},
			{"id": "buy_tea", "title": "Купить горячий чай", "description": "Согреться у киоска и ненадолго перевести дух.", "time_text": "10 мин", "cost_text": "Нужно 18 ₽", "enabled": false, "locked_reason": "Не хватает 18 ₽"},
			{"id": "cross_tracks", "title": "Срезать путь через пути", "description": "Быстрый, но опасный способ попасть к складам.", "time_text": "8 мин", "risk_text": "Риск: высокий", "variant": "danger"},
		],
	}


func _on_action_requested(action_id: String, action_model: Dictionary) -> void:
	_last_action_id = action_id
	_last_action_model = action_model


func _on_status_requested(status_id: String) -> void:
	_last_status_id = status_id


func _on_tab_requested(tab_id: String) -> void:
	_last_tab_id = tab_id


func _on_settings_requested() -> void:
	_settings_requests += 1


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
