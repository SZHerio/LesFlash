extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")


class MemoryPersistence extends SessionPersistence:
	var save_calls := 0

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> FirstDaySessionAdapter:
		return SandboxAdapter.create(characteristics, 43_303) as FirstDaySessionAdapter

	func save_session(_session: FirstDaySessionAdapter) -> Dictionary:
		save_calls += 1
		return {"ok": true}


class MemoryPreferences extends UiPreferences:
	func load_from_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		reduced_motion = true
		return {"ok": true, "created": true}

	func save_to_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true}


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var persistence := MemoryPersistence.new()
	var shell := AppShellScene.instantiate() as AppShell
	var coordinator := shell.get_node("UiCoordinator") as UiCoordinator
	coordinator.configure(persistence, MemoryPreferences.new())
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	await _frames(6)

	var menu := shell.current_screen() as MainMenuScreen
	_require(menu != null, "main menu did not boot")
	if menu == null:
		_finish()
		return
	menu.new_game_requested.emit()
	await _frames(2)
	var creation := shell.current_screen() as CharacterCreationScreen
	_require(creation != null, "character creation did not open")
	if creation == null:
		_finish()
		return
	creation.character_confirmed.emit({
		"strength": 6,
		"charisma": 4,
		"intelligence": 4,
		"luck": 4,
	})
	await _frames(6)
	await create_timer(0.30, true, false, true).timeout

	var adapter := coordinator.get("_session") as SandboxSessionAdapter
	var command_runner := coordinator.get("_commands") as SessionCommandRunner
	_require(adapter != null and command_runner != null, "sandbox session did not start")
	if adapter == null or command_runner == null:
		_finish()
		return
	var session: FirstDaySession = adapter.get("_session")
	session.location = "recycling_point"
	session.phase = "map"
	coordinator.call("_show_location")
	await _frames(4)

	var location := shell.current_screen() as LocationScreen
	var npc_action := _find_npc_action(adapter.get_location_model(), "npc_viktor_koren")
	_require(location != null and not npc_action.is_empty(), "scheduled Viktor action is missing")
	if location == null or npc_action.is_empty():
		_finish()
		return
	var ui_actions: Dictionary = location.get("_action_models")
	var ui_action: Dictionary = Dictionary(ui_actions.get(npc_action.get("id", ""), {}))
	var payload: Dictionary = Dictionary(Dictionary(ui_action.get("intent", {})).get("payload", {}))
	_require(String(payload.get("npc_id", "")) == "npc_viktor_koren", "typed NPC intent was lost")
	var time_before := int(session.run_state.calendar.elapsed_minutes)
	var revision_before := adapter.get_flow_revision()
	location.action_requested.emit(String(npc_action.get("id", "")), ui_action)
	await _frames(5)

	var npc_screen := shell.current_screen() as NpcScreen
	_require(npc_screen != null, "NPC action did not open NpcScreen")
	_require(String(coordinator.get("_route")) == "npc", "root route did not follow the NPC screen")
	_require(session.run_state.calendar.elapsed_minutes == time_before, "opening NPC screen moved time")
	_require(adapter.get_flow_revision() == revision_before, "opening NPC screen changed flow revision")
	_require(persistence.save_calls == 1, "opening NPC screen wrote an unnecessary save")
	if npc_screen == null:
		_finish()
		return
	var initial_model: Dictionary = npc_screen.get("_model")
	_require(String(initial_model.get("name", "")) == "Мартин Гордеев", "screen received the wrong NPC")
	_require(
		String(initial_model.get("portrait_key", "")).begins_with("npc_viktor_koren"),
		"screen did not receive Viktor's stable portrait key"
	)
	var talk_row := _interaction_row(npc_screen, "npc_interaction_viktor_ask_shift")
	_require(talk_row != null and not talk_row.disabled, "baseline Viktor interaction is unavailable")
	if talk_row == null or talk_row.disabled:
		_finish()
		return
	talk_row.pressed.emit()
	await _frames(7)

	npc_screen = shell.current_screen() as NpcScreen
	_require(npc_screen != null, "successful interaction did not refresh NpcScreen")
	_require(session.run_state.calendar.elapsed_minutes == time_before + 8, "interaction did not spend eight minutes")
	_require(adapter.get_flow_revision() == revision_before + 1, "interaction did not advance revision once")
	_require(persistence.save_calls == 2, "interaction did not save exactly once")
	if npc_screen == null:
		_finish()
		return
	var refreshed_model: Dictionary = npc_screen.get("_model")
	_require(
		int(refreshed_model.get("expected_revision", -1)) == adapter.get_flow_revision(),
		"refreshed screen kept a stale revision"
	)
	_require(
		String(refreshed_model.get("outcome", "")).contains("Мартин"),
		"interaction outcome is not visible on the refreshed screen"
	)
	_require(
		String(refreshed_model.get("relationship_value", "")).contains("Доверие +1"),
		"relationship feedback did not reflect the committed interaction"
	)

	while command_runner.locked():
		await process_frame
	var second_row := _interaction_row(npc_screen, "npc_interaction_viktor_clear_yard")
	_require(second_row != null and not second_row.disabled, "second Viktor interaction is unavailable")
	if second_row == null or second_row.disabled:
		_finish()
		return
	npc_screen.set("_expected_revision", revision_before)
	var before_stale: Dictionary = session.to_dict()
	second_row.pressed.emit()
	await _frames(5)
	npc_screen = shell.current_screen() as NpcScreen
	_require(session.to_dict() == before_stale, "stale NPC intent mutated the session")
	_require(persistence.save_calls == 2, "stale NPC intent triggered a save")
	_require(npc_screen != null and not bool(npc_screen.get("_awaiting_result")), "stale intent left screen pending")
	if npc_screen == null:
		_finish()
		return

	npc_screen.back_requested.emit()
	await _frames(3)
	location = shell.current_screen() as LocationScreen
	_require(location != null, "NPC Back did not return to the location")
	if location == null:
		_finish()
		return
	ui_actions = location.get("_action_models")
	ui_action = Dictionary(ui_actions.get(npc_action.get("id", ""), {}))
	location.action_requested.emit(String(npc_action.get("id", "")), ui_action)
	await _frames(3)
	_require(shell.current_screen() as NpcScreen != null, "NPC screen did not reopen")
	shell.back_requested.emit()
	await _frames(3)
	_require(shell.current_screen() as LocationScreen != null, "system Back did not leave the NPC route")
	_finish()


func _find_npc_action(model: Dictionary, npc_id: String) -> Dictionary:
	for raw_action: Variant in Array(model.get("actions", [])):
		if not raw_action is Dictionary or String(raw_action.get("kind", "")) != "npc":
			continue
		var intent: Dictionary = Dictionary(raw_action.get("intent", {}))
		var payload: Dictionary = Dictionary(intent.get("payload", {}))
		if String(payload.get("npc_id", "")) == npc_id:
			return Dictionary(raw_action).duplicate(true)
	return {}


func _interaction_row(screen: NpcScreen, interaction_id: String) -> ActionRow:
	for child: Node in screen.get_node("%InteractionList").get_children():
		if child is ActionRow and String(child.get("_action_id")) == interaction_id:
			return child as ActionRow
	return null


func _frames(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M3F.3 NPC FLOW SMOKE PASSED")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M3F.3 NPC FLOW: %s" % failure)
	quit(1)
