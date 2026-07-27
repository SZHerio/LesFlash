extends SceneTree

const ShopScene := preload("res://ui/screens/shop/shop_screen.tscn")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const AdapterScript := preload("res://app/session/sandbox_session_adapter.gd")
const OutputDir := "res://docs/qa/m3f2"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var adapter := AdapterScript.create({
		"strength": 4,
		"charisma": 4,
		"intelligence": 5,
		"luck": 5,
	}, 19800901) as SandboxSessionAdapter
	if adapter == null:
		push_error("M3F.2 SHOP REFERENCE: session creation failed")
		quit(1)
		return
	var session: FirstDaySession = adapter.get("_session")
	session.location = "station_square"
	session.run_state.money = 240
	session.run_state.calendar.advance_minutes(60)
	session.survival_state.processed_elapsed_minutes = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OutputDir))
	for size: Vector2i in [Vector2i(360, 640), Vector2i(540, 960)]:
		var result := await _capture(adapter, size)
		if result != OK:
			push_error("M3F.2 SHOP REFERENCE: capture failed for %s" % size)
			quit(1)
			return
	print("M3F.2 SHOP VISUAL REFERENCES WRITTEN: 360x640, 540x960")
	quit(0)


func _capture(adapter: SandboxSessionAdapter, size: Vector2i) -> Error:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := ShopScene.instantiate() as ShopScreen
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(screen)
	screen.present(adapter.get_store_model("store_station_commission", true))
	for _frame: int in 12:
		await process_frame
	var image := viewport.get_texture().get_image()
	var result := ERR_CANT_CREATE if image == null or image.is_empty() else image.save_png(
		"%s/shop_station_%dx%d.png" % [OutputDir, size.x, size.y]
	)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame
	return result
