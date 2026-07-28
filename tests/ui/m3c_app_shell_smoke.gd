extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
const LegacySession := preload("res://game/run/run_session.gd")
const SandboxAdapterScript := preload("res://app/session/sandbox_session_adapter.gd")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]
const OUTPUT_DIR := "res://docs/qa/m3c"

class MemoryPersistence extends SessionPersistence:
	var session: RunSession
	var saves := 0

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> RunSessionAdapter:
		session = LegacySession.create_location_first(characteristics, 61_337)
		session.run_state.add_item("simple_meal", 1)
		session.run_state.set_meter("hunger", 55)
		return SandboxAdapterScript.new(session)

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found"}

	func save_session(_session: RunSessionAdapter) -> Dictionary:
		saves += 1
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
		await _exercise(test_size)
	if _failures.is_empty():
		print("M3C APP SHELL SMOKE PASSED: inventory navigation, one commit/save and Back")
		quit(0)
		return
	for failure in _failures:
		push_error("M3C APP SHELL: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var persistence := MemoryPersistence.new()
	var shell := AppShellScene.instantiate() as AppShell
	var coordinator := shell.get_node("UiCoordinator") as UiCoordinator
	coordinator.configure(persistence, MemoryPreferences.new())
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	for _frame in range(5):
		await process_frame
	(shell.current_screen() as MainMenuScreen).new_game_requested.emit()
	await process_frame
	(shell.current_screen() as CharacterCreationScreen).character_confirmed.emit({
		"strength": 6,
		"charisma": 4,
		"intelligence": 5,
		"luck": 3,
	})
	for _frame in range(4):
		await process_frame
	await create_timer(0.28, true, false, true).timeout
	var before_time := persistence.session.run_state.calendar.elapsed_minutes
	var navigation := shell.get_node("%BottomNavigation") as BottomNavigation
	var items_button := navigation.get_node("%ItemsButton") as Button
	_require(not items_button.disabled, "%s items tab is disabled" % test_size)
	shell.navigation_requested.emit("items")
	for _frame in range(4):
		await process_frame
	var screen := shell.current_screen() as InventoryScreen
	_require(screen != null, "%s items tab did not open InventoryScreen" % test_size)
	if screen == null:
		return
	_require(
		persistence.session.run_state.calendar.elapsed_minutes == before_time,
		"%s opening inventory changed game time" % test_size
	)
	_require(
		screen.get_global_rect().end.y <= navigation.get_global_rect().position.y + 1.0,
		"%s inventory overlaps bottom navigation" % test_size
	)
	await _capture(viewport, test_size, "loaded")
	var stacks: Array = preload("res://core/inventory/inventory_state.gd").all_stacks(
		persistence.session.run_state.inventory
	)
	var meal_stack := ""
	for stack in stacks:
		if String(stack.get("item_id", "")) == "simple_meal":
			meal_stack = String(stack.get("stack_id", ""))
	var saves_before := persistence.saves
	screen.action_requested.emit(meal_stack, "use", 1, "")
	for _frame in range(4):
		await process_frame
	await create_timer(0.28, true, false, true).timeout
	_require(persistence.saves == saves_before + 1, "%s item command did not save exactly once" % test_size)
	_require(persistence.session.run_state.get_item_count("simple_meal") == 0, "%s use did not consume meal" % test_size)
	_require(
		persistence.session.run_state.calendar.elapsed_minutes == before_time + 12,
		"%s use did not apply declared decision time once" % test_size
	)
	(shell.get_node("SafeArea/ToastOverlay/Position/ToastPanel") as Control).visible = false
	await _capture(viewport, test_size, "empty")
	shell.set_font_scale(2.0)
	for _frame in range(3):
		await process_frame
	screen = shell.current_screen() as InventoryScreen
	var scroll := screen.get_node("%InventoryScroll") as ScrollContainer
	_require(scroll.size.y >= 160.0, "%s 200%% text collapsed inventory scroll" % test_size)
	await _capture(viewport, test_size, "text_200")
	shell.back_requested.emit()
	for _frame in range(3):
		await process_frame
	_require(shell.current_screen() is LocationScreen, "%s Back did not return to location" % test_size)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _capture(viewport: SubViewport, test_size: Vector2i, state_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s %s returned no render" % [test_size, state_name])
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path := "%s/inventory_%s_%dx%d.png" % [
		OUTPUT_DIR,
		state_name,
		test_size.x,
		test_size.y,
	]
	_require(image.save_png(path) == OK, "could not save %s" % path)
