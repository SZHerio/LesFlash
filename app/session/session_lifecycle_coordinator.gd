class_name SessionLifecycleCoordinator
extends RefCounted

const ErrorLocalizer := preload("res://app/ui_error_localizer.gd")

var _shell: AppShell
var _persistence: SessionPersistence
var _save_barrier_active := false


func _init(shell: AppShell, persistence: SessionPersistence) -> void:
	_shell = shell
	_persistence = persistence


func save(session: RunSessionAdapter, show_success: bool = false) -> Dictionary:
	if session == null:
		_save_barrier_active = false
		return {
			"ok": true,
			"code": "no_active_session",
			"error": "",
			"skipped": true,
		}
	var result: Dictionary = _persistence.save_session(session)
	_save_barrier_active = not bool(result.get("ok", false))
	if not bool(result.get("ok", false)):
		_shell.show_toast("Не удалось сохранить попытку: %s" % error_message(result), true)
	elif show_success:
		_shell.show_toast("Сохранено")
	return result


func ensure_durable(session: RunSessionAdapter) -> bool:
	return not _save_barrier_active or bool(save(session).get("ok", false))


func leave_to_menu(session: RunSessionAdapter, on_saved: Callable) -> void:
	if bool(save(session).get("ok", false)):
		on_saved.call()


func close_application(session: RunSessionAdapter, tree: SceneTree) -> void:
	if bool(save(session).get("ok", false)):
		tree.quit()


func error_message(result: Dictionary) -> String:
	return ErrorLocalizer.message(result)
