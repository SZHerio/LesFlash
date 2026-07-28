extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")
const LegacySession := preload("res://game/run/run_session.gd")
const SandboxAdapterScript := preload("res://app/session/sandbox_session_adapter.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")


class MemoryPersistence extends SessionPersistence:
	var session: RunSession
	var saves := 0

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> RunSessionAdapter:
		session = LegacySession.create_location_first(characteristics, 72_311)
		session.run_state.add_item("cardboard_sheet", 1, "pockets")
		session.run_state.add_item("recyclables", 1, "pockets")
		session.run_state.inventory = InventoryStateScript.ensure_external_container(
			session.run_state.inventory,
			"ground:%s" % session.location,
			"На земле"
		)
		var addition := InventoryStateScript.add_item(
			session.run_state.inventory,
			"plastic_bottle",
			1,
			100,
			"ground:%s" % session.location,
			session.run_state.get_characteristic("strength")
		)
		if bool(addition.get("ok", false)):
			session.run_state.inventory = addition["inventory"]
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
	await _frames(5)
	(shell.current_screen() as MainMenuScreen).new_game_requested.emit()
	await process_frame
	(shell.current_screen() as CharacterCreationScreen).character_confirmed.emit({
		"strength": 6,
		"charisma": 4,
		"intelligence": 5,
		"luck": 3,
	})
	await _frames(5)
	await create_timer(0.28, true, false, true).timeout
	shell.navigation_requested.emit("items")
	await _frames(4)

	var screen := shell.current_screen() as InventoryScreen
	_require(screen != null, "inventory route did not open")
	if screen != null:
		await _exercise_pickup(shell, screen, persistence)

	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame
	if _failures.is_empty():
		print("M3C INVENTORY RECOVERY SMOKE PASSED: pickup, conflict, replacement, modal Back/nav")
		quit(0)
		return
	for failure in _failures:
		push_error("M3C INVENTORY RECOVERY: %s" % failure)
	quit(1)


func _exercise_pickup(
	shell: AppShell,
	screen: InventoryScreen,
	persistence: MemoryPersistence
) -> void:
	var original_instance := screen.get_instance_id()
	var external := _card_with_action(screen, "Забрать")
	_require(external != null, "external item has no «Забрать» action")
	if external == null:
		return
	var saves_before := persistence.saves
	(_action_button(external, "Забрать") as Button).pressed.emit()
	var sheet := screen.get_node("%ActionSheet") as InventoryActionSheet
	_require(sheet.visible, "pickup confirmation did not open")
	(sheet.get_node("%ConfirmButton") as Button).pressed.emit()
	await _frames(3)
	_require(persistence.saves == saves_before, "failed capacity preview unexpectedly saved")
	_require(sheet.visible, "capacity conflict did not replace confirmation with recovery")
	_require(
		(sheet.get_node("%ReplacementPicker") as OptionButton).item_count == 2,
		"capacity conflict omitted carried comparison"
	)
	_require(
		"Доступно:" in (sheet.get_node("%RecoveriesLabel") as Label).text,
		"capacity conflict omitted recoveries"
	)

	await create_timer(0.28, true, false, true).timeout
	(sheet.get_node("%ConfirmButton") as Button).pressed.emit()
	await _frames(5)
	await create_timer(0.28, true, false, true).timeout
	screen = shell.current_screen() as InventoryScreen
	_require(screen != null and screen.get_instance_id() == original_instance, "item action recreated InventoryScreen")
	_require(persistence.saves == saves_before + 1, "replacement did not save exactly once")
	_require(persistence.session.run_state.get_item_count("plastic_bottle") == 1, "incoming item was not carried")
	var external_cardboard := _external_stack(persistence.session, "cardboard_sheet")
	_require(not external_cardboard.is_empty(), "displaced item was not left at the source")

	var displaced_card := _card_with_action(screen, "Забрать")
	_require(displaced_card != null, "displaced external item is not recoverable")
	if displaced_card == null:
		return
	(_action_button(displaced_card, "Забрать") as Button).pressed.emit()
	await process_frame
	_require(screen.has_open_sheet(), "second pickup sheet did not open")
	shell.navigation_requested.emit("map")
	await _frames(2)
	_require(shell.current_screen() == screen, "bottom navigation bypassed the modal sheet")
	shell.back_requested.emit()
	await _frames(2)
	_require(shell.current_screen() == screen and not screen.has_open_sheet(), "Back did not close sheet first")
	shell.back_requested.emit()
	await _frames(3)
	_require(shell.current_screen() is LocationScreen, "second Back did not return to location")


func _card_with_action(screen: InventoryScreen, title: String) -> InventoryItemCard:
	for child in screen.get_node("%ItemsList").get_children():
		var card := child as InventoryItemCard
		if card != null and _action_button(card, title) != null:
			return card
	return null


func _action_button(card: InventoryItemCard, title: String) -> Button:
	for child in card.get_node("%Actions").get_children():
		var button := child as Button
		if button != null and button.text == title:
			return button
	return null


func _external_stack(session: RunSession, item_id: String) -> Dictionary:
	for stack in InventoryStateScript.all_stacks(session.run_state.inventory):
		if bool(stack.get("external", false)) and String(stack.get("item_id", "")) == item_id:
			return stack
	return {}


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
