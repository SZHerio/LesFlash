class_name SessionCommandRunner
extends RefCounted

## Shared command gate for all UI flows. It owns double-tap protection,
## durable-save checks, result feedback and the latest status animation input.

var _owner: Node
var _shell: AppShell
var _lifecycle: SessionLifecycleCoordinator
var _in_flight := false
var _unlock_at_msec := 0
var _last_transaction: Dictionary = {}
var _status_delta_pending := false


func configure(
	owner: Node,
	shell: AppShell,
	lifecycle: SessionLifecycleCoordinator
) -> void:
	_owner = owner
	_shell = shell
	_lifecycle = lifecycle


func reset_feedback() -> void:
	_last_transaction.clear()
	_status_delta_pending = false


func last_transaction() -> Dictionary:
	return _last_transaction.duplicate(true)


func status_delta_pending() -> bool:
	return _status_delta_pending


func clear_status_delta() -> void:
	_status_delta_pending = false


func in_flight() -> bool:
	return _in_flight


func locked() -> bool:
	return _in_flight or Time.get_ticks_msec() < _unlock_at_msec


func unlock_remaining_msec() -> int:
	return maxi(_unlock_at_msec - Time.get_ticks_msec(), 0)


func run(
	command: Callable,
	show_outcome: bool,
	session: SandboxSessionAdapter,
	route_after: Callable
) -> void:
	if not try_begin(session):
		return
	var result: Dictionary = command.call()
	if not accept_result(result):
		release()
		return
	capture_transaction(result)
	var save_result := save(session)
	route_after.call()
	if (
		bool(save_result.get("ok", false))
		and show_outcome
		and not String(result.get("outcome", "")).is_empty()
	):
		_shell.show_toast(String(result.get("outcome", "")))
	release()


func save(session: SandboxSessionAdapter, show_success: bool = false) -> Dictionary:
	return _lifecycle.save(session, show_success)


func accept_result(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		return true
	_shell.show_toast(_lifecycle.error_message(result), true)
	return false


func capture_transaction(result: Dictionary) -> void:
	var raw_transaction: Variant = result.get("transaction", null)
	if raw_transaction is Dictionary and raw_transaction.get("changes", null) is Array:
		_last_transaction = Dictionary(raw_transaction).duplicate(true)
		_status_delta_pending = true


func try_begin(session: SandboxSessionAdapter) -> bool:
	if _in_flight or Time.get_ticks_msec() < _unlock_at_msec:
		return false
	if not _lifecycle.ensure_durable(session):
		return false
	_in_flight = true
	return true


func release() -> void:
	_unlock_at_msec = maxi(_unlock_at_msec, Time.get_ticks_msec() + 250)
	if _owner == null or not _owner.is_inside_tree():
		_in_flight = false
		return
	await _owner.get_tree().process_frame
	_in_flight = false
