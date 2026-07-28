class_name LocationFlowCoordinator
extends RefCounted

## Presents the stable sandbox location and translates its typed action intent
## into domain commands. The root coordinator retains saving and global routes.

const NpcFlowScript := preload("res://app/flows/npc_flow_coordinator.gd")
const JobShiftFlowScript := preload("res://app/flows/job_shift_flow_coordinator.gd")

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _npc_flow: NpcFlowCoordinator = NpcFlowScript.new()
var _job_shift_flow: JobShiftFlowCoordinator = JobShiftFlowScript.new()


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	last_transaction: Dictionary,
	animate_status_delta: bool,
	hooks: Dictionary
) -> void:
	_session = session
	_presenter = presenter
	_preferences = preferences.duplicate(true)
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
		"search":
			_hook("run_command").call(_session.begin_search, false)
		"store":
			var intent: Dictionary = Dictionary(action_model.get("intent", {}))
			var payload: Dictionary = Dictionary(intent.get("payload", {}))
			_hook("store").call(String(payload.get("store_id", "")))
		"npc":
			_show_npc(action_model)
		"job_shift":
			_show_job_shift()
		"recycling":
			_hook("recycling").call()
		"wait":
			_hook("run_command").call(_session.wait_until_evening, true)
		"shelter":
			if bool(_hook("begin_command").call()):
				_hook("shelters").call()
				_hook("release_command").call()


func _show_job_shift() -> void:
	var shift_hooks := _hooks.duplicate()
	shift_hooks["back"] = _hook("location")
	_hook("job_shift_opened").call()
	_job_shift_flow.show(_session, _presenter, _preferences, shift_hooks)


func _show_npc(action_model: Dictionary) -> void:
	var intent: Dictionary = Dictionary(action_model.get("intent", {}))
	var payload: Dictionary = Dictionary(intent.get("payload", {}))
	var npc_hooks := _hooks.duplicate()
	npc_hooks["back"] = _hook("location")
	_hook("npc_opened").call()
	_npc_flow.show(
		_session,
		_presenter,
		_preferences,
		String(payload.get("npc_id", "")),
		npc_hooks
	)


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing location-flow hook: %s" % key)
	return value
