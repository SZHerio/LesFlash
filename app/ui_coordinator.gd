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
var _legacy_activity_flow: LegacyActivityFlowCoordinator
var _route := "boot"
var _settings_return_route := "menu"
var _command_in_flight := false
var _command_unlock_at_msec := 0
var _last_transaction: Dictionary = {}
var _status_delta_pending := false


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
	_legacy_activity_flow = LegacyActivityFlowScript.new()
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
	_last_transaction.clear()
	_status_delta_pending = false
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
	if not _try_begin_command():
		return
	var seed := int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	var candidate := _persistence.create_session(characteristics, seed) as SandboxSessionAdapter
	if candidate == null or not candidate.is_valid():
		_shell.show_toast("Не удалось начать новую жизнь.", true)
		_release_command_after_transition()
		return
	_session = candidate
	_last_transaction.clear()
	_status_delta_pending = false
	_preference_flow.apply_to_session(_session)
	var save_result := _save_session(false)
	if not bool(save_result.get("ok", false)):
		_session = null
		_release_command_after_transition()
		return
	_route_session()
	_release_command_after_transition()


func _continue_game() -> void:
	if not _try_begin_command():
		return
	var result: Dictionary = _persistence.load_session()
	if not bool(result.get("ok", false)):
		_shell.show_toast("Сохранение не загружено: %s" % _lifecycle.error_message(result), true)
		_release_command_after_transition()
		return
	_session = result.get("adapter") as SandboxSessionAdapter
	if _session == null or not _session.is_valid():
		_shell.show_toast("Сохранение не содержит рабочую игровую сессию.", true)
		_session = null
		_release_command_after_transition()
		return
	_last_transaction.clear()
	_status_delta_pending = false
	_preference_flow.apply_to_session(_session)
	_route_session()
	if bool(result.get("migrated", false)):
		var migration_save := _save_session(false)
		if bool(migration_save.get("ok", false)):
			_shell.show_toast("Старое сохранение безопасно обновлено.")
	elif bool(result.get("recovered_from_temporary", false)) or bool(result.get("recovered_from_backup", false)):
		_shell.show_toast("Попытка восстановлена после прерванного сохранения.")
	_release_command_after_transition()


func _route_session() -> void:
	if _session == null:
		_show_main_menu()
		return
	match _session.get_phase():
		"start", "event":
			_show_event()
		"map":
			_show_location()
		"job":
			_show_job()
		"completed":
			_show_summary()
		_:
			_shell.show_toast("Неизвестное состояние попытки.", true)
			_show_main_menu()


func _show_location() -> void:
	_route = "location"
	_location_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		_last_transaction,
		_status_delta_pending,
		{
			"settings": _open_settings,
			"run_command": _run_command,
			"begin_command": _try_begin_command,
			"shelters": _show_shelters,
			"release_command": _release_command_after_transition,
		}
	)
	_status_delta_pending = false


func _show_map() -> void:
	_route = "map"
	_map_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		{
			"back": _show_location,
			"begin_command": _try_begin_command,
			"accept_result": _accept_result,
			"capture_transaction": _capture_transaction,
			"save": _save_session.bind(false),
			"arrived": _on_map_arrived,
			"release_command": _release_command_after_transition,
		}
	)


func _show_inventory() -> void:
	_route = "inventory"
	_inventory_flow.show(
		_session,
		_screens,
		_preferences.to_model(),
		{
			"settings": _open_settings,
			"begin_command": _try_begin_command,
			"accept_result": _accept_result,
			"capture_transaction": _capture_transaction,
			"save": _save_session.bind(false),
			"toast": _shell.show_toast,
			"release_command": _release_command_after_transition,
		}
	)


func _on_map_arrived(result: Dictionary) -> void:
	_show_location()
	if bool(result.get("show_travel_toast", true)):
		_shell.show_toast("Дорога заняла %d мин." % int(result.get("minutes", 0)))


func _show_event() -> void:
	_route = "event"
	_prepare_legacy_flow()
	_legacy_activity_flow.show_event()


func _show_job() -> void:
	_route = "job"
	_prepare_legacy_flow()
	_legacy_activity_flow.show_job()


func _show_shelters() -> void:
	_route = "shelter"
	_prepare_legacy_flow()
	_legacy_activity_flow.show_shelters()


func _show_job_result() -> void:
	_route = "job_result"
	_prepare_legacy_flow()
	_legacy_activity_flow.show_job_result()


func _show_summary() -> void:
	_route = "summary"
	_prepare_legacy_flow()
	_legacy_activity_flow.show_summary()


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
		"shelter": _show_shelters()
		"job_result": _show_job_result()
		_: _route_session()


func _prepare_legacy_flow() -> void:
	_legacy_activity_flow.configure(
		_session,
		_screens,
		_preferences.to_model(),
		{
			"settings": _open_settings,
			"run_command": _run_command,
			"begin_command": _try_begin_command,
			"accept_result": _accept_result,
			"capture_transaction": _capture_transaction,
			"save": _save_session.bind(false),
			"job_result": _show_job_result,
			"location": _show_location,
			"leave": _leave_session_to_menu,
			"toast": _shell.show_toast,
			"release_command": _release_command_after_transition,
		}
	)


func _run_command(command: Callable, show_outcome: bool = false) -> void:
	if not _try_begin_command():
		return
	var result: Dictionary = command.call()
	if not _accept_result(result):
		_release_command_after_transition()
		return
	_capture_transaction(result)
	var save_result := _save_session(false)
	_route_session()
	if (
		bool(save_result.get("ok", false))
		and show_outcome
		and not String(result.get("outcome", "")).is_empty()
	):
		_shell.show_toast(String(result.get("outcome", "")))
	_release_command_after_transition()


func _save_session(show_success: bool) -> Dictionary:
	return _lifecycle.save(_session, show_success)


func _accept_result(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		return true
	_shell.show_toast(_lifecycle.error_message(result), true)
	return false


func _capture_transaction(result: Dictionary) -> void:
	var raw_transaction: Variant = result.get("transaction", null)
	if raw_transaction is Dictionary and raw_transaction.get("changes", null) is Array:
		_last_transaction = Dictionary(raw_transaction).duplicate(true)
		_status_delta_pending = true


func _release_command_after_transition() -> void:
	_command_unlock_at_msec = maxi(_command_unlock_at_msec, Time.get_ticks_msec() + 250)
	if not is_inside_tree():
		_command_in_flight = false
		return
	await get_tree().process_frame
	_command_in_flight = false


func _try_begin_command() -> bool:
	if _command_in_flight or Time.get_ticks_msec() < _command_unlock_at_msec:
		return false
	if not _lifecycle.ensure_durable(_session):
		return false
	_command_in_flight = true
	return true


func _on_navigation_requested(tab_id: String) -> void:
	if _command_in_flight:
		return
	if _route == "inventory" and _inventory_flow.has_modal():
		return
	match tab_id:
		"place":
			_show_location()
		"map":
			_show_map()
		"items":
			_show_inventory()


func _on_back_requested() -> void:
	if _command_in_flight:
		return
	match _route:
		"menu": _on_close_requested()
		"creation": _show_main_menu()
		"settings": _return_from_settings()
		"location":
			_leave_session_to_menu()
		"map":
			_show_location()
		"inventory":
			if not _inventory_flow.handle_back():
				_show_location()
		"shelter": _show_location()
		"job_result": _show_location()
		"summary": _leave_session_to_menu()
		_:
			_shell.show_toast("Сначала завершите текущее решение.")


func _leave_session_to_menu() -> void:
	_lifecycle.leave_to_menu(_session, _show_main_menu)


func _on_close_requested() -> void:
	_lifecycle.close_application(_session, get_tree())
