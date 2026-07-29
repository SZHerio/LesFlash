class_name ShellNavigationFlowCoordinator
extends RefCounted

## Owns shell-only tab and Back semantics. The visible UI route is supplied by
## the composition root for each request; it never becomes a gameplay phase or
## persisted activity.

const REQUIRED_HOOKS := [
	"close",
	"main_menu",
	"return_settings",
	"leave_session",
	"location",
	"map",
	"hero",
	"routine",
	"inventory",
]

var _shell: AppShell
var _commands: SessionCommandRunner
var _inventory_flow: InventoryFlowCoordinator
var _search_flow: SearchFlowCoordinator
var _hooks: Dictionary = {}


func configure(
	shell: AppShell,
	commands: SessionCommandRunner,
	inventory_flow: InventoryFlowCoordinator,
	search_flow: SearchFlowCoordinator,
	hooks: Dictionary
) -> void:
	_shell = shell
	_commands = commands
	_inventory_flow = inventory_flow
	_search_flow = search_flow
	_hooks = hooks.duplicate()
	for key: String in REQUIRED_HOOKS:
		_hook(key)


func navigate(tab_id: String, current_route: String) -> void:
	if _commands.in_flight():
		return
	if current_route == "inventory" and _inventory_flow.has_modal():
		return
	# Search is an interruptible activity and owns the screen until the player
	# explicitly leaves it; a stray bottom-tab signal cannot abandon the zone.
	if current_route in ["search", "job_shift"]:
		return
	match tab_id:
		"place": _hook("location").call()
		"map": _hook("map").call()
		"hero": _hook("hero").call()
		"routine": _hook("routine").call()
		"items": _hook("inventory").call()


func handle_back(current_route: String) -> void:
	if _commands.in_flight():
		return
	match current_route:
		"menu":
			_hook("close").call()
		"creation":
			var creation := _shell.current_screen() as CharacterCreationScreen
			if creation == null or not creation.handle_back():
				_hook("main_menu").call()
		"settings":
			_hook("return_settings").call()
		"location", "summary":
			_hook("leave_session").call()
		"inventory":
			if not _inventory_flow.handle_back():
				_hook("location").call()
		"search":
			if not _search_flow.handle_back():
				_hook("location").call()
		"map", "hero", "routine", "npc", "shop", "shelter", "job_shift":
			_hook("location").call()
		_:
			_shell.show_toast("Сначала завершите текущее решение.")


func _hook(key: String) -> Callable:
	var value: Variant = _hooks.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing shell-navigation hook: %s" % key)
	return value
