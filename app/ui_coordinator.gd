class_name UiCoordinator
extends Node

const PreferencesScript := preload("res://app/ui_preferences.gd")
const PersistenceScript := preload("res://app/session/session_persistence.gd")
const ScreenPresenterScript := preload("res://app/ui_screen_presenter.gd")
const ErrorLocalizerScript := preload("res://app/ui_error_localizer.gd")

var _shell: AppShell
var _session: FirstDaySessionAdapter
var _preferences: UiPreferences
var _persistence: SessionPersistence
var _screens: UiScreenPresenter
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
	_screens = ScreenPresenterScript.new(_shell)
	_shell.back_requested.connect(_on_back_requested)
	_shell.close_requested.connect(_on_close_requested)
	_shell.pause_requested.connect(_on_pause_requested)
	_shell.autosave_requested.connect(_on_autosave_requested)
	_shell.navigation_requested.connect(_on_navigation_requested)
	var preference_result := _preferences.load_from_disk()
	if not bool(preference_result.get("ok", false)):
		_shell.show_toast("Настройки не удалось прочитать. Использованы безопасные значения.", true)
	_apply_visual_preferences()
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
	var candidate := _persistence.create_session(characteristics, seed)
	if candidate == null or not candidate.is_valid():
		_shell.show_toast("Не удалось начать новую жизнь.", true)
		_release_command_after_transition()
		return
	_session = candidate
	_last_transaction.clear()
	_status_delta_pending = false
	_apply_preferences_to_session()
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
		_shell.show_toast("Сохранение не загружено: %s" % _error_message(result), true)
		_release_command_after_transition()
		return
	_session = result.get("adapter") as FirstDaySessionAdapter
	if _session == null or not _session.is_valid():
		_shell.show_toast("Сохранение не содержит рабочую игровую сессию.", true)
		_session = null
		_release_command_after_transition()
		return
	_last_transaction.clear()
	_status_delta_pending = false
	_apply_preferences_to_session()
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
	var shell_model := _session.get_shell_model()
	var animate_status_delta := _status_delta_pending
	_screens.show_location(
		shell_model,
		_preferences.to_model(),
		{"action": _on_location_action, "settings": _open_settings},
		_last_transaction,
		animate_status_delta
	)
	_status_delta_pending = false


func _show_event() -> void:
	_route = "event"
	var raw_model := _session.get_current_event_model()
	_screens.show_event(
		raw_model,
		_session.get_shell_model(),
		_preferences.to_model(),
		{"action": _on_event_choice, "settings": _open_settings}
	)


func _show_job() -> void:
	_route = "job"
	_screens.show_job(
		_session.current_job_prompt(),
		_session.get_shell_model(),
		_preferences.to_model(),
		{"action": _on_job_answer, "settings": _open_settings}
	)


func _show_shelters() -> void:
	_route = "shelter"
	_screens.show_shelters(
		_session.available_shelters(),
		_session.get_shell_model(),
		_preferences.to_model(),
		{"action": _on_shelter_selected, "settings": _open_settings}
	)


func _show_job_result() -> void:
	_route = "job_result"
	_screens.show_job_result(
		_session.get_job_result_model(),
		_session.get_shell_model(),
		_preferences.to_model(),
		_show_location
	)


func _show_summary() -> void:
	_route = "summary"
	_screens.show_summary(
		_session.get_summary_model(),
		_session.get_shell_model(),
		_preferences.to_model(),
		_leave_session_to_menu
	)


func _open_settings() -> void:
	_settings_return_route = _route
	_route = "settings"
	_screens.show_settings(
		_preferences.to_model(),
		{"back": _return_from_settings, "change": _on_preference_changed}
	)


func _return_from_settings() -> void:
	match _settings_return_route:
		"menu": _show_main_menu()
		"creation": _show_character_creation()
		"shelter": _show_shelters()
		"job_result": _show_job_result()
		_: _route_session()


func _on_location_action(_action_id: String, action_model: Dictionary) -> void:
	var kind := String(action_model.get("kind", "event"))
	match kind:
		"event":
			_run_command(_session.enter_event.bind(String(action_model.get("id", ""))))
		"job":
			_run_command(_session.begin_job.bind("standard"))
		"wait":
			_run_command(_session.wait_until_evening, true)
		"shelter":
			if _try_begin_command():
				_show_shelters()
				_release_command_after_transition()


func _on_event_choice(choice_id: String) -> void:
	_run_command(_session.resolve_choice.bind(choice_id), true)


func _on_job_answer(choice_id: String) -> void:
	if not _try_begin_command():
		return
	var result: Dictionary = _session.answer_job(choice_id)
	if not _accept_result(result):
		_release_command_after_transition()
		return
	_capture_transaction(result)
	_save_session(false)
	if bool(result.get("completed", false)):
		_show_job_result()
	else:
		_show_job()
		_shell.show_toast("Результат раунда: +%d" % int(result.get("round_score", 0)))
	_release_command_after_transition()


func _on_shelter_selected(shelter_id: String) -> void:
	_run_command(_session.choose_shelter.bind(shelter_id))


func _run_command(command: Callable, show_outcome: bool = false) -> void:
	if not _try_begin_command():
		return
	var result: Dictionary = command.call()
	if not _accept_result(result):
		_release_command_after_transition()
		return
	_capture_transaction(result)
	_save_session(false)
	_route_session()
	if show_outcome and not String(result.get("outcome", "")).is_empty():
		_shell.show_toast(String(result.get("outcome", "")))
	_release_command_after_transition()


func _on_preference_changed(key: String, value: Variant) -> void:
	if not _preferences.apply(key, value):
		return
	var result := _preferences.save_to_disk()
	if not bool(result.get("ok", false)):
		_shell.show_toast("Настройка применена, но не сохранена.", true)
	_apply_visual_preferences()
	_apply_preferences_to_session()
	_save_session(false)


func _apply_visual_preferences() -> void:
	_shell.set_font_scale(_preferences.font_scale)
	_shell.set_reduced_motion(_preferences.reduced_motion)
	if _session != null:
		_screens.apply_session_ambience(_session.get_shell_model(), _preferences.to_model())


func _apply_preferences_to_session() -> void:
	if _session == null:
		return
	_session.set_setting("show_locked_options", _preferences.show_locked_options)
	_session.set_setting("psyche_effect_mode", _preferences.psyche_effect_mode)
	_session.set_setting("font_scale", _preferences.font_scale)


func _save_session(show_success: bool) -> Dictionary:
	var result: Dictionary = _persistence.save_session(_session)
	if not bool(result.get("ok", false)):
		_shell.show_toast("Не удалось сохранить попытку: %s" % _error_message(result), true)
	elif show_success:
		_shell.show_toast("Сохранено")
	return result


func _accept_result(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		return true
	_shell.show_toast(_error_message(result), true)
	return false


func _error_message(result: Dictionary) -> String:
	return ErrorLocalizerScript.message(result)


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
	_command_in_flight = true
	return true


func _on_navigation_requested(tab_id: String) -> void:
	if tab_id == "place":
		_show_location()


func _on_back_requested() -> void:
	match _route:
		"menu": _on_close_requested()
		"creation": _show_main_menu()
		"settings": _return_from_settings()
		"location":
			_leave_session_to_menu()
		"shelter": _show_location()
		"job_result": _show_location()
		"summary": _leave_session_to_menu()
		_:
			_shell.show_toast("Сначала завершите текущее решение.")


func _on_pause_requested() -> void:
	_save_session(false)


func _on_autosave_requested() -> void:
	_save_session(false)


func _leave_session_to_menu() -> void:
	var result := _save_session(false)
	if bool(result.get("ok", false)):
		_show_main_menu()


func _on_close_requested() -> void:
	var result := _save_session(false)
	if bool(result.get("ok", false)):
		get_tree().quit()
