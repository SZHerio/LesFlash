class_name UiCoordinator
extends Node

const PreferencesScript := preload("res://app/ui_preferences.gd")
const PersistenceScript := preload("res://app/session/session_persistence.gd")
const LifecycleScript := preload("res://app/session/session_lifecycle_coordinator.gd")
const ScreenPresenterScript := preload("res://app/ui_screen_presenter.gd")
const MapFlowScript := preload("res://app/flows/map_flow_coordinator.gd")
const LocationFlowScript := preload("res://app/flows/location_flow_coordinator.gd")
const PreferenceFlowScript := preload("res://app/flows/preference_flow_coordinator.gd")
const InventoryFlowScript := preload("res://app/flows/inventory_flow_coordinator.gd")
const SearchFlowScript := preload("res://app/flows/search_flow_coordinator.gd")
const ShopFlowScript := preload("res://app/flows/shop_flow_coordinator.gd")
const ShellNavigationFlowScript := preload("res://app/flows/shell_navigation_flow_coordinator.gd")
const JobShiftFlowScript := preload("res://app/flows/job_shift_flow_coordinator.gd")
const CommandRunnerScript := preload("res://app/flows/session_command_runner.gd")
const LegacyActivityFlowScript := preload("res://app/flows/legacy_activity_flow_coordinator.gd")

var _shell: AppShell
var _session: SandboxSessionAdapter
var _preferences: UiPreferences
var _persistence: SessionPersistence
var _lifecycle: SessionLifecycleCoordinator
var _screens: UiScreenPresenter
var _map_flow: MapFlowCoordinator
var _location_flow: LocationFlowCoordinator
var _preference_flow: RefCounted
var _inventory_flow: InventoryFlowCoordinator
var _search_flow: SearchFlowCoordinator
var _shop_flow: ShopFlowCoordinator
var _job_shift_flow: JobShiftFlowCoordinator
var _shell_navigation: ShellNavigationFlowCoordinator
var _commands: SessionCommandRunner
var _legacy_activity_flow: LegacyActivityFlowCoordinator
var _route := "boot"
var _shop_store_id := ""
var _settings_return_route := "menu"


func configure(persistence: SessionPersistence = null, preferences: UiPreferences = null) -> void:
	_persistence = persistence
	_preferences = preferences


func _ready() -> void:
	call_deferred("_boot")


func _boot() -> void:
	_shell = get_parent() as AppShell
	if _shell == null:
		push_error("UiCoordinator must be a direct child of AppShell.")
		return
	if _persistence == null:
		_persistence = PersistenceScript.new()
	if _preferences == null:
		_preferences = PreferencesScript.new()
	_lifecycle = LifecycleScript.new(_shell, _persistence)
	_screens = ScreenPresenterScript.new(_shell)
	_map_flow = MapFlowScript.new()
	_location_flow = LocationFlowScript.new()
	_preference_flow = PreferenceFlowScript.new(_shell, _preferences, _lifecycle, _screens)
	_inventory_flow = InventoryFlowScript.new()
	_search_flow = SearchFlowScript.new()
	_shop_flow = ShopFlowScript.new()
	_commands = CommandRunnerScript.new()
	_commands.configure(self, _shell, _lifecycle)
	_legacy_activity_flow = LegacyActivityFlowScript.new()
	_job_shift_flow = JobShiftFlowScript.new()
	_shell_navigation = ShellNavigationFlowScript.new()
	_shell_navigation.configure(
		_shell,
		_commands,
		_inventory_flow,
		_search_flow,
		{
			"close": _on_close_requested,
			"main_menu": _show_main_menu,
			"return_settings": _return_from_settings,
			"leave_session": _leave_session_to_menu,
			"location": _show_location,
			"map": _show_map,
			"hero": _show_hero,
			"inventory": _show_inventory,
		}
	)
	_shell.back_requested.connect(_on_back_requested)
	_shell.close_requested.connect(_on_close_requested)
	_shell.pause_requested.connect(_save_session.bind(false))
	_shell.autosave_requested.connect(_save_session.bind(false))
	_shell.navigation_requested.connect(_on_navigation_requested)
	var preference_result := _preferences.load_from_disk()
	if not bool(preference_result.get("ok", false)):
		_shell.show_toast("Настройки не удалось прочитать. Использованы безопасные значения.", true)
	_preference_flow.apply_visual(_session)
	_show_main_menu()


func _show_main_menu() -> void:
	_route = "menu"
	_session = null
	_commands.reset_feedback()
	_screens.show_main_menu(
		_persistence.has_candidates(),
		{
			"new_game": _show_character_creation,
			"continue": _continue_game,
			"settings": _open_settings,
			"quit": _on_close_requested,
		}
	)


func _show_character_creation() -> void:
	_route = "creation"
	_screens.show_character_creation(
		{"back": _show_main_menu, "confirm": _create_new_session}
	)


func _create_new_session(characteristics: Dictionary) -> void:
	if not _commands.try_begin(_session):
		return
	var seed := int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	var candidate := _persistence.create_session(characteristics, seed) as SandboxSessionAdapter
	if candidate == null or not candidate.is_valid():
		_shell.show_toast("Не удалось начать новую жизнь.", true)
		_commands.release()
		return
	_session = candidate
	_commands.reset_feedback()
	_preference_flow.apply_to_session(_session)
	var save_result := _save_session(false)
	if not bool(save_result.get("ok", false)):
		_session = null
		_commands.release()
		return
	_route_session()
	_commands.release()


func _continue_game() -> void:
	if not _commands.try_begin(_session):
		return
	var result: Dictionary = _persistence.load_session()
	if not bool(result.get("ok", false)):
		_shell.show_toast("Сохранение не загружено: %s" % _lifecycle.error_message(result), true)
		_commands.release()
		return
	_session = result.get("adapter") as SandboxSessionAdapter
	if _session == null or not _session.is_valid():
		_shell.show_toast("Сохранение не содержит рабочую игровую сессию.", true)
		_session = null
		_commands.release()
		return
	_commands.reset_feedback()
	_preference_flow.apply_to_session(_session)
	_route_session()
	if bool(result.get("migrated", false)):
		var migration_save := _save_session(false)
		if bool(migration_save.get("ok", false)):
			_shell.show_toast("Старое сохранение безопасно обновлено.")
	elif bool(result.get("recovered_from_temporary", false)) or bool(result.get("recovered_from_backup", false)):
		_shell.show_toast("Попытка восстановлена после прерванного сохранения.")
	_commands.release()


func _route_session() -> void:
	if _session == null:
		_show_main_menu()
		return
	if _session.get_phase() == "completed":
		_show_legacy("summary")
		return
	# The search is an activity layered on the location, so it wins over the
	# underlying phase and is restored first after a reload or a kill.
	if _session.is_search_active():
		_show_search()
		return
	# A shift is the same kind of layered activity, and six hours of it may
	# already be committed, so it is restored before the underlying phase.
	if _session.is_job_shift_active():
		_show_job_shift()
		return
	match _session.get_phase():
		"start", "event":
			_show_legacy("event")
		"map":
			_show_location()
		"completed":
			_show_legacy("summary")
		_:
			_shell.show_toast("Неизвестное состояние попытки.", true)
			_show_main_menu()


## Every flow needs the same command gating, result handling, saving and toasts.
## Only the routes a flow can reach differ.
func _flow_hooks(routes: Dictionary = {}) -> Dictionary:
	var hooks := {
		"settings": _open_settings,
		"run_command": _commands.run.bind(_session, _route_session),
		"begin_command": _commands.try_begin.bind(_session),
		"accept_result": _commands.accept_result,
		"capture_transaction": _commands.capture_transaction,
		"save": _commands.save.bind(_session),
		"toast": _shell.show_toast,
		"release_command": _commands.release,
	}
	hooks.merge(routes, true)
	return hooks


func _show_location() -> void:
	_route = "location"
	_location_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_commands.last_transaction(),
		_commands.status_delta_pending(),
		_flow_hooks({
			"npc_opened": func() -> void: _route = "npc",
			"job_shift_opened": func() -> void: _route = "job_shift",
			"location": _show_location,
			"finished": _route_session,
			"shelters": _show_legacy.bind("shelter"),
			"store": _show_store,
			"recycling": _show_recycling,
		})
	)
	_commands.clear_status_delta()


func _show_job_shift() -> void:
	_route = "job_shift"
	_job_shift_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_flow_hooks({"back": _show_location, "location": _show_location, "finished": _route_session})
	)


func _show_search() -> void:
	_route = "search"
	_search_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_flow_hooks({"location": _show_location})
	)
	_commands.clear_status_delta()


func _show_map() -> void:
	_route = "map"
	_map_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_flow_hooks({"back": _show_location, "arrived": _on_map_arrived})
	)


func _show_hero() -> void:
	_route = "hero"
	_screens.show_hero(
		_session.get_hero_model(),
		_session.get_shell_model(),
		_preferences.to_model(),
		{"settings": _open_settings}
	)


func _show_inventory() -> void:
	_route = "inventory"
	_inventory_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_flow_hooks()
	)


func _show_store(store_id: String) -> void:
	if store_id.strip_edges().is_empty():
		_shell.show_toast("Торговая точка не найдена.", true)
		return
	_route = "shop"
	_shop_store_id = store_id
	_shop_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		store_id,
		_flow_hooks({"back": _show_location, "finished": _route_session})
	)


func _show_recycling() -> void:
	_show_inventory()
	if _session.get_recycling_offers().is_empty():
		_shell.show_toast("В вещах пока нет вторсырья, которое здесь примут.")
	else:
		_shell.show_toast("Выберите вторсырьё и нажмите «Сдать в приёмный пункт».")


func _on_map_arrived(result: Dictionary) -> void:
	_show_location()
	if bool(result.get("show_travel_toast", true)):
		_shell.show_toast("Дорога заняла %d мин." % int(result.get("minutes", 0)))


func _show_legacy(route: String) -> void:
	_route = route
	_prepare_legacy_flow()
	_legacy_activity_flow.show(route)


func _open_settings() -> void:
	_settings_return_route = _route
	_route = "settings"
	_screens.show_settings(
		_preferences.to_model(),
		{"back": _return_from_settings, "change": _preference_flow.change.bind(_session)}
	)


func _return_from_settings() -> void:
	match _settings_return_route:
		"menu": _show_main_menu()
		"creation": _show_character_creation()
		"map": _show_map()
		"inventory": _show_inventory()
		"shop": _show_store(_shop_store_id)
		"shelter": _show_legacy(_settings_return_route)
		_: _route_session()


func _prepare_legacy_flow() -> void:
	_legacy_activity_flow.configure(
		_session,
		_screens,
		_preferences.to_model(),
		_flow_hooks({
			"location": _show_location,
			"leave": _leave_session_to_menu,
		})
	)


func _save_session(show_success: bool) -> Dictionary:
	return _commands.save(_session, show_success)


func _on_navigation_requested(tab_id: String) -> void:
	_shell_navigation.navigate(tab_id, _route)


func _on_back_requested() -> void:
	_shell_navigation.handle_back(_route)


func _leave_session_to_menu() -> void:
	_lifecycle.leave_to_menu(_session, _show_main_menu)


func _on_close_requested() -> void:
	_lifecycle.close_application(_session, get_tree())
