extends SceneTree

const AppShellScene := preload("res://app/app_shell.tscn")

var _back_requests := 0
var _pause_requests := 0
var _autosave_requests := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	root.add_child(viewport)
	var shell := AppShellScene.instantiate() as AppShell
	var coordinator := shell.get_node("UiCoordinator")
	shell.remove_child(coordinator)
	coordinator.queue_free()
	shell.back_requested.connect(func() -> void: _back_requests += 1)
	shell.pause_requested.connect(func() -> void: _pause_requests += 1)
	shell.autosave_requested.connect(func() -> void: _autosave_requests += 1)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	await process_frame

	shell.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	shell.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	shell.call("_on_autosave_timer_timeout")
	var timer := shell.get_node("AutosaveTimer") as Timer

	if _back_requests != 1 or _pause_requests != 1 or _autosave_requests != 1:
		push_error("APP LIFECYCLE FAILED: Back/pause/autosave signals were not relayed exactly once")
		quit(1)
		return
	if not is_equal_approx(timer.wait_time, 300.0) or timer.is_stopped():
		push_error("APP LIFECYCLE FAILED: repeating autosave timer is not running at five minutes")
		quit(1)
		return
	print("APP LIFECYCLE TEST PASSED: Back, pause and five-minute autosave contracts")
	quit(0)
