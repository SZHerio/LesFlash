class_name InventoryFlowCoordinator
extends RefCounted

const InventoryModels := preload("res://app/inventory/inventory_view_model.gd")

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _screen: InventoryScreen


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	hooks: Dictionary
) -> void:
	_session = session
	_presenter = presenter
	_preferences = preferences.duplicate(true)
	_hooks = hooks.duplicate()
	_screen = _presenter.show_inventory(
		_session.get_inventory_model(),
		_session.get_shell_model(),
		_preferences,
		{
			"action": _on_action_requested,
			"settings": _hook("settings"),
		}
	)
	if _screen != null:
		_screen.replacement_requested.connect(_on_replacement_requested)


func refresh() -> void:
	if _session == null or _screen == null or not is_instance_valid(_screen):
		return
	_screen.present(InventoryModels.build(
		_session.get_inventory_model(),
		_session.get_shell_model(),
		bool(_preferences.get("reduced_motion", false)),
		float(_preferences.get("font_scale", 1.0))
	))


func handle_back() -> bool:
	return (
		_screen != null
		and is_instance_valid(_screen)
		and _screen.handle_back()
	)


func has_modal() -> bool:
	return (
		_screen != null
		and is_instance_valid(_screen)
		and _screen.has_open_sheet()
	)


func _on_action_requested(
	stack_id: String,
	action_id: String,
	quantity: int,
	target_container_id: String
) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result: Dictionary = _session.perform_inventory_action(
		stack_id,
		action_id,
		quantity,
		target_container_id
	)
	if String(result.get("code", "")) == "capacity_conflict":
		if _screen != null and is_instance_valid(_screen):
			_screen.show_capacity_conflict(result)
		_hook("release_command").call()
		return
	_finish_successful_command(result, action_id)


func _on_replacement_requested(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.perform_inventory_replacement(
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	_finish_successful_command(result, "replace")


func _finish_successful_command(result: Dictionary, action_id: String) -> void:
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var save_result: Dictionary = _hook("save").call()
	refresh()
	if bool(save_result.get("ok", false)) and action_id != "select":
		_hook("toast").call(_outcome(action_id))
	_hook("release_command").call()


func _outcome(action_id: String) -> String:
	match action_id:
		"select":
			return "Предмет выбран."
		"move":
			return "Вещь переложена."
		"pick_up":
			return "Находка теперь у героя."
		"replace":
			return "Вещи заменены: находка взята, выбранный предмет оставлен здесь."
		"use":
			return "Предмет использован."
		"disassemble":
			return "Предмет разобран."
		"drop":
			return "Вещь оставлена в этом месте."
		"sell":
			return "Вторсырьё принято. Выплата добавлена к деньгам героя."
		_:
			return "Инвентарь обновлён."


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing inventory-flow hook: %s" % key)
	return value
