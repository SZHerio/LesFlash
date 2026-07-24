extends SceneTree

## End-to-end wiring for the search mini-game and the encounter it raises:
## location → search → find → encounter → answer → back to the location.

const AppShellScene := preload("res://app/app_shell.tscn")
const LegacySession := preload("res://game/first_day/first_day_session.gd")
const SandboxAdapterScript := preload("res://app/session/sandbox_session_adapter.gd")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]
const OUTPUT_DIR := "res://docs/qa/m3d"
const ZONE_LOCATION_ID := "underpass"

class MemoryPersistence extends SessionPersistence:
	var session: FirstDaySession
	var saves := 0

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> FirstDaySessionAdapter:
		session = LegacySession.create_location_first(characteristics, 74_112)
		# Luck decides where a run starts; the authored zone lives here.
		session.location = ZONE_LOCATION_ID
		return SandboxAdapterScript.new(session)

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found"}

	func save_session(_session: FirstDaySessionAdapter) -> Dictionary:
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
		print("M3D SEARCH APP SHELL SMOKE PASSED: entry, find, encounter and exit")
		quit(0)
		return
	for failure in _failures:
		push_error("M3D SEARCH APP SHELL: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var persistence := MemoryPersistence.new()
	var shell := AppShellScene.instantiate() as AppShell
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(shell.get_node("UiCoordinator") as UiCoordinator).configure(
		persistence,
		MemoryPreferences.new()
	)
	viewport.add_child(shell)
	for _frame in range(5):
		await process_frame
	(shell.current_screen() as MainMenuScreen).new_game_requested.emit()
	await process_frame
	(shell.current_screen() as CharacterCreationScreen).character_confirmed.emit({
		"strength": 5, "charisma": 6, "intelligence": 4, "luck": 3
	})
	for _frame in range(4):
		await process_frame
	await _settle()

	var location := shell.current_screen() as LocationScreen
	_require(location != null, "%s run did not open the location" % test_size)
	if location == null:
		return
	var search_action := _find_search_action(persistence.session)
	_require(not search_action.is_empty(), "%s location offers no search action" % test_size)
	if search_action.is_empty():
		return

	var time_before := persistence.session.run_state.calendar.elapsed_minutes
	location.action_requested.emit(String(search_action.get("id", "")), search_action)
	for _frame in range(4):
		await process_frame
	await _settle()
	var search := shell.current_screen() as SearchScreen
	_require(search != null, "%s search action did not open the search screen" % test_size)
	if search == null:
		return
	_require(
		persistence.session.run_state.calendar.elapsed_minutes == time_before,
		"%s entering the search spent game time" % test_size
	)
	var navigation := shell.get_node("%BottomNavigation") as BottomNavigation
	_require(
		not navigation.visible,
		"%s search left the bottom navigation on screen" % test_size
	)
	await _capture(viewport, test_size, "search_entry")

	# Walking is free: it must neither spend time nor write a save.
	var saves_before := persistence.saves
	await _walk_to(shell, search, persistence, "open_dumpster")
	search = shell.current_screen() as SearchScreen
	_require(
		persistence.session.run_state.calendar.elapsed_minutes == time_before,
		"%s walking spent game time" % test_size
	)
	_require(persistence.saves == saves_before, "%s walking wrote a save" % test_size)

	search.interaction_requested.emit("open_dumpster", "sort_by_hand")
	for _frame in range(4):
		await process_frame
	await _settle()
	_require(
		persistence.session.run_state.calendar.elapsed_minutes > time_before,
		"%s a confirmed decision did not spend time" % test_size
	)
	_require(persistence.saves == saves_before + 1, "%s decision did not save once" % test_size)
	var ground: Array = Array(
		persistence.session.active_activity["snapshot"].get("ground_items", [])
	)
	_require(not ground.is_empty(), "%s the resolved object produced no find" % test_size)
	await _capture(viewport, test_size, "search_loot")

	# Raising trespass past the threshold must produce a real encounter card.
	await _walk_to(shell, shell.current_screen() as SearchScreen, persistence, "market_fence")
	search = shell.current_screen() as SearchScreen
	search.interaction_requested.emit("market_fence", "slip_through")
	for _frame in range(4):
		await process_frame
	await _settle()
	var choice := shell.current_screen() as ChoiceScreen
	_require(choice != null, "%s risk threshold did not open an encounter" % test_size)
	if choice == null:
		return
	await _capture(viewport, test_size, "search_encounter")
	var option_id := _first_available_option(persistence.session)
	_require(not option_id.is_empty(), "%s encounter offers no available answer" % test_size)
	if option_id.is_empty():
		return
	choice.action_requested.emit(option_id)
	for _frame in range(4):
		await process_frame
	await _settle()
	_require(
		shell.current_screen() is SearchScreen,
		"%s answering did not hand the zone back" % test_size
	)
	_require(
		Dictionary(
			persistence.session.active_activity["snapshot"].get("pending_encounter", {})
		).is_empty(),
		"%s the answered encounter stayed pending" % test_size
	)

	shell.back_requested.emit()
	for _frame in range(4):
		await process_frame
	await _settle()
	_require(
		shell.current_screen() is LocationScreen,
		"%s Back did not leave the zone for the location" % test_size
	)
	_require(
		not persistence.session.is_search_active(),
		"%s leaving the zone left the search active" % test_size
	)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _walk_to(
	shell: AppShell,
	search: SearchScreen,
	persistence: MemoryPersistence,
	object_id: String
) -> void:
	if search == null:
		return
	search.move_requested.emit(Vector2.ZERO, object_id)
	for _frame in range(3):
		await process_frame
	var player: Dictionary = Dictionary(
		persistence.session.active_activity["snapshot"].get("player", {})
	)
	var path: Array = Array(player.get("planned_path", []))
	if path.is_empty():
		_failures.append("no planned path towards %s" % object_id)
		return
	var destination: Array = Array(path.back())
	var screen := shell.current_screen() as SearchScreen
	if screen == null:
		return
	screen.movement_checkpoint.emit(
		Vector2(float(destination[0]), float(destination[1])),
		path.size() - 1,
		true
	)
	for _frame in range(3):
		await process_frame
	await _settle()


func _find_search_action(session: FirstDaySession) -> Dictionary:
	var adapter := SandboxAdapterScript.new(session)
	for raw_action: Variant in Array(adapter.get_location_model().get("actions", [])):
		if raw_action is Dictionary and String(raw_action.get("kind", "")) == "search":
			return Dictionary(raw_action).duplicate(true)
	return {}


func _first_available_option(session: FirstDaySession) -> String:
	var pending: Dictionary = preload(
		"res://game/events/search_encounter_command.gd"
	).pending(session)
	for raw_option: Variant in Array(Dictionary(pending.get("preview", {})).get("options", [])):
		if raw_option is Dictionary and bool(raw_option.get("available", false)):
			return String(raw_option.get("id", ""))
	return ""


func _settle() -> void:
	await create_timer(0.3, true, false, true).timeout


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
	var path := "%s/%s_%dx%d.png" % [OUTPUT_DIR, state_name, test_size.x, test_size.y]
	_require(image.save_png(path) == OK, "could not save %s" % path)
