class_name NpcFlowCoordinator
extends RefCounted

## Owns one recurring-NPC visit. Opening and refreshing are pure reads; only a
## confirmed interaction crosses the command gate, saves, and changes time.

const WeekFacade := preload("res://app/session/week_session_facade.gd")

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _npc_id := ""
var _screen: NpcScreen


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	npc_id: String,
	hooks: Dictionary
) -> void:
	_session = session
	_presenter = presenter
	_preferences = preferences.duplicate(true)
	_hooks = hooks.duplicate()
	_npc_id = npc_id
	_present_initial()


func _present_initial() -> void:
	var model := _model()
	if not bool(model.get("ok", false)):
		_reject_and_leave(model)
		return
	_screen = _presenter.show_npc(
		model,
		_session.get_shell_model(),
		_preferences,
		{"back": _hook("back"), "interaction": _on_interaction_requested}
	)


func _on_interaction_requested(
	npc_id: String,
	interaction_id: String,
	expected_revision: int
) -> void:
	if npc_id != _npc_id:
		_hook("toast").call("Собеседник изменился. Откройте разговор снова.", true)
		_refresh()
		return
	if not bool(_hook("begin_command").call()):
		_refresh()
		return
	var result := (
		_session.give_to_npc(_npc_id, WeekFacade.gift_stack_id(interaction_id), 1)
		if WeekFacade.is_gift_interaction(interaction_id)
		else _session.execute_npc_interaction(_npc_id, interaction_id, expected_revision)
	)
	if not bool(_hook("accept_result").call(result)):
		_refresh()
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var saved: Dictionary = _hook("save").call()
	if _session.get_phase() == "completed":
		_hook("finished").call()
		_hook("release_command").call()
		return
	var outcome := String(result.get("outcome", result.get("note", "")))
	if not _refresh(outcome) and bool(saved.get("ok", false)) and not outcome.is_empty():
		_hook("toast").call(outcome)
	_hook("release_command").call()


func _refresh(outcome: String = "") -> bool:
	var model := _model()
	if not bool(model.get("ok", false)):
		_hook("back").call()
		return false
	if not outcome.is_empty():
		model["outcome"] = outcome
	if _screen == null or not is_instance_valid(_screen):
		_screen = _presenter.show_npc(
			model,
			_session.get_shell_model(),
			_preferences,
			{"back": _hook("back"), "interaction": _on_interaction_requested}
		)
	else:
		_screen.present(model)
	return true


func _model() -> Dictionary:
	return _session.get_npc_model(
		_npc_id,
		bool(_preferences.get("reduced_motion", false))
	)


func _reject_and_leave(result: Dictionary) -> void:
	_hook("accept_result").call(result)
	_hook("back").call()


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing NPC-flow hook: %s" % key)
	return value
