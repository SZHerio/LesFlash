class_name PreferenceFlowCoordinator
extends RefCounted

## Owns preference persistence and the small bridge from visual preferences to
## serialized session settings. A failed gameplay save is recovered before
## settings are allowed to advance the session revision.

var _shell: AppShell
var _preferences: UiPreferences
var _lifecycle: SessionLifecycleCoordinator
var _screens: UiScreenPresenter


func _init(
	shell: AppShell,
	preferences: UiPreferences,
	lifecycle: SessionLifecycleCoordinator,
	screens: UiScreenPresenter
) -> void:
	_shell = shell
	_preferences = preferences
	_lifecycle = lifecycle
	_screens = screens


func change(key: String, value: Variant, session: RunSessionAdapter) -> void:
	if session != null and not _lifecycle.ensure_durable(session):
		return
	if not _preferences.apply(key, value):
		return
	var result := _preferences.save_to_disk()
	if not bool(result.get("ok", false)):
		_shell.show_toast("Настройка применена, но не сохранена.", true)
	apply_visual(session)
	apply_to_session(session)
	if session != null:
		_lifecycle.save(session)


func apply_visual(session: RunSessionAdapter) -> void:
	_shell.set_font_scale(_preferences.font_scale)
	_shell.set_reduced_motion(_preferences.reduced_motion)
	if session != null:
		_screens.apply_session_ambience(session.get_shell_model(), _preferences.to_model())


func apply_to_session(session: RunSessionAdapter) -> void:
	if session == null:
		return
	session.set_setting("show_locked_options", _preferences.show_locked_options)
	session.set_setting("psyche_effect_mode", _preferences.psyche_effect_mode)
	session.set_setting("font_scale", _preferences.font_scale)
