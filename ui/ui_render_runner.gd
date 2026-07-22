extends SceneTree

const MainScene := preload("res://ui/main.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(432, 768)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell := MainScene.instantiate() as AppShell
	if shell == null:
		push_error("UI SMOKE FAILED: AppShell could not be instantiated")
		quit(1)
		return
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(shell)
	for _frame in range(10):
		await process_frame
	if not shell.current_screen() is MainMenuScreen:
		push_error("UI SMOKE FAILED: main menu was not presented")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("UI SMOKE PASSED: modular AppShell and main menu instantiated")
		quit(0)
		return
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("UI RENDER FAILED: viewport returned no pixels")
		quit(1)
		return
	var error := image.save_png("res://.godot/m3_ui_previews/main_menu_432x768.png")
	print("UI RENDER PASSED" if error == OK else "UI RENDER FAILED")
	quit(0 if error == OK else 1)
