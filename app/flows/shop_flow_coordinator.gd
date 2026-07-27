class_name ShopFlowCoordinator
extends RefCounted

## Owns one shop visit. The screen emits purchase intents; this coordinator
## applies, saves and refreshes without allowing UI code to mutate the session.

var _session: SandboxSessionAdapter
var _presenter: UiScreenPresenter
var _preferences: Dictionary = {}
var _hooks: Dictionary = {}
var _store_id := ""
var _screen: ShopScreen


func show(
	session: SandboxSessionAdapter,
	presenter: UiScreenPresenter,
	preferences: Dictionary,
	store_id: String,
	hooks: Dictionary
) -> void:
	_session = session
	_presenter = presenter
	_preferences = preferences.duplicate(true)
	_hooks = hooks.duplicate()
	_store_id = store_id
	_screen = _presenter.show_shop(
		_session.get_store_model(
			_store_id,
			bool(_preferences.get("reduced_motion", false))
		),
		_session.get_shell_model(),
		_preferences,
		{"back": _hook("back"), "purchase": _on_purchase_requested}
	)


func _on_purchase_requested(
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	expected_revision: int
) -> void:
	if not bool(_hook("begin_command").call()):
		return
	var result := _session.buy_store_offer(
		store_id,
		offer_id,
		quantity,
		target_container_id,
		expected_revision
	)
	if not bool(_hook("accept_result").call(result)):
		_hook("release_command").call()
		return
	_hook("capture_transaction").call(result)
	var saved: Dictionary = _hook("save").call()
	if _session.get_phase() == "completed":
		_hook("finished").call()
	elif _screen != null and is_instance_valid(_screen):
		_screen.present(_session.get_store_model(
			_store_id,
			bool(_preferences.get("reduced_motion", false))
		))
	if bool(saved.get("ok", false)):
		_hook("toast").call("Покупка уложена в вещи героя.")
	_hook("release_command").call()


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing shop-flow hook: %s" % key)
	return value
