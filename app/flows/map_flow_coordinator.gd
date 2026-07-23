class_name MapFlowCoordinator
extends RefCounted

## Owns the M3B map flow without turning the root UI coordinator into a
## gameplay manager. Route inspection remains presentation-only. A confirmed
## trip commits and saves first; only then is the calculated route animated.

var _session: SandboxSessionAdapter
var _screen: CityMapScreen
var _hooks: Dictionary = {}


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	hooks: Dictionary
) -> void:
	_session = session
	_hooks = hooks.duplicate()
	_screen = presenter.show_city_map(
		session.get_city_map_model(),
		session.get_shell_model(),
		preferences,
		{
			"travel": _on_travel_requested,
			"back": _hook("back"),
		}
	)


func _on_travel_requested(destination_id: String, mode_id: String) -> void:
	if _session == null or _screen == null:
		return
	var begin_command := _hook("begin_command")
	if not bool(begin_command.call()):
		return

	var result: Dictionary = _session.travel(destination_id, mode_id)
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return

	var save_result: Dictionary = _hook("save").call()
	if not bool(save_result.get("ok", false)):
		_hook("capture_transaction").call(result)
		var direct_arrival := result.duplicate(true)
		direct_arrival["show_travel_toast"] = false
		_hook("arrived").call(direct_arrival)
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var origin := String(result.get("from", ""))
	var destination := String(result.get("to", destination_id))
	_screen.animate_travel(origin, destination)
	await _screen.travel_animation_finished
	_hook("arrived").call(result)
	_hook("release_command").call()


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing map-flow hook: %s" % key)
	return value
