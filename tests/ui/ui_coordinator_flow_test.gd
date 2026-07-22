extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
class SpyPersistence extends SessionPersistence:
	const Adapter := preload("res://app/session/first_day_session_adapter.gd")

	var create_calls := 0
	var save_calls := 0
	var fail_save := false

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, seed: int) -> FirstDaySessionAdapter:
		create_calls += 1
		return Adapter.create(characteristics, seed) as FirstDaySessionAdapter

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found", "error": "No save exists."}

	func save_session(_session: FirstDaySessionAdapter) -> Dictionary:
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

	var adapter := coordinator.get("_session") as FirstDaySessionAdapter
	var choice_screen := shell.current_screen() as ChoiceScreen
	if adapter == null or choice_screen == null:
		_fail("new session did not route to its opening choice")
		return
	var choice_id := _first_available_choice(adapter.get_current_event_model())
	if choice_id.is_empty():
		_fail("opening choice has no available option")
		return
	var revision_before := adapter.get_flow_revision()
	await create_timer(0.10, true, false, true).timeout
	choice_screen.action_requested.emit(choice_id)
	if adapter.get_flow_revision() != revision_before or persistence.save_calls != 1:
		_fail(
			"a second tap crossed the screen transition gate (revision %d→%d, saves=%d, locked=%s)"
			% [revision_before, adapter.get_flow_revision(), persistence.save_calls, coordinator.get("_command_in_flight")]
		)
		return

	await create_timer(0.30, true, false, true).timeout
	choice_screen.action_requested.emit(choice_id)
	if adapter.get_flow_revision() <= revision_before or persistence.save_calls != 2:
		_fail("the transition gate did not release for the next deliberate action")
		return

	shell.pause_requested.emit()
	shell.autosave_requested.emit()
	if persistence.save_calls != 4:
		_fail("pause and autosave did not trigger exactly one save each")
		return
	persistence.fail_save = true
	var session_before_failure: Variant = coordinator.get("_session")
	shell.pause_requested.emit()
	if persistence.save_calls != 5 or coordinator.get("_session") != session_before_failure:
		_fail("a failed lifecycle save changed or discarded the active session")
		return

	print("UI COORDINATOR FLOW TEST PASSED: debounce, pause, autosave and failed-save safety")
	quit(0)


func _first_available_choice(model: Dictionary) -> String:
	for raw_option in Array(model.get("options", [])):
		if raw_option is Dictionary and not bool(raw_option.get("locked", false)):
			return String(raw_option.get("id", ""))
	return ""


func _fail(message: String) -> void:
	push_error("UI COORDINATOR FLOW FAILED: %s" % message)
	quit(1)
