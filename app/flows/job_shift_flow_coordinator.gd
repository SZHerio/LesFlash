class_name JobShiftFlowCoordinator
extends RefCounted

## Owns one sorting shift from the briefing to the pay.
##
## Opening and refreshing are pure reads. Only a confirmed step crosses the
## command gate, and every one of them saves: a shift is six hours long, so a
## run interrupted in the middle must resume where the hero actually stood
## rather than back at the briefing.

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _screen: JobScreen


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
	if not _session.is_job_shift_active():
		if not bool(_hook("begin_command").call()):
			return
		var started := _session.begin_job_shift()
		if not bool(_hook("accept_result").call(started)):
			_hook("release_command").call()
			_hook("back").call()
			return
		_hook("capture_transaction").call(started)
		_hook("save").call()
		_hook("release_command").call()
	_present()


func _present() -> void:
	_screen = _presenter.show_job_shift(
		_model(),
		_session.get_shell_model(),
		_preferences,
		{
			"back": _hook("back"),
			"choice": _on_choice_requested,
			"quick_resolve": _on_quick_resolve_requested,
			"finish": _hook("back"),
		}
	)


func _on_quick_resolve_requested() -> void:
	_run_step(func() -> Dictionary: return _session.quick_resolve_job_shift())


func _on_choice_requested(choice_id: String) -> void:
	_run_step(func() -> Dictionary: return _session.resolve_job_shift_step(choice_id))


func _run_step(command: Callable) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result: Dictionary = command.call()
	if not bool(_hook("accept_result").call(result)):
		_refresh()
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var saved: Dictionary = _hook("save").call()
	# Deprivation can end a run in the middle of a shift, and the terminal
	# screen has to win over the shift the hero will never finish.
	if _session.get_phase() == "completed":
		_hook("finished").call()
		_hook("release_command").call()
		return
	_refresh()
	if bool(result.get("completed", false)) and bool(saved.get("ok", false)):
		var grade := String(Dictionary(result.get("result", {})).get("grade", ""))
		if bool(result.get("dismissed", false)):
			_hook("toast").call("Виктор больше не ставит вас в смену.", true)
		elif grade == "unsafe":
			_hook("toast").call("Виктор молча смотрит, как вы уходите.", true)
	_hook("release_command").call()


func _refresh() -> void:
	if _screen == null or not is_instance_valid(_screen):
		_present()
		return
	_screen.present(_model())


func _model() -> Dictionary:
	return _session.get_job_shift_model(bool(_preferences.get("reduced_motion", false)))


func handle_back() -> bool:
	return false


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing job-shift hook: %s" % key)
	return value
