extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")


class MemoryPersistence extends SessionPersistence:
	var save_calls := 0

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> RunSessionAdapter:
		return SandboxAdapter.create(characteristics, 4_202) as RunSessionAdapter

	func save_session(_session: RunSessionAdapter) -> Dictionary:
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
		"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5,
	})
	await _frames(6)
	await create_timer(0.30, true, false, true).timeout
	var adapter := coordinator.get("_session") as SandboxSessionAdapter
	_require(adapter != null, "sandbox session was not created")
	if adapter == null:
		_finish()
		return
	var session: RunSession = adapter.get("_session")
	session.location = "clinic_yard"
	session.phase = "map"
	session.run_state.set_money(1_000)
	coordinator.call("_show_location")
	await _frames(4)
	var location := shell.current_screen() as LocationScreen
	var store_action := _find_kind(adapter.get_location_model(), "store")
	_require(location != null and not store_action.is_empty(), "clinic store action is missing")
	if location == null or store_action.is_empty():
		_finish()
		return
	var ui_actions: Dictionary = location.get("_action_models")
	var ui_action: Dictionary = Dictionary(ui_actions.get(store_action.get("id", ""), {}))
	_require(not Dictionary(ui_action.get("intent", {})).is_empty(), "typed store intent was lost in presentation")
	var time_before := session.run_state.calendar.elapsed_minutes
	location.action_requested.emit(String(store_action.get("id", "")), ui_action)
	await _frames(5)
	var shop := shell.current_screen() as ShopScreen
	_require(shop != null, "store action did not open ShopScreen")
	_require(session.run_state.calendar.elapsed_minutes == time_before, "opening shop moved gameplay time")
	if shop != null:
		var rows := shop.get_node("%OfferList").get_children()
		_require(not rows.is_empty(), "open pharmacy rendered no offers")
		if not rows.is_empty():
			var first := rows[0] as ShopOfferRow
			(first.get_node("%BuyButton") as Button).pressed.emit()
			await _frames(6)
			_require(session.run_state.calendar.elapsed_minutes == time_before + 5, "purchase did not spend five minutes")
			_require(persistence.save_calls == 2, "new run and purchase must each save once")
			_require(shell.current_screen() as ShopScreen != null, "shop did not refresh after purchase")
	if shell.current_screen() as ShopScreen != null:
		(shell.current_screen() as ShopScreen).back_requested.emit()
		await _frames(2)
		_require(shell.current_screen() as LocationScreen != null, "shop Back did not return to location")
	_finish()


func _find_kind(model: Dictionary, kind: String) -> Dictionary:
	for raw_action: Variant in Array(model.get("actions", [])):
		if raw_action is Dictionary and String(raw_action.get("kind", "")) == kind:
			return Dictionary(raw_action).duplicate(true)
	return {}


func _frames(count: int) -> void:
	for _frame: int in count:
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M3F.2 SHOP FLOW SMOKE PASSED")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M3F.2 SHOP FLOW: %s" % failure)
	quit(1)
