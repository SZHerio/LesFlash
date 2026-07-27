extends SceneTree

const JobScreenScene := preload("res://ui/screens/job/job_screen.tscn")
const JobViewModel := preload("res://app/jobs/job_shift_view_model.gd")
const JobCatalog := preload("res://game/jobs/job_shift_catalog.gd")
const JobGenerator := preload("res://game/jobs/job_shift_generator.gd")
const JobService := preload("res://game/jobs/job_shift_service.gd")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _failures: Array[String] = []
var _choice_intents: Array = []
var _quick_intents: Array[int] = []
var _active_model: Dictionary = {}
var _completed_model: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_models()
	_test_view_model_contract()
	for size: Vector2i in TEST_SIZES:
		await _exercise(size, 1.0)
		await _exercise(size, 2.0)
	await _exercise_completed_state()
	if _failures.is_empty():
		print("M3F.4 JOB SCREEN SMOKE PASSED: contract, intents, 360x640 / 540x960 at 100/200%")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M3F.4 JOB SCREEN: %s" % failure)
	quit(1)


func _build_models() -> void:
	var loaded := JobCatalog.load_default()
	_require(bool(loaded.get("ok", false)), "job catalog did not load: %s" % str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var generated := JobGenerator.generate(loaded["catalog"], "job_recycling_sorter", 19800901, 2)
	_require(bool(generated.get("ok", false)), "job snapshot did not generate: %s" % str(generated.get("errors", [])))
	if not bool(generated.get("ok", false)):
		return
	var snapshot: Dictionary = generated["snapshot"]
	var started := JobService.start(snapshot)
	_require(bool(started.get("ok", false)), "job progress did not start")
	if not bool(started.get("ok", false)):
		return
	var progress: Dictionary = started["progress"]
	var profile := {
		"characteristics": {"strength": 6, "charisma": 4, "intelligence": 7, "luck": 1},
		"skills": {"cargo_handling": 1, "repair": 1, "search": 1, "trade": 0},
	}
	var first_preview := JobService.preview(snapshot, progress, profile)
	var first_choice := String(Dictionary(Array(first_preview.get("choices", []))[1]).get("id", ""))
	var first_result := JobService.resolve_step(snapshot, progress, first_choice, profile)
	_require(bool(first_result.get("ok", false)), "first job step did not resolve")
	if not bool(first_result.get("ok", false)):
		return
	progress = first_result["progress"]
	var current_preview := JobService.preview(snapshot, progress, profile)
	var raw_active := {
		"snapshot": snapshot,
		"progress": progress,
		"current_step": current_preview,
		"quick_resolve": {
			"eligible": true,
			"enabled": true,
			"title": "Рассчитать знакомые операции",
			"description": "Освоенные действия будут рассчитаны сразу, а итог останется сопоставимым с ручной сменой.",
		},
		"expected_revision": 23,
	}
	_active_model = JobViewModel.build(raw_active, true)
	while String(progress.get("status", "")) != "completed":
		var preview := JobService.preview(snapshot, progress, profile)
		var choices: Array = preview.get("choices", [])
		var choice_index := mini(1, choices.size() - 1)
		var choice_id := String(Dictionary(choices[choice_index]).get("id", ""))
		var resolved := JobService.resolve_step(snapshot, progress, choice_id, profile)
		_require(bool(resolved.get("ok", false)), "completion step did not resolve")
		if not bool(resolved.get("ok", false)):
			break
		progress = resolved["progress"]
	var settled_result := Dictionary(progress.get("result", {})).duplicate(true)
	settled_result["payout_ard"] = 224
	settled_result["mastery_awarded"] = 2
	settled_result["summary"] = "Виктор принял работу и отметил аккуратное обращение с площадкой."
	_completed_model = JobViewModel.build({
		"snapshot": snapshot,
		"progress": progress,
		"result": settled_result,
		"quick_resolve": true,
		"expected_revision": 27,
	}, true)


func _test_view_model_contract() -> void:
	if _active_model.is_empty():
		return
	_require(String(_active_model.get("job_id", "")) == "job_recycling_sorter", "job id was lost")
	_require(int(_active_model.get("expected_revision", -1)) == 23, "revision was lost")
	_require(Array(_active_model.get("metrics", [])).size() == 3, "three live metrics were not produced")
	var step: Dictionary = _active_model.get("current_step", {})
	_require(not step.is_empty(), "current step was lost")
	_require(Array(step.get("choices", [])).size() >= 2, "current step choices were lost")
	var first_choice: Dictionary = Array(step.get("choices", []))[0]
	_require(Array(first_choice.get("meta_tokens", [])).size() == 3, "projected score trade-offs are missing")
	_require(bool(Dictionary(_active_model.get("quick_resolve", {})).get("visible", false)), "earned quick resolve is hidden")
	_require(bool(Dictionary(_completed_model.get("result", {})).get("visible", false)), "completed result is hidden")
	_require(not bool(Dictionary(_completed_model.get("quick_resolve", {})).get("visible", true)), "quick resolve remains visible after completion")
	var derived_raw := {
		"snapshot": Dictionary(_active_model_source().get("snapshot", {})),
		"progress": Dictionary(_active_model_source().get("progress", {})),
		"expected_revision": 31,
	}
	var before := JSON.stringify(derived_raw)
	var derived := JobViewModel.build(derived_raw, true)
	_require(not Dictionary(derived.get("current_step", {})).is_empty(), "view-model did not derive current step from snapshot")
	_require(JSON.stringify(derived_raw) == before, "view-model mutated its input")


func _exercise(size: Vector2i, scale: float) -> void:
	var setup := _spawn(size, scale)
	var viewport: SubViewport = setup[0]
	var screen: JobScreen = setup[1]
	if screen == null:
		return
	screen.apply_model(_active_model)
	for _frame: int in 8:
		await process_frame
	var scroll := screen.get_node("%ContentScroll") as ScrollContainer
	_require(absf(screen.size.x - size.x) <= 2.0, "%s %.0f%% wrong width" % [size, scale * 100.0])
	_require(scroll.size.y >= 160.0, "%s %.0f%% scroll collapsed" % [size, scale * 100.0])
	_require(not scroll.get_h_scroll_bar().visible, "%s %.0f%% content spills sideways" % [size, scale * 100.0])
	_require((screen.get_node("%StepPanel") as Control).visible, "active step is hidden")
	_require((screen.get_node("%QuickPanel") as Control).visible, "earned quick resolve panel is hidden")
	_require(not (screen.get_node("%ResultPanel") as Control).visible, "active shift shows a completed result")
	var rows: Array[Node] = screen.get_node("%ChoiceList").get_children()
	_require(rows.size() >= 2, "choice rows were not rendered")
	_require((screen.get_node("%WorkIcon") as TextureRect).texture != null, "work visual anchor is missing")
	for metric_name: String in ["ProductionMetric", "QualityMetric", "SafetyMetric"]:
		var card := screen.get_node("%%%s" % metric_name) as JobMetricCard
		_require(card != null and card.displayed_value() >= 0, "%s is not presented" % metric_name)
	_check_touch_targets(screen, size, scale)
	_check_wrapping(screen)
	_choice_intents.clear()
	var first := rows[0] as ActionRow
	first.pressed.emit()
	first.pressed.emit()
	_require(_choice_intents.size() == 1, "double tap emitted %d choice intents" % _choice_intents.size())
	if not _choice_intents.is_empty():
		_require(int(_choice_intents[0][1]) == 23, "choice intent lost expected revision")
	_require(first.is_pending_feedback(), "choice has no immediate pending feedback")
	screen.apply_model(_active_model)
	await process_frame
	_quick_intents.clear()
	var quick := screen.get_node("%QuickButton") as Button
	quick.pressed.emit()
	quick.pressed.emit()
	_require(_quick_intents == [23], "quick-resolve intent is not idempotent: %s" % str(_quick_intents))
	_require(quick.disabled, "quick-resolve button has no immediate pending state")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _exercise_completed_state() -> void:
	var setup := _spawn(Vector2i(360, 640), 1.0)
	var viewport: SubViewport = setup[0]
	var screen: JobScreen = setup[1]
	screen.apply_model(_completed_model)
	for _frame: int in 4:
		await process_frame
	_require((screen.get_node("%ResultPanel") as Control).visible, "completed result panel is hidden")
	_require(not (screen.get_node("%StepPanel") as Control).visible, "completed shift still shows a task")
	_require(not (screen.get_node("%ChoiceList") as Control).visible, "completed shift still shows choices")
	_require(not (screen.get_node("%QuickPanel") as Control).visible, "completed shift still shows quick resolve")
	_require((screen.get_node("%ResultPayout") as Label).text == "Оплата: 224 ардена", "fictional-currency payout is wrong")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _spawn(size: Vector2i, scale: float) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := JobScreenScene.instantiate() as JobScreen
	_require(screen != null, "%s screen could not instantiate" % size)
	if screen == null:
		return [viewport, null]
	screen.theme = _scaled_theme(scale)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.choice_requested.connect(func(choice_id: String, revision: int) -> void:
		_choice_intents.append([choice_id, revision])
	)
	screen.quick_resolve_requested.connect(func(revision: int) -> void:
		_quick_intents.append(revision)
	)
	viewport.add_child(screen)
	return [viewport, screen]


func _active_model_source() -> Dictionary:
	var loaded := JobCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return {}
	var generated := JobGenerator.generate(loaded["catalog"], "job_recycling_sorter", 19800901, 2)
	if not bool(generated.get("ok", false)):
		return {}
	var snapshot: Dictionary = generated["snapshot"]
	var started := JobService.start(snapshot)
	return {"snapshot": snapshot, "progress": started.get("progress", {})}


func _check_touch_targets(node: Node, size: Vector2i, scale: float) -> void:
	for child: Node in node.get_children():
		var button := child as BaseButton
		if button != null and button.is_visible_in_tree():
			_require(
				button.size.x >= 48.0 and button.size.y >= 48.0,
				"%s %.0f%% %s touch target %.0fx%.0f" % [size, scale * 100.0, button.name, button.size.x, button.size.y]
			)
		_check_touch_targets(child, size, scale)


func _check_wrapping(node: Node) -> void:
	for child: Node in node.get_children():
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
