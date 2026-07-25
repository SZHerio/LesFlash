extends SceneTree

const MainScene := preload("res://ui/main.tscn")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const MainMenuScene := preload("res://ui/screens/main_menu/main_menu.tscn")
const SettingsScene := preload("res://ui/screens/settings/settings_screen.tscn")
const ChoiceScene := preload("res://ui/screens/choice/choice_screen.tscn")
const ResultScene := preload("res://ui/screens/result/result_screen.tscn")
const LocationScene := preload("res://ui/screens/location/location_screen.tscn")
const TEST_SIZES: Array[Vector2i] = [
	Vector2i(360, 640),
	Vector2i(540, 960),
	Vector2i(432, 936),
]
const OUTPUT_DIR := "res://docs/qa/m3a"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise_size(test_size)
	if _failures.is_empty():
		print("M3 APP SHELL SMOKE PASSED: 360x640, 540x960, 432x936 and 200% text")
		quit(0)
		return
	for failure in _failures:
		push_error("M3 APP SHELL: %s" % failure)
	quit(1)


func _exercise_size(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell := MainScene.instantiate() as AppShell
	_require(shell != null, "%s AppShell could not be instantiated" % test_size)
	if shell == null:
		viewport.queue_free()
		return
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	for _frame in range(10):
		await process_frame

	var menu := shell.current_screen() as MainMenuScreen
	_require(menu != null, "%s main menu was not presented by coordinator" % test_size)
	_check_shell_layout(shell, test_size)
	if menu != null:
		_check_touch_targets(menu, "%s menu" % test_size)
	await _capture(viewport, "menu_%dx%d" % [test_size.x, test_size.y])

	if menu != null:
		menu.new_game_requested.emit()
		for _frame in range(6):
			await process_frame
	var creation := shell.current_screen() as CharacterCreationScreen
	_require(creation != null, "%s creation screen did not open" % test_size)
	if creation != null:
		_check_touch_targets(creation, "%s creation" % test_size)
	await _capture(viewport, "creation_%dx%d" % [test_size.x, test_size.y])

	shell.set_font_scale(2.0)
	shell.set_reduced_motion(true)
	for _frame in range(8):
		await process_frame
	_require(shell.theme.default_font_size >= UiTheme.default_font_size * 2, "%s default text did not reach 200%%" % test_size)
	if creation != null:
		_check_touch_targets(creation, "%s creation 200%%" % test_size)
		_check_horizontal_bounds(creation, test_size)
		_check_visible_text(creation, "%s creation 200%%" % test_size)
	if test_size == TEST_SIZES[0]:
		await _capture(viewport, "creation_360x640_text_200")

	var large_menu := shell.show_screen(MainMenuScene) as MainMenuScreen
	large_menu.present({"can_continue": false})
	await _settle()
	_check_screen_at_200(large_menu, test_size, "menu")
	if test_size == TEST_SIZES[0]:
		await _capture(viewport, "menu_360x640_text_200")

	var settings := shell.show_screen(SettingsScene) as SettingsScreen
	settings.present({
		"show_locked_options": false,
		"psyche_effect_mode": "full",
		"font_scale": 2.0,
		"reduced_motion": true,
	})
	await _settle()
	_check_screen_at_200(settings, test_size, "settings")

	var choice := shell.show_screen(ChoiceScene) as ChoiceScreen
	choice.present(_choice_model())
	await _settle()
	_check_screen_at_200(choice, test_size, "choice")

	var result := shell.show_screen(ResultScene) as ResultScreen
	result.present(_result_model())
	await _settle()
	_check_screen_at_200(result, test_size, "result")

	shell.set_navigation_visible(true)
	shell.present_navigation({"active_tab": "place"})
	var location := shell.show_screen(LocationScene) as LocationScreen
	location.present(_location_model())
	await _settle()
	_check_screen_at_200(location, test_size, "location")
	_check_touch_targets(shell.get_node("%BottomNavigation"), "%s navigation 200%%" % test_size)
	if test_size == TEST_SIZES[0]:
		await _capture(viewport, "location_360x640_text_200")

	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_shell_layout(shell: AppShell, test_size: Vector2i) -> void:
	_require(absf(shell.size.x - test_size.x) <= 2.0, "%s shell width is %.1f" % [test_size, shell.size.x])
	_require(absf(shell.size.y - test_size.y) <= 2.0, "%s shell height is %.1f" % [test_size, shell.size.y])
	var host := shell.get_node_or_null("%ScreenHost") as Control
	_require(host != null and host.size.x >= minf(328.0, test_size.x - 32.0), "%s ScreenHost is too narrow" % test_size)
	_require(host != null and host.size.y >= test_size.y - 110.0, "%s ScreenHost does not fill the safe vertical area" % test_size)


func _check_touch_targets(node: Node, context: String) -> void:
	for child in node.find_children("*", "BaseButton", true, false):
		var button := child as BaseButton
		if not button.visible:
			continue
		_require(button.size.y >= 48.0, "%s button '%s' is only %.1f px high" % [context, button.name, button.size.y])
		_require(button.size.x >= 48.0, "%s button '%s' is only %.1f px wide" % [context, button.name, button.size.x])


func _check_screen_at_200(screen: Control, test_size: Vector2i, label: String) -> void:
	_check_touch_targets(screen, "%s %s 200%%" % [test_size, label])
	_check_horizontal_bounds(screen, test_size)
	_check_visible_text(screen, "%s %s 200%%" % [test_size, label])


func _check_horizontal_bounds(screen: Control, test_size: Vector2i) -> void:
	for child in screen.find_children("*", "Control", true, false):
		var control := child as Control
		if control.owner == null or not control.visible or control is HScrollBar or control is VScrollBar:
			continue
		var rect := control.get_global_rect()
		var right_edge := rect.end.x
		_require(
			right_edge <= float(test_size.x) + 2.0,
			"%s '%s' overflows horizontally at 200%% (x=%.1f width=%.1f right=%.1f)" % [test_size, control.name, rect.position.x, rect.size.x, right_edge]
		)


func _check_visible_text(screen: Control, context: String) -> void:
	for child in screen.find_children("*", "Label", true, false):
		var label := child as Label
		if not label.visible or label.text.is_empty():
			continue
		_require(
			label.get_visible_line_count() >= label.get_line_count(),
			"%s label '%s' hides one or more lines" % [context, label.name]
		)


func _settle() -> void:
	for _frame in range(8):
		await process_frame


func _capture(viewport: SubViewport, basename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var texture := viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error := image.save_png("%s/%s.png" % [OUTPUT_DIR, basename])
	_require(error == OK, "could not save preview %s" % basename)


func _choice_model() -> Dictionary:
	return {
		"eyebrow": "СИТУАЦИЯ",
		"title": "Неожиданный разговор у служебного входа",
		"context": "Вокзальная площадь",
		"body": "Незнакомец задаёт несколько настойчивых вопросов. Ответ может открыть полезный контакт или создать новую проблему.",
		"section_title": "Как поступить",
		"options": [
			{"id": "talk", "title": "Спокойно объяснить своё положение", "description": "Попробовать договориться без давления.", "enabled": true},
			{"id": "leave", "title": "Уйти, не продолжая разговор", "description": "Не рисковать и сохранить дистанцию.", "enabled": true},
			{"id": "press", "title": "Потребовать помощи", "enabled": false, "locked_reason": "Недостаточно харизмы: требуется 7"},
		],
	}


func _result_model() -> Dictionary:
	return {
		"eyebrow": "СМЕНА ЗАВЕРШЕНА",
		"title": "Работа выполнена аккуратно",
		"body": "Хозяин пункта принял результат, но предупредил, что в следующий раз будет внимательнее следить за сортировкой.",
		"facts": [
			"Деньги: +24 ₽",
			"Энергия: -7",
			"Время: +120 мин",
			"Работа с грузом: +1",
		],
		"confirm_text": "Вернуться к месту",
	}


func _location_model() -> Dictionary:
	return {
		"district_title": "Приречный район",
		"location_title": "Вокзальная площадь",
		"date_text": "12.09.1974",
		"time_text": "08:20",
		"money": 0,
		"background_key": "riverside_station_square_day",
		"description": "Утренний поток людей растекается от вокзала к остановкам. Здесь легко затеряться и заметить возможность.",
		"context_tags": ["Утро", "Людно", "Прохладно"],
		"reduced_motion": true,
		"statuses": {
			"health": 72, "hunger": 39, "energy": 58, "tension": 44, "morale": 61,
		},
		"actions": [
			{"id": "look", "title": "Осмотреться", "description": "Понять ритм площади и доступные возможности.", "enabled": true},
			{"id": "work", "title": "Спросить о подработке", "description": "Поговорить с людьми у разгрузочной площадки.", "enabled": true},
			{"id": "closed", "title": "Купить горячую еду", "enabled": false, "locked_reason": "Не хватает денег"},
		],
	}


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
