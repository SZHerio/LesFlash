extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
class SpyPersistence extends SessionPersistence:
	const Adapter := preload("res://app/session/sandbox_session_adapter.gd")

	var create_calls := 0
	var save_calls := 0
	var fail_save := false

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, seed: int) -> RunSessionAdapter:
		create_calls += 1
		return Adapter.create(characteristics, seed) as RunSessionAdapter

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found", "error": "No save exists."}

	func save_session(_session: RunSessionAdapter) -> Dictionary:
		save_calls += 1
		if fail_save:
			return {"ok": false, "code": "temporary_write_failed", "error": "Could not write save."}
		return {"ok": true}


class MemoryPreferences extends UiPreferences:
	func load_from_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true, "created": true}

	func save_to_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	root.add_child(viewport)
	var shell := AppShellScene.instantiate() as AppShell
	var coordinator := shell.get_node("UiCoordinator") as UiCoordinator
	var persistence := SpyPersistence.new()
	coordinator.configure(persistence, MemoryPreferences.new())
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	for _frame in range(5):
		await process_frame

	var menu := shell.current_screen() as MainMenuScreen
	if menu == null:
		_fail("main menu did not boot")
		return
	shell.pause_requested.emit()
	shell.autosave_requested.emit()
	if persistence.save_calls != 0:
		_fail("menu lifecycle attempted to save a missing session")
		return
	menu.new_game_requested.emit()
	await process_frame
	var creation := shell.current_screen() as CharacterCreationScreen
	if creation == null:
		_fail("character creation did not open")
		return
	creation.character_confirmed.emit({
		"strength": 10,
		"charisma": 6,
		"intelligence": 1,
		"luck": 1,
	})
	if persistence.create_calls != 1 or persistence.save_calls != 1:
		_fail("new session was not created and saved exactly once")
		return

	var adapter := coordinator.get("_session") as SandboxSessionAdapter
	var command_runner := coordinator.get("_commands") as SessionCommandRunner
	var location_screen := shell.current_screen() as LocationScreen
	if adapter == null or command_runner == null or location_screen == null:
		_fail("new session did not route directly to its location")
		return
	if adapter.get_phase() != "map" or not adapter.get_current_event_model().is_empty():
		_fail("location-first start still contains a mandatory event")
		return
	var action := _first_available_local_action(adapter.get_location_model())
	if action.is_empty():
		_fail("starting location has no available ordinary action: %s" % str(adapter.get_location_model()))
		return
	var revision_before := adapter.get_flow_revision()
	await create_timer(0.10, true, false, true).timeout
	location_screen.action_requested.emit(String(action.get("id", "")), action)
	if adapter.get_flow_revision() != revision_before or persistence.save_calls != 1:
		_fail(
			"a second tap crossed the screen transition gate (revision %d→%d, saves=%d, locked=%s)"
			% [revision_before, adapter.get_flow_revision(), persistence.save_calls, command_runner.in_flight()]
		)
		return

	await create_timer(0.30, true, false, true).timeout
	location_screen.action_requested.emit(String(action.get("id", "")), action)
	if adapter.get_flow_revision() <= revision_before or persistence.save_calls != 2:
		_fail("the transition gate did not release for the next deliberate action")
		return

	while command_runner.locked():
		await process_frame
	persistence.fail_save = true
	command_runner.run(
		func() -> Dictionary:
			return {"ok": true, "outcome": "SAVE_FAILURE_OUTCOME"},
		true,
		adapter,
		Callable(coordinator, "_route_session")
	)
	await process_frame
	var toast_label := shell.get_node(
		"SafeArea/ToastOverlay/Position/ToastPanel/Margin/ToastLabel"
	) as Label
	if (
		persistence.save_calls != 3
		or toast_label == null
		or "SAVE_FAILURE_OUTCOME" in toast_label.text
	):
		_fail("successful outcome hid the save failure warning")
		return
	persistence.fail_save = false
	while command_runner.locked():
		await process_frame
	var time_before_map := int(adapter.get_city_map_model().get("calendar", {}).get("elapsed_minutes", -1))
	var revision_before_map := adapter.get_flow_revision()
	shell.navigation_requested.emit("map")
	await process_frame
	var map_screen := shell.current_screen() as CityMapScreen
	if map_screen == null:
		_fail("map tab did not open the city map")
		return
	if (
		int(adapter.get_city_map_model().get("calendar", {}).get("elapsed_minutes", -1)) != time_before_map
		or adapter.get_flow_revision() != revision_before_map
	):
		_fail("opening the map changed gameplay time or revision")
		return
	var route := _first_available_route(adapter.get_city_map_model())
	if route.is_empty():
		_fail("city map has no available route")
		return
	map_screen.travel_requested.emit(
		String(route.get("destination_id", "")),
		String(route.get("mode", "walk"))
	)
	var revision_after_travel := adapter.get_flow_revision()
	var time_after_travel := int(adapter.get_city_map_model().get("calendar", {}).get("elapsed_minutes", -1))
	if (
		revision_after_travel != revision_before_map + 1
		or time_after_travel - time_before_map != int(route.get("minutes", 0))
		or persistence.save_calls != 5
	):
		_fail("confirmed travel did not commit and save exactly once before animation")
		return
	shell.back_requested.emit()
	if shell.current_screen() != map_screen:
		_fail("system Back destroyed the map during a committed travel animation")
		return
	map_screen.travel_requested.emit(
		String(route.get("destination_id", "")),
		String(route.get("mode", "walk"))
	)
	if adapter.get_flow_revision() != revision_after_travel or persistence.save_calls != 5:
		_fail("travel input lock allowed a duplicate domain command")
		return
	var animation_deadline := Time.get_ticks_msec() + 3000
	while shell.current_screen() == map_screen and Time.get_ticks_msec() < animation_deadline:
		await process_frame
	if shell.current_screen() as LocationScreen == null:
		_fail("completed route animation did not return to the destination location")
		return

	while command_runner.locked():
		await process_frame
	shell.navigation_requested.emit("map")
	await process_frame
	map_screen = shell.current_screen() as CityMapScreen
	if map_screen == null:
		_fail("map did not reopen for failed-save travel regression")
		return
	route = _first_available_route(adapter.get_city_map_model())
	if route.is_empty():
		_fail("destination has no route for failed-save travel regression")
		return
	var location_before_failed_travel := adapter.get_location_id()
	var revision_before_failed_travel := adapter.get_flow_revision()
	var time_before_failed_travel := int(
		adapter.get_city_map_model().get("calendar", {}).get("elapsed_minutes", -1)
	)
	persistence.fail_save = true
	map_screen.travel_requested.emit(
		String(route.get("destination_id", "")),
		String(route.get("mode", "walk"))
	)
	await process_frame
	if persistence.save_calls != 6:
		_fail("failed travel did not attempt exactly one save")
		return
	if (
		adapter.get_location_id() == location_before_failed_travel
		or adapter.get_flow_revision() != revision_before_failed_travel + 1
		or int(adapter.get_city_map_model().get("calendar", {}).get("elapsed_minutes", -1))
			- time_before_failed_travel != int(route.get("minutes", 0))
	):
		_fail("failed save discarded or duplicated the already committed travel")
		return
	if shell.current_screen() as LocationScreen == null:
		_fail("failed travel save did not show the committed destination immediately")
		return
	while command_runner.locked():
		await process_frame
	shell.navigation_requested.emit("map")
	await process_frame
	map_screen = shell.current_screen() as CityMapScreen
	if map_screen == null:
		_fail("map did not open for save-barrier regression")
		return
	route = _first_available_route(adapter.get_city_map_model())
	if route.is_empty():
		_fail("destination has no route for save-barrier regression")
		return
	var revision_before_barrier := adapter.get_flow_revision()
	map_screen.travel_requested.emit(
		String(route.get("destination_id", "")),
		String(route.get("mode", "walk"))
	)
	await process_frame
	if persistence.save_calls != 7 or adapter.get_flow_revision() != revision_before_barrier:
		_fail(
			"save barrier allowed a new command before durability recovery (saves=%d, revision=%d->%d, in_flight=%s, unlock_delta=%d)"
			% [
				persistence.save_calls,
				revision_before_barrier,
				adapter.get_flow_revision(),
				command_runner.in_flight(),
				command_runner.unlock_remaining_msec(),
			]
		)
		return
	shell.back_requested.emit()
	await process_frame
	location_screen = shell.current_screen() as LocationScreen
	if location_screen == null:
		_fail("save-barrier regression could not return to the location")
		return
	location_screen.settings_requested.emit()
	await process_frame
	var settings_screen := shell.current_screen() as SettingsScreen
	if settings_screen == null:
		_fail("settings did not open during save-barrier regression")
		return
	var revision_before_blocked_preference := adapter.get_flow_revision()
	settings_screen.preference_changed.emit("show_locked_options", true)
	await process_frame
	if (
		persistence.save_calls != 8
		or adapter.get_flow_revision() != revision_before_blocked_preference
	):
		_fail("a preference mutated the session before durability recovery")
		return
	persistence.fail_save = false
	settings_screen.preference_changed.emit("show_locked_options", true)
	await process_frame
	if (
		persistence.save_calls != 10
		or adapter.get_flow_revision() != revision_before_blocked_preference + 1
	):
		_fail("a preference did not save after durability recovery")
		return
	settings_screen.back_requested.emit()
	await process_frame
	shell.navigation_requested.emit("map")
	await process_frame
	map_screen = shell.current_screen() as CityMapScreen
	if map_screen == null:
		_fail("map did not reopen after preference recovery")
		return
	route = _first_available_route(adapter.get_city_map_model())
	if route.is_empty():
		_fail("recovered location has no route")
		return
	var revision_before_recovered_command := adapter.get_flow_revision()
	map_screen.travel_requested.emit(
		String(route.get("destination_id", "")),
		String(route.get("mode", "walk"))
	)
	await process_frame
	if (
		persistence.save_calls != 11
		or adapter.get_flow_revision() != revision_before_recovered_command + 1
	):
		_fail("recovered save barrier did not release exactly one deliberate command")
		return
	await create_timer(0.85, true, false, true).timeout

	shell.pause_requested.emit()
	shell.autosave_requested.emit()
	if persistence.save_calls != 13:
		_fail("pause and autosave did not trigger exactly one save each")
		return
	persistence.fail_save = true
	var session_before_failure: Variant = coordinator.get("_session")
	shell.pause_requested.emit()
	if persistence.save_calls != 14 or coordinator.get("_session") != session_before_failure:
		_fail("a failed lifecycle save changed or discarded the active session")
		return

	print("UI COORDINATOR FLOW TEST PASSED: debounce, pause, autosave and failed-save safety")
	quit(0)


func _first_available_local_action(model: Dictionary) -> Dictionary:
	for raw_action in Array(model.get("actions", [])):
		if (
			raw_action is Dictionary
			and String(raw_action.get("kind", "")) == "local"
			and bool(raw_action.get("available", false))
		):
			return Dictionary(raw_action).duplicate(true)
	return {}


func _first_available_route(model: Dictionary) -> Dictionary:
	for raw_route in Array(model.get("routes", [])):
		if raw_route is Dictionary and bool(raw_route.get("available", false)):
			return Dictionary(raw_route).duplicate(true)
	return {}


func _fail(message: String) -> void:
	push_error("UI COORDINATOR FLOW FAILED: %s" % message)
	quit(1)
