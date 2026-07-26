extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const OUTPUT_DIR := "res://docs/qa/m3b"
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

class MemoryPersistence extends SessionPersistence:
	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> FirstDaySessionAdapter:
		return SandboxAdapter.create(characteristics, 41_337) as FirstDaySessionAdapter

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found"}

	func save_session(_session: FirstDaySessionAdapter) -> Dictionary:
		return {"ok": true}


class MemoryPreferences extends UiPreferences:
	func load_from_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true, "created": true}

	func save_to_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true}


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise_size(test_size)
	if _failures.is_empty():
		print("M3B APP SHELL SMOKE PASSED: 360x640 and 540x960, including 200% text")
		quit(0)
		return
	for failure in _failures:
		push_error("M3B APP SHELL SMOKE: %s" % failure)
	quit(1)


func _exercise_size(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell := AppShellScene.instantiate() as AppShell
	var coordinator := shell.get_node("UiCoordinator") as UiCoordinator
	coordinator.configure(MemoryPersistence.new(), MemoryPreferences.new())
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	for _frame in range(5):
		await process_frame

	var menu := shell.current_screen() as MainMenuScreen
	_require(menu != null, "%s main menu did not boot" % test_size)
	if menu == null:
		return
	menu.new_game_requested.emit()
	await process_frame
	var creation := shell.current_screen() as CharacterCreationScreen
	_require(creation != null, "%s character creation did not open" % test_size)
	if creation == null:
		return
	creation.character_confirmed.emit({
		"strength": 10,
		"charisma": 6,
		"intelligence": 1,
		"luck": 1,
	})
	for _frame in range(4):
		await process_frame
	await create_timer(0.28, true, false, true).timeout
	var location_screen := shell.current_screen() as LocationScreen
	_require(location_screen != null, "%s new run did not open its location" % test_size)
	if location_screen == null:
		return
	_require(
		location_screen.get_node("%ActionsList").get_child_count() > 0,
		"%s starting location has no rendered ordinary action" % test_size
	)
	await _capture(viewport, test_size, "location")

	var navigation := shell.get_node("%BottomNavigation") as BottomNavigation
	var map_button := navigation.get_node("%MapButton") as Button
	var place_button := navigation.get_node("%PlaceButton") as Button
	_require(navigation.visible, "%s bottom navigation is not persistent" % test_size)
	_require(not map_button.disabled and not place_button.disabled, "%s place/map tabs are not enabled" % test_size)
	_require(map_button.size.y >= 48.0 and place_button.size.y >= 48.0, "%s navigation touch target is too small" % test_size)

	await _exercise_hero_tab(shell, navigation, test_size)

	await create_timer(0.30, true, false, true).timeout
	shell.navigation_requested.emit("map")
	for _frame in range(4):
		await process_frame
	await create_timer(0.28, true, false, true).timeout
	var map_screen := shell.current_screen() as CityMapScreen
	_require(map_screen != null, "%s map tab did not open CityMapScreen" % test_size)
	if map_screen == null:
		return
	var canvas := map_screen.get_node("%MapCanvas") as CityMapCanvas
	var trip_panel := map_screen.get_node("%TripPanel") as Control
	var confirm := map_screen.get_node("%ConfirmButton") as Button
	var header := map_screen.get_node("%Header") as Control
	var body_scroll := map_screen.get_node("%BodyScroll") as ScrollContainer
	_require(header.get_global_rect().position.y >= 0.0, "%s map header is clipped above the viewport" % test_size)
	_require(canvas.size.y >= 150.0, "%s integrated map canvas is too short: %.1f" % [test_size, canvas.size.y])
	_require(trip_panel.size.y >= 154.0, "%s integrated trip panel is clipped" % test_size)
	_require(confirm.size.y >= 48.0, "%s trip confirmation touch target is too small" % test_size)
	_require(map_screen.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0, "%s map overlaps navigation" % test_size)
	_require(body_scroll.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0, "%s map scroll area overlaps navigation" % test_size)
	_select_first_available_destination(map_screen)
	await process_frame
	_require(not confirm.disabled, "%s available map route cannot be confirmed" % test_size)

	if test_size == TEST_SIZES.front():
		await _capture(viewport, test_size, "map")
	shell.set_font_scale(2.0)
	for _frame in range(4):
		await process_frame
	await create_timer(0.10, true, false, true).timeout
	_require(confirm.is_visible_in_tree(), "%s 200%% text hid route confirmation" % test_size)
	_require(header.get_global_rect().position.y >= 0.0, "%s 200%% text clipped the map header" % test_size)
	body_scroll.scroll_vertical = int(body_scroll.get_v_scroll_bar().max_value)
	await process_frame
	_require(trip_panel.get_global_rect().position.y >= body_scroll.get_global_rect().position.y - 1.0, "%s 200%% trip panel cannot be scrolled into view" % test_size)
	_require(trip_panel.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0, "%s 200%% trip panel overlaps navigation after scrolling" % test_size)
	_require(confirm.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0, "%s 200%% text overlaps navigation" % test_size)
	await _capture(viewport, test_size, "map", "_text_200")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


## The hero tab is a read-only view of the run. Opening it must cost nothing —
## no minute of game time, no save — and it must come back to the place screen.
func _exercise_hero_tab(
	shell: AppShell,
	navigation: BottomNavigation,
	test_size: Vector2i
) -> void:
	var hero_button := navigation.get_node("%HeroButton") as Button
	_require(not hero_button.disabled, "%s hero tab is disabled" % test_size)
	# Both screens render the same clock, so an unchanged reading proves the tab
	# cost no game time and that the hero header follows the shell rather than
	# inventing its own state.
	var before_clock := _clock_text(shell.current_screen())
	await create_timer(0.30, true, false, true).timeout
	shell.navigation_requested.emit("hero")
	for _frame in range(4):
		await process_frame
	var hero_screen := shell.current_screen() as HeroScreen
	_require(hero_screen != null, "%s hero tab did not open HeroScreen" % test_size)
	if hero_screen == null:
		return
	_require(
		not before_clock.is_empty() and _clock_text(hero_screen) == before_clock,
		"%s hero clock reads «%s», the place screen read «%s»"
			% [test_size, _clock_text(hero_screen), before_clock]
	)
	_require(
		hero_screen.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0,
		"%s hero screen overlaps bottom navigation" % test_size
	)
	var psyche := hero_screen.get_node("%PsycheStep") as Label
	_require(
		not psyche.text.is_empty() and not psyche.text.is_valid_int(),
		"%s hero screen shows the psyche as «%s» instead of a word" % [test_size, psyche.text]
	)
	shell.back_requested.emit()
	for _frame in range(4):
		await process_frame
	_require(
		shell.current_screen() is LocationScreen,
		"%s back from the hero tab did not return to the place screen" % test_size
	)
	await create_timer(0.28, true, false, true).timeout


func _clock_text(screen: Control) -> String:
	if screen == null:
		return ""
	var label := screen.find_child("DateLabel", true, false) as Label
	return label.text if label != null else ""


func _capture(
	viewport: SubViewport,
	test_size: Vector2i,
	screen_name: String,
	suffix: String = ""
) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s viewport returned no image" % test_size)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path := "%s/m3b_shell_%s_%dx%d%s.png" % [
		OUTPUT_DIR,
		screen_name,
		test_size.x,
		test_size.y,
		suffix,
	]
	_require(image.save_png(path) == OK, "could not save %s" % path)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _select_first_available_destination(screen: CityMapScreen) -> void:
	var model: Dictionary = screen.get("_model")
	for raw_route in Array(model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var has_available_mode := false
		for raw_mode in Array(raw_route.get("modes", [])):
			if raw_mode is Dictionary and bool(raw_mode.get("available", false)):
				has_available_mode = true
				break
		if has_available_mode:
			screen.call("_on_destination_selected", String(raw_route.get("to", "")))
			return
