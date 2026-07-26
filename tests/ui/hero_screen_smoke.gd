## Renders the hero screen at the two target widths and checks the promises it
## makes: nothing spills sideways, no label is silently cut, and a section the
## hero has not filled is absent rather than empty.

extends SceneTree

const HeroScreenScene = preload("res://ui/screens/hero/hero_screen.tscn")
const HeroModels = preload("res://app/hero/hero_view_model.gd")
const RunStateScript = preload("res://core/state/run_state.gd")
const UiTheme = preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]
const OUTPUT_DIR := "res://docs/qa/hero"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise(test_size, _lived_in_model(), "lived_in")
	await _exercise(TEST_SIZES[0], _fresh_model(), "fresh")
	if _failures.is_empty():
		print("HERO SCREEN SMOKE PASSED: 360x640 and 540x960")
		quit(0)
		return
	for failure in _failures:
		push_error("HERO SCREEN: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i, model: Dictionary, label: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var screen := HeroScreenScene.instantiate() as HeroScreen
	_require(screen != null, "%s screen could not be instantiated" % label)
	if screen == null:
		viewport.queue_free()
		return
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(screen)
	screen.present(model)
	for _frame in range(8):
		await process_frame

	_check_fits(screen, test_size, label)
	_check_no_clipped_text(screen, test_size, label)
	_check_touch_targets(screen, test_size, label)
	if label == "fresh":
		_check_empty_sections_are_absent(screen)
	else:
		_check_filled_sections(screen, model)
	await _capture(viewport, test_size, label)

	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_fits(screen: HeroScreen, test_size: Vector2i, label: String) -> void:
	_require(
		absf(screen.size.x - test_size.x) <= 2.0,
		"%s %s screen width is %.1f" % [label, test_size, screen.size.x]
	)
	var scroll := screen.get_node("%Scroll") as ScrollContainer
	_require(
		scroll != null and scroll.get_h_scroll_bar() != null
			and not scroll.get_h_scroll_bar().visible,
		"%s %s content spills sideways" % [label, test_size]
	)
	# The scroll bar is drawn over the content area, so right-aligned readings
	# have to stop before it starts or the player reads them through a bar.
	var bar := scroll.get_v_scroll_bar()
	if bar != null and bar.visible:
		var lane := screen.get_node("%ScrollLane") as MarginContainer
		var clearance := scroll.global_position.x + scroll.size.x - (
			lane.global_position.x + lane.size.x - lane.get_theme_constant(&"margin_right")
		)
		_require(
			clearance >= bar.size.x,
			"%s %s content clears the scroll bar by %.1f px of %.1f"
				% [label, test_size, clearance, bar.size.x]
		)


## A clipped Russian noun reads as a different word. `get_minimum_size()` is no
## use here — a `clip_text` label reports almost nothing, which is exactly how a
## cut label slips through — so the text is measured against its own font.
func _check_no_clipped_text(node: Node, test_size: Vector2i, label: String) -> void:
	for child in node.get_children():
		var text_label := child as Label
		if (
			text_label != null
			and text_label.is_visible_in_tree()
			and not text_label.text.is_empty()
			and text_label.autowrap_mode == TextServer.AUTOWRAP_OFF
		):
			var font := text_label.get_theme_font(&"font")
			var font_size := text_label.get_theme_font_size(&"font_size")
			var wanted: float = font.get_string_size(
				text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			).x
			_require(
				text_label.size.x + 1.0 >= wanted,
				"%s %s «%s» is cut: %.1f px of %.1f px"
					% [label, test_size, text_label.text, text_label.size.x, wanted]
			)
		_check_no_clipped_text(child, test_size, label)


func _check_touch_targets(node: Node, test_size: Vector2i, label: String) -> void:
	for child in node.get_children():
		var button := child as BaseButton
		if button != null and button.is_visible_in_tree():
			_require(
				button.size.x >= 48.0 and button.size.y >= 48.0,
				"%s %s %s touch target is %.0fx%.0f"
					% [label, test_size, button.name, button.size.x, button.size.y]
			)
		_check_touch_targets(child, test_size, label)


## Rule 3.4: an empty section announces a mechanic the player has not met.
func _check_empty_sections_are_absent(screen: HeroScreen) -> void:
	for section_name in ["SkillsTitle", "Skills", "KnowledgeTitle", "Knowledge"]:
		var section := screen.get_node("%%%s" % section_name) as Control
		_require(
			section != null and not section.is_visible_in_tree(),
			"%s is shown to a hero who has nothing in it" % section_name
		)


func _check_filled_sections(screen: HeroScreen, model: Dictionary) -> void:
	var characteristics := screen.get_node("%Characteristics") as HBoxContainer
	_require(
		characteristics.get_child_count() == 4,
		"characteristics row holds %d columns" % characteristics.get_child_count()
	)
	var axes := screen.get_node("%Polarities") as VBoxContainer
	var expected := Array(model.get("polarities", [])).size() + Array(model.get("profiles", [])).size()
	_require(
		axes.get_child_count() == expected,
		"style section holds %d rows, expected %d" % [axes.get_child_count(), expected]
	)
	var track_width := -1.0
	for row in axes.get_children():
		var track := row.get_node("%Track") as Control
		_require(track != null and track.size.y >= 8.0, "a style track collapsed to nothing")
		if track_width < 0.0:
			track_width = track.size.x
		_require(
			absf(track.size.x - track_width) <= 1.0,
			"style tracks differ in width (%.1f vs %.1f), so the centres do not line up"
				% [track.size.x, track_width]
		)
	var skills := screen.get_node("%Skills") as VBoxContainer
	_require(
		skills.is_visible_in_tree() and skills.get_child_count() == Array(model.get("skills", [])).size(),
		"skill rows do not match the model"
	)
	var knowledge := screen.get_node("%Knowledge") as Label
	_require(knowledge.is_visible_in_tree() and not knowledge.text.is_empty(), "knowledge line is empty")


func _capture(viewport: SubViewport, test_size: Vector2i, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var texture := viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var path := "%s/hero_%s_%dx%d.png" % [OUTPUT_DIR, label, test_size.x, test_size.y]
	_require(image.save_png(path) == OK, "could not save %s" % path)


func _shell() -> Dictionary:
	return {
		"status": {
			"money": 240,
			"calendar": {"year": 2024, "month": 9, "day": 12, "minute_of_day": 615},
		},
	}


## A hero part-way through a run: a few skills, a formed profile and a clear
## lean on two of the axes.
func _lived_in_model() -> Dictionary:
	var state: RunState = RunStateScript.new(
		{"strength": 6, "charisma": 3, "intelligence": 5, "luck": 4}, 4242
	)
	state.meters["morale"] = 44
	state.set_polarity("physical_specialization", -35)
	state.set_polarity("execution_style", 40)
	state.set_polarity("decision_priority", 12)
	state.set_skill_rank("city_navigation", 1)
	state.set_skill_rank("cargo_handling", 2)
	state.set_skill_rank("trade", 3)
	state.knowledge["ночлежка на Кузнечной"] = true
	state.knowledge["приём цветмета"] = true
	state.set_computed_profile("knowledge_profile", -20, GameRules.PROFILE_FORMATION_EVIDENCE + 1)
	return HeroModels.build(HeroModels.raw(state), _shell(), false, 1.0)


func _fresh_model() -> Dictionary:
	var state: RunState = RunStateScript.new(
		{"strength": 6, "charisma": 3, "intelligence": 5, "luck": 4}, 4242
	)
	return HeroModels.build(HeroModels.raw(state), _shell(), false, 1.0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
