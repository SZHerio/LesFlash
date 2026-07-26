extends SceneTree

const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")
const SemanticIconScene := preload("res://ui/components/semantic_icon.tscn")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const Palette := preload("res://ui/theme/palette.gd")

const PREVIEW_SIZE := Vector2i(720, 1024)
const OUTPUT_PATH := "res://docs/qa/iconography/iconography_master.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("ICONOGRAPHY PREVIEW SKIPPED: headless display")
		quit(0)
		return
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Palette.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	margin.theme = UiTheme
	background.add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 10)
	margin.add_child(page)
	var title := Label.new()
	title.text = "БОМЖАРА · СИСТЕМА ИКОНОК"
	title.add_theme_font_size_override(&"font_size", 26)
	title.add_theme_color_override(&"font_color", Palette.TEXT)
	page.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Авторские SVG · сетка 24 × 24 · мастер-проверка в 32 dp"
	subtitle.add_theme_font_size_override(&"font_size", 14)
	subtitle.add_theme_color_override(&"font_color", Palette.MUTED)
	page.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	page.add_child(grid)
	for icon_id: StringName in IconRegistryScript.all_ids():
		grid.add_child(_icon_cell(icon_id))

	for _frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var image := viewport.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error == OK:
		print("ICONOGRAPHY PREVIEW RENDERED: %s" % OUTPUT_PATH)
		quit(0)
	else:
		push_error("ICONOGRAPHY PREVIEW: could not save image (%d)" % error)
		quit(1)


func _icon_cell(icon_id: StringName) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(124, 116)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_LIGHT
	style.border_color = Palette.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 8
	style.content_margin_top = 10
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override(&"panel", style)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override(&"separation", 8)
	panel.add_child(content)
	var icon := SemanticIconScene.instantiate() as SemanticIcon
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.present(icon_id, 32, _group_colour(icon_id))
	content.add_child(icon)
	var label := Label.new()
	label.text = String(icon_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 11)
	label.add_theme_color_override(&"font_color", Palette.MUTED)
	content.add_child(label)
	return panel


func _group_colour(icon_id: StringName) -> Color:
	var value := String(icon_id)
	if value.begins_with("action_"):
		return Palette.GOLD
	if value.begins_with("place_"):
		return Palette.GREEN_BRIGHT
	if value.begins_with("transport_"):
		return Palette.BLUE
	if value.begins_with("currency_"):
		return Palette.GOLD
	return Palette.TEXT
