extends SceneTree

const JobScreenScene := preload("res://ui/screens/job/job_screen.tscn")
const JobViewModel := preload("res://app/jobs/job_shift_view_model.gd")
const JobCatalog := preload("res://game/jobs/job_shift_catalog.gd")
const JobGenerator := preload("res://game/jobs/job_shift_generator.gd")
const JobService := preload("res://game/jobs/job_shift_service.gd")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const OutputDir := "res://docs/qa/m3f4"
const BackgroundPath := "res://assets/backgrounds/riverside_recycling_point_day.png"
const Sizes: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _active_model: Dictionary = {}
var _result_model: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(BackgroundPath, "Texture2D"):
		push_error("M3F.4 JOB REFERENCE: recycling-point background is not imported")
		quit(1)
		return
	if not _build_models():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OutputDir))
	for size: Vector2i in Sizes:
		for state: String in ["active", "result"]:
			var model := _active_model if state == "active" else _result_model
			var error := await _capture(size, state, model)
			if error != OK:
				push_error("M3F.4 JOB REFERENCE: %s capture failed for %s (%d)" % [state, size, error])
				quit(1)
				return
	print("M3F.4 JOB VISUAL REFERENCES WRITTEN: active/result at 360x640 and 540x960")
	quit(0)


func _build_models() -> bool:
	var loaded := JobCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		push_error("M3F.4 JOB REFERENCE: catalog failed: %s" % str(loaded.get("errors", [])))
		return false
	var generated := JobGenerator.generate(loaded["catalog"], "job_recycling_sorter", 19800901, 2)
	if not bool(generated.get("ok", false)):
		push_error("M3F.4 JOB REFERENCE: generation failed: %s" % str(generated.get("errors", [])))
		return false
	var snapshot: Dictionary = generated["snapshot"]
	var started := JobService.start(snapshot)
	if not bool(started.get("ok", false)):
		push_error("M3F.4 JOB REFERENCE: shift did not start")
		return false
	var progress: Dictionary = started["progress"]
	var profile := {
		"characteristics": {"strength": 6, "charisma": 4, "intelligence": 7, "luck": 1},
		"skills": {"cargo_handling": 1, "repair": 1, "search": 1, "trade": 0},
	}
	var first_preview := JobService.preview(snapshot, progress, profile)
	var first_choice := String(Dictionary(Array(first_preview.get("choices", []))[1]).get("id", ""))
	var first_result := JobService.resolve_step(snapshot, progress, first_choice, profile)
	if not bool(first_result.get("ok", false)):
		push_error("M3F.4 JOB REFERENCE: first step failed")
		return false
	progress = first_result["progress"]
	_active_model = JobViewModel.build({
		"snapshot": snapshot,
		"progress": progress,
		"current_step": JobService.preview(snapshot, progress, profile),
		"quick_resolve": {
			"eligible": true,
			"title": "Рассчитать знакомые операции",
			"description": "Освоенные действия можно рассчитать без повторения уже знакомой рутины.",
		},
		"expected_revision": 41,
	}, true)
	while String(progress.get("status", "")) != "completed":
		var preview := JobService.preview(snapshot, progress, profile)
		var choices: Array = preview.get("choices", [])
		var choice_id := String(Dictionary(choices[mini(1, choices.size() - 1)]).get("id", ""))
		var resolved := JobService.resolve_step(snapshot, progress, choice_id, profile)
		if not bool(resolved.get("ok", false)):
			push_error("M3F.4 JOB REFERENCE: completion failed")
			return false
		progress = resolved["progress"]
	var settlement := Dictionary(progress.get("result", {})).duplicate(true)
	settlement["payout_ard"] = 224
	settlement["mastery_awarded"] = 2
	settlement["summary"] = "Мартин принял работу и отметил аккуратное обращение с площадкой."
	_result_model = JobViewModel.build({
		"snapshot": snapshot,
		"progress": progress,
		"result": settlement,
		"expected_revision": 44,
	}, true)
	return true


func _capture(size: Vector2i, state: String, model: Dictionary) -> Error:
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
	var screen := JobScreenScene.instantiate() as JobScreen
	if screen == null:
		return ERR_CANT_CREATE
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(screen)
	screen.present(model)
	for _frame: int in 12:
		await process_frame
	var image := viewport.get_texture().get_image()
	var result := ERR_CANT_CREATE if image == null or image.is_empty() else image.save_png(
		"%s/job_shift_%s_%dx%d.png" % [OutputDir, state, size.x, size.y]
	)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame
	return result
