extends SceneTree

const MainScene = preload("res://ui/main.tscn")
const PREVIEW_PATH := "res://ui_preview.png"
const PREVIEW_SIZE := Vector2i(432, 768)


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main = MainScene.instantiate()
	if main == null:
		push_error("UI SMOKE FAILED: main scene could not be instantiated")
		quit(1)
		return
	if not main.has_method("_show_main_menu"):
		push_error("UI SMOKE FAILED: main scene script did not compile")
		quit(1)
		return
	root.size = PREVIEW_SIZE
	root.add_child(main)
	for index in range(8):
		await process_frame
	var screen_host := main.get_node_or_null("UILayer/SafeArea/Center/ContentRoot/ScreenHost")
	if screen_host == null or screen_host.get_child_count() == 0:
		push_error("UI SMOKE FAILED: main menu was not built")
		quit(1)
		return
	if DisplayServer.get_name().to_lower() == "headless":
		print("UI SMOKE PASSED (SAFE MODE): headless dummy renderer has no reliable viewport pixels; screenshot skipped")
		quit(0)
		return
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("UI RENDER FAILED: window viewport texture is unavailable")
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("UI RENDER FAILED: windowed renderer returned an empty image")
		quit(1)
		return
	var error := image.save_png(PREVIEW_PATH)
	if error == OK:
		print("UI RENDER PASSED: %s (%dx%d)" % [PREVIEW_PATH, image.get_width(), image.get_height()])
	else:
		push_error("UI RENDER FAILED: preview could not be saved (error %d)" % error)
	quit(0 if error == OK else 1)
