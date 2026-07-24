class_name SearchFlowCoordinator
extends RefCounted

## Drives the search mini-game and the encounter it can raise.
##
## Walking is free and never saves; only a confirmed decision commits, saves and
## reports its outcome. When the zone raises an encounter the coordinator hands
## the screen over to it, because an unanswered encounter must be impossible to
## overlook — but leaving the zone stays available at all times.

const ItemCatalog := preload("res://core/inventory/item_catalog.gd")

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _screen: SearchScreen
var _showing_encounter := false
var _conflict_container_id := ""


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
	_present_current()


func has_modal() -> bool:
	return (
		not _showing_encounter
		and _screen != null
		and is_instance_valid(_screen)
		and _screen.has_open_modal()
	)


## Back closes an open sheet first. Otherwise it leaves the zone, including
## while an encounter waits: a pending answer must never trap the player.
func handle_back() -> bool:
	if has_modal():
		return _screen.handle_back()
	_leave_zone()
	return true


func _present_current() -> void:
	var encounter: Dictionary = _session.get_encounter_model()
	if bool(encounter.get("active", false)):
		_show_encounter(encounter)
		return
	_show_search()


func _show_search() -> void:
	_showing_encounter = false
	_screen = _presenter.show_search(
		_session.get_search_model(),
		_session.get_shell_model(),
		_preferences,
		{
			"move": _on_move,
			"checkpoint": _on_checkpoint,
			"interact": _on_interact,
			"pick_up": _on_pick_up,
			"replace": _on_replace,
			"recover": _on_recover,
			"quick_search": _on_quick_search,
			"finish": _on_finish,
		}
	)


func _show_encounter(encounter: Dictionary) -> void:
	_showing_encounter = true
	_screen = null
	_presenter.show_encounter(
		Dictionary(encounter.get("preview", {})),
		_session.get_shell_model(),
		_preferences,
		{"action": _on_encounter_answer, "settings": _hook("settings")}
	)


func _refresh() -> void:
	if _screen == null or not is_instance_valid(_screen):
		_present_current()
		return
	_screen.present(_presenter.build_search_model(
		_session.get_search_model(),
		_session.get_shell_model(),
		_preferences
	))


func _on_move(target: Vector2, focus_object_id: String) -> void:
	var destination: Variant = focus_object_id if not focus_object_id.is_empty() else target
	var result := _session.plan_search_move(destination)
	if not bool(result.get("ok", false)):
		return
	var path: Array = Array(Dictionary(result.get("path", {})).get("points", []))
	if _screen != null and is_instance_valid(_screen) and not path.is_empty():
		_screen.animate_path(path, focus_object_id)


func _on_checkpoint(position: Vector2, path_index: int, completed: bool) -> void:
	# Intermediate points are pure animation. Only the arrival is worth storing,
	# and neither costs game time.
	if not completed:
		return
	if bool(_session.checkpoint_search_move(position, path_index).get("ok", false)):
		_refresh()


func _on_interact(object_id: String, approach_id: String) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.confirm_search_interaction(object_id, approach_id)
	_finish_command(result, _loot_message(result))


func _on_pick_up(stack_id: String, target_container_id: String) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.pick_up_search_loot(stack_id, target_container_id)
	if String(result.get("code", "")) == "capacity_conflict":
		_open_conflict(result)
		return
	_finish_command(result, "Находка теперь у героя.")


func _on_replace(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.replace_search_loot(
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	_finish_command(
		result,
		"Находка взята, выбранная вещь осталась здесь."
	)


func _on_recover(incoming_stack_id: String, recovery_id: String) -> void:
	match recovery_id:
		"leave_at_source":
			_refresh()
			_hook("toast").call("Находка осталась лежать в зоне.")
		"choose_other_container":
			var next_container := _session.suggest_loot_container(
				incoming_stack_id,
				_conflict_container_id
			)
			if next_container.is_empty():
				_hook("toast").call(
					"Свободного места нет ни в карманах, ни в руках.",
					true
				)
				return
			_on_pick_up(incoming_stack_id, next_container)
		_:
			_refresh()


func _on_quick_search() -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.run_quick_search()
	var resolved := Array(result.get("resolved_object_ids", [])).size()
	_finish_command(
		result,
		"Быстрый поиск: осмотрено объектов — %d." % resolved
	)


func _on_finish() -> void:
	_leave_zone()


func _on_encounter_answer(option_id: String) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.resolve_encounter(option_id)
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var save_result: Dictionary = _hook("save").call()
	_present_current()
	var outcome := String(result.get("outcome", ""))
	if bool(save_result.get("ok", false)) and not outcome.is_empty():
		_hook("toast").call(outcome)
	_hook("release_command").call()


func _leave_zone() -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.finish_search()
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("save").call()
	_hook("location").call()
	_hook("release_command").call()


func _finish_command(result: Dictionary, outcome: String) -> void:
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var save_result: Dictionary = _hook("save").call()
	var encounter: Dictionary = Dictionary(result.get("encounter", {}))
	if not encounter.is_empty():
		_present_current()
		_hook("release_command").call()
		return
	_refresh()
	if bool(save_result.get("ok", false)) and not outcome.is_empty():
		_hook("toast").call(outcome)
	_hook("release_command").call()


func _open_conflict(result: Dictionary) -> void:
	_conflict_container_id = String(result.get("container_id", ""))
	if _screen != null and is_instance_valid(_screen):
		_screen.show_capacity_conflict(result)
	_hook("release_command").call()


## Several stacks of one item read as one find, so the message says "×3" instead
## of naming the same thing three times.
func _loot_message(result: Dictionary) -> String:
	var found: Array = Array(result.get("ground_items", []))
	if found.is_empty():
		return "Здесь ничего полезного не нашлось."
	var totals: Dictionary = {}
	var order: Array = []
	for raw_entry: Variant in found:
		if not raw_entry is Dictionary:
			continue
		var item_id := String(raw_entry.get("item_id", ""))
		if item_id.is_empty():
			continue
		if not totals.has(item_id):
			order.append(item_id)
		totals[item_id] = int(totals.get(item_id, 0)) + maxi(
			int(raw_entry.get("quantity", 1)),
			1
		)
	var parts := PackedStringArray()
	for item_id: Variant in order:
		var definition: Variant = ItemCatalog.definition(String(item_id))
		var quantity := int(totals[item_id])
		parts.append(
			definition.title() if quantity <= 1 else "%s ×%d" % [definition.title(), quantity]
		)
	return "Найдено: %s." % ", ".join(parts)


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing search-flow hook: %s" % key)
	return value
