class_name LocationFlowCoordinator
extends RefCounted

## Presents the stable sandbox location and translates its typed action intent
## into domain commands. The root coordinator retains saving and global routes.

var _session: SandboxSessionAdapter
var _hooks: Dictionary = {}


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	last_transaction: Dictionary,
	animate_status_delta: bool,
	hooks: Dictionary
) -> void:
	_session = session
	_hooks = hooks.duplicate()
	presenter.show_location(
		session.get_shell_model(),
		preferences,
		{"action": _on_action_requested, "settings": _hook("settings")},
		last_transaction,
		animate_status_delta
	)


func _on_action_requested(_action_id: String, action_model: Dictionary) -> void:
	var action_id := String(action_model.get("id", ""))
	match String(action_model.get("kind", "local")):
		"local":
			_hook("run_command").call(_session.perform_location_action.bind(action_id), true)
		"event":
			_hook("run_command").call(_session.enter_event.bind(action_id), false)
		"job":
			_hook("run_command").call(_session.begin_job.bind("standard"), false)
		"wait":
			_hook("run_command").call(_session.wait_until_evening, true)
		"shelter":
			if bool(_hook("begin_command").call()):
				_hook("shelters").call()
				_hook("release_command").call()


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing location-flow hook: %s" % key)
	return value
