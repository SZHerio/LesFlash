extends SceneTree

const NpcScreenScene := preload("res://ui/screens/npc/npc_screen.tscn")
const NpcViewModel := preload("res://app/npc/npc_interaction_view_model.gd")
const PortraitRegistry := preload("res://app/npc/npc_portrait_registry.gd")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _failures: Array[String] = []
var _intents: Array = []
var _back_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_view_model()
	for size in TEST_SIZES:
		await _exercise(size, 1.0)
		await _exercise(size, 2.0)
	await _exercise_empty_state()
	if _failures.is_empty():
		print("M3F.3 NPC SCREEN SMOKE PASSED: 360x640 / 540x960 at 100/200%")
		quit(0)
		return
	for failure in _failures:
		push_error("M3F.3 NPC SCREEN: %s" % failure)
	quit(1)


func _test_view_model() -> void:
	for npc_id: String in ["npc_viktor_koren", "npc_lidia_maren", "npc_tamara_roven"]:
		var portrait_entry := PortraitRegistry.entry(npc_id)
		_require(String(portrait_entry.get("portrait_crop_mode", "")) == "focus_cover", "%s has no stable crop mode" % npc_id)
		var authored_focus: Dictionary = Dictionary(portrait_entry.get("portrait_focus", {}))
		_require(
			float(authored_focus.get("x", -1.0)) >= 0.0
			and float(authored_focus.get("x", 2.0)) <= 1.0
			and float(authored_focus.get("y", -1.0)) >= 0.0
			and float(authored_focus.get("y", 2.0)) <= 1.0,
			"%s portrait focus is outside normalized bounds" % npc_id
		)
	var model := _model(false)
	_require(String(model.get("npc_id", "")) == "npc_lidia_maren", "npc id was lost")
	_require(int(model.get("expected_revision", -1)) == 12, "revision was lost")
	_require(String(model.get("portrait_crop_mode", "")) == "focus_cover", "portrait crop mode was lost")
	var focus: Dictionary = Dictionary(model.get("portrait_focus", {}))
	_require(is_equal_approx(float(focus.get("x", -1.0)), 0.5), "portrait focus x was lost")
	_require(is_equal_approx(float(focus.get("y", -1.0)), 0.34), "portrait focus y was lost")
	var interactions: Array = model.get("interactions", [])
	_require(interactions.size() == 3, "view-model dropped interactions")
	_require(String(Dictionary(interactions[0]).get("category_icon_id", "")) == "action_talk", "typed icon was lost")
	_require(Array(Dictionary(interactions[0]).get("meta_tokens", [])).size() == 1, "duration token is missing")
	_require(not bool(Dictionary(interactions[2]).get("enabled", true)), "blocked interaction became available")
	_require(
		String(Dictionary(interactions[2]).get("locked_reason", "")).contains(
			"Доверие Лидии пока недостаточно"
		),
		"typed blocked reason message was lost"
	)


func _exercise(size: Vector2i, scale: float) -> void:
	var setup := _spawn(size, scale)
	var viewport: SubViewport = setup[0]
	var screen: Control = setup[1]
	if screen == null:
		return
	var model := _model(scale >= 2.0)
	screen.apply_model(model)
	for _frame in range(5):
		await process_frame
	var scroll := screen.get_node("%ContentScroll") as ScrollContainer
	_require(absf(screen.size.x - size.x) <= 2.0, "%s %.0f%% wrong width" % [size, scale * 100.0])
	_require(scroll.size.y >= 180.0, "%s %.0f%% scroll collapsed" % [size, scale * 100.0])
	_require(not scroll.get_h_scroll_bar().visible, "%s %.0f%% content spills sideways" % [size, scale * 100.0])
	var portrait := screen.get_node("%PortraitTexture") as Control
	_require(portrait.visible and bool(portrait.call("has_texture")), "production portrait was not presented")
	_require(not (screen.get_node("%PortraitFallback") as Control).visible, "fallback covers production portrait")
	var applied_focus: Vector2 = portrait.call("focus_normalized")
	_require(applied_focus.is_equal_approx(Vector2(0.5, 0.34)), "authored portrait focus was not applied")
	_require(String(portrait.call("crop_mode")) == "focus_cover", "portrait crop mode was not applied")
	_require((screen.get_node("%OutcomePanel") as Control).visible, "outcome/reactions are hidden")
	if size.x == 360 and is_equal_approx(scale, 1.0):
		_require(
			(screen.get_node("%RelationshipValue") as Label).get_line_count() <= 2,
			"relationship value is not compact at 360px"
		)
	var rows: Array[Node] = screen.get_node("%InteractionList").get_children()
	_require(rows.size() == 3, "interaction rows were not rendered")
	_check_touch_targets(screen, size, scale)
	_check_wrapping(screen)
	_intents.clear()
	var first := rows[0] as ActionRow
	var row_height_before := first.size.y
	var content_height_before := (screen.get_node("%Content") as Control).size.y
	first.pressed.emit()
	first.pressed.emit()
	_require(_intents.size() == 1, "double tap emitted %d intents" % _intents.size())
	if not _intents.is_empty():
		_require(_intents[0] == ["npc_lidia_maren", "ask_help", 12], "typed intent is incomplete: %s" % str(_intents[0]))
	_require(first.is_pending_feedback(), "selected row has no immediate pending feedback")
	_require((screen.get_node("%BackButton") as Button).disabled, "Back remains active during command")
	await process_frame
	await process_frame
	_require(absf(first.size.y - row_height_before) <= 1.0, "pending feedback changed row height")
	_require(
		absf((screen.get_node("%Content") as Control).size.y - content_height_before) <= 1.0,
		"pending feedback shifted the screen layout"
	)
	screen.apply_model(model)
	await process_frame
	_require(not (screen.get_node("%BackButton") as Button).disabled, "new model did not release guard")
	(screen.get_node("%BackButton") as Button).pressed.emit()
	_require(_back_count > 0, "Back intent was not emitted")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _exercise_empty_state() -> void:
	var setup := _spawn(Vector2i(360, 640), 1.0)
	var viewport: SubViewport = setup[0]
	var screen: Control = setup[1]
	var model := _model(false)
	model["portrait_path"] = ""
	model["interactions"] = []
	model["outcome"] = ""
	model["reactions"] = []
	screen.apply_model(model)
	await process_frame
	_require((screen.get_node("%PortraitFallback") as Control).visible, "missing portrait fallback is hidden")
	_require((screen.get_node("%EmptyState") as Control).visible, "empty state is hidden")
	_require(not (screen.get_node("%OutcomePanel") as Control).visible, "empty outcome panel is visible")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _spawn(size: Vector2i, scale: float) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := NpcScreenScene.instantiate() as Control
	_require(screen != null, "%s screen could not instantiate" % size)
	if screen == null:
		return [viewport, null]
	screen.theme = _scaled_theme(scale)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.interaction_requested.connect(func(npc_id: String, interaction_id: String, revision: int) -> void:
		_intents.append([npc_id, interaction_id, revision])
	)
	screen.back_requested.connect(func() -> void: _back_count += 1)
	viewport.add_child(screen)
	return [viewport, screen]


func _model(reduced_motion: bool) -> Dictionary:
	var source := {
		"npc_id": "npc_lidia_maren",
		"name": "Лидия Соколова с очень длинным уточнением для проверки переноса",
		"role": "Медсестра Приречной муниципальной поликлиники",
		"portrait_key": "npc_lidia_maren_neutral",
		"presence_text": "Сейчас во дворе поликлиники, но вскоре вернётся на приём",
		"relationship": {"label": "Отношение к герою", "value": "Осторожное доверие · +12"},
		"outcome": "Лидия внимательно выслушала героя и не обещала того, чего не сможет сделать.",
		"reactions": ["Она запомнила спокойную просьбу.", "Доверие немного выросло."],
		"revision": 12,
		"interactions": [
			{"interaction_id": "ask_help", "title": "Спросить, где сегодня можно получить безопасную помощь", "description": "Уточнить известные условия и часы работы службы.", "available": true, "duration_minutes": 6, "icon_id": &"action_talk"},
			{"interaction_id": "offer_help", "title": "Предложить помощь с коробками перевязочных материалов", "description": "Небольшое дело вместо просьбы о награде.", "available": true, "duration": 18, "icon_id": &"action_work", "variant": &"accent"},
			{"interaction_id": "discuss_records", "title": "Попросить проверить запись в старом журнале регистрации", "description": "Разговор требует конкретного знания и сложившегося доверия.", "available": false, "reasons": ["Нужно знание: порядок регистрации", {"code": "relationship_min", "message": "Доверие Лидии пока недостаточно"}], "duration_minutes": 12, "icon_id": &"meta_knowledge"},
		],
	}
	source.merge(PortraitRegistry.entry("npc_lidia_maren"), true)
	return NpcViewModel.build(source, reduced_motion)


func _check_touch_targets(node: Node, size: Vector2i, scale: float) -> void:
	for child in node.get_children():
		var button := child as BaseButton
		if button != null and button.is_visible_in_tree():
			_require(button.size.x >= 48.0 and button.size.y >= 48.0, "%s %.0f%% %s touch target %.0fx%.0f" % [size, scale * 100.0, button.name, button.size.x, button.size.y])
		_check_touch_targets(child, size, scale)


func _check_wrapping(node: Node) -> void:
	for child in node.get_children():
		var label := child as Label
		if label != null and label.is_visible_in_tree() and label.text.length() > 30:
			_require(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s cannot wrap long Russian text" % label.name)
		_check_wrapping(child)


func _scaled_theme(scale: float) -> Theme:
	var result := UiTheme.duplicate(true) as Theme
	result.default_font_size = int(round(float(UiTheme.default_font_size) * scale))
	return result


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
