extends SceneTree

const NpcScene := preload("res://ui/screens/npc/npc_screen.tscn")
const NpcViewModel := preload("res://app/npc/npc_interaction_view_model.gd")
const PortraitRegistry := preload("res://app/npc/npc_portrait_registry.gd")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const OutputDir := "res://docs/qa/m3f3"
const PortraitPath := "res://assets/portraits/npc_lidia_maren.png"
const BackgroundPath := "res://assets/backgrounds/riverside_clinic_yard_day.png"
const Sizes: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(PortraitPath, "Texture2D"):
		push_error("M3F.3 NPC REFERENCE: portrait is not imported")
		quit(1)
		return
	if not ResourceLoader.exists(BackgroundPath, "Texture2D"):
		push_error("M3F.3 NPC REFERENCE: location background is not imported")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OutputDir))
	for size: Vector2i in Sizes:
		var result := await _capture(size)
		if result != OK:
			push_error("M3F.3 NPC REFERENCE: capture failed for %s (%d)" % [size, result])
			quit(1)
			return
	print("M3F.3 NPC VISUAL REFERENCES WRITTEN: 360x640, 540x960")
	quit(0)


func _capture(size: Vector2i) -> Error:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := TextureRect.new()
	backdrop.texture = load(BackgroundPath) as Texture2D
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(backdrop)
	var screen := NpcScene.instantiate() as Control
	if screen == null:
		return ERR_CANT_CREATE
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(screen)
	screen.call("present", _model())
	for _frame: int in 12:
		await process_frame
	var image := viewport.get_texture().get_image()
	var result := ERR_CANT_CREATE if image == null or image.is_empty() else image.save_png(
		"%s/npc_lidia_%dx%d.png" % [OutputDir, size.x, size.y]
	)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame
	return result


func _model() -> Dictionary:
	var source := {
		"npc_id": "npc_lidia_maren",
		"name": "Лидия Марен",
		"role": "Медсестра Приречной поликлиники",
		"presence_text": "Сейчас во дворе поликлиники · до 17:30",
		"relationship": {
			"label": "Отношение к герою",
			"value": "Осторожное доверие · +12",
		},
		"outcome": "Лидия выслушала героя и уточнила, что сможет сделать сегодня.",
		"reactions": ["Она запомнила спокойную просьбу."],
		"revision": 4,
		"interactions": [
			{
				"interaction_id": "ask_clinic_help",
				"title": "Спросить о доступной помощи",
				"description": "Уточнить условия и часы работы городской службы.",
				"available": true,
				"duration_minutes": 6,
				"icon_id": &"action_talk",
			},
			{
				"interaction_id": "offer_supply_help",
				"title": "Помочь перенести коробки",
				"description": "Небольшое дело во дворе поликлиники.",
				"available": true,
				"duration_minutes": 18,
				"icon_id": &"action_work",
				"variant": &"accent",
			},
			{
				"interaction_id": "ask_registry",
				"title": "Спросить о старой записи",
				"description": "Для предметного разговора пока не хватает сведений.",
				"available": false,
				"reasons": [{
					"code": "knowledge_missing",
					"message": "Нужно знание: порядок регистрации",
				}],
				"duration_minutes": 10,
				"icon_id": &"meta_knowledge",
			},
		],
	}
	source.merge(PortraitRegistry.entry("npc_lidia_maren"), true)
	return NpcViewModel.build(source, true)
