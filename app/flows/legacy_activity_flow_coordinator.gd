class_name LegacyActivityFlowCoordinator
extends RefCounted

## Temporary bridge for the verified M2 event/job/shelter screens. M3F removes
## this flow together with the legacy UI once seven-day sandbox parity exists.

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}


func configure(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	hooks: Dictionary
) -> void:
	_session = session
	_presenter = presenter
	_preferences = preferences.duplicate(true)
	_hooks = hooks.duplicate()


func show_event() -> void:
	_presenter.show_event(
		_session.get_current_event_model(),
		_session.get_shell_model(),
		_preferences,
		{"action": _on_event_choice, "settings": _hook("settings")}
	)


func show_job() -> void:
	_presenter.show_job(
		_session.current_job_prompt(),
		_session.get_shell_model(),
		_preferences,
		{"action": _on_job_answer, "settings": _hook("settings")}
	)


func show_shelters() -> void:
	_presenter.show_shelters(
		_session.available_shelters(),
		_session.get_shell_model(),
		_preferences,
		{"action": _on_shelter_selected, "settings": _hook("settings")}
	)


func show_job_result() -> void:
	_presenter.show_job_result(
		_session.get_job_result_model(),
		_session.get_shell_model(),
		_preferences,
		_hook("location")
	)


func show_summary() -> void:
	_presenter.show_summary(
		_session.get_summary_model(),
		_session.get_shell_model(),
		_preferences,
		_hook("leave")
	)


func _on_event_choice(choice_id: String) -> void:
	_hook("run_command").call(_session.resolve_choice.bind(choice_id), true)


func _on_job_answer(choice_id: String) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result: Dictionary = _session.answer_job(choice_id)
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var save_result: Dictionary = _hook("save").call()
	if bool(result.get("completed", false)):
		_hook("job_result").call()
	else:
		show_job()
		if bool(save_result.get("ok", false)):
			_hook("toast").call("Результат раунда: +%d" % int(result.get("round_score", 0)))
	_hook("release_command").call()


func _on_shelter_selected(shelter_id: String) -> void:
	_hook("run_command").call(_session.choose_shelter.bind(shelter_id))


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing legacy-activity hook: %s" % key)
	return value
