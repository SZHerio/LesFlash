class_name JobScreen
extends Control

signal choice_requested(choice_id: String, expected_revision: int)
signal quick_resolve_requested(expected_revision: int)

const ActionRowScene := preload("res://ui/components/action_row.tscn")
const Motion := preload("res://ui/theme/motion.gd")
const Palette := preload("res://ui/theme/palette.gd")

@onready var _work_icon: SemanticIcon = %WorkIcon
@onready var _title: Label = %TitleLabel
@onready var _supervisor: Label = %SupervisorLabel
@onready var _briefing_title: Label = %BriefingTitle
@onready var _briefing_text: Label = %BriefingText
@onready var _shift_meta: DecisionCostRow = %ShiftMeta
@onready var _progress_label: Label = %ProgressLabel
@onready var _progress_detail: Label = %ProgressDetail
@onready var _progress_track: Control = %ProgressTrack
@onready var _progress_fill: ColorRect = %ProgressFill
@onready var _production: JobMetricCard = %ProductionMetric
@onready var _quality: JobMetricCard = %QualityMetric
@onready var _safety: JobMetricCard = %SafetyMetric
@onready var _step_panel: PanelContainer = %StepPanel
@onready var _step_icon: SemanticIcon = %StepIcon
@onready var _step_eyebrow: Label = %StepEyebrow
@onready var _step_title: Label = %StepTitle
@onready var _step_description: Label = %StepDescription
@onready var _choices_title: Label = %ChoicesTitle
@onready var _choice_list: VBoxContainer = %ChoiceList
@onready var _no_choices: Label = %NoChoices
@onready var _quick_panel: PanelContainer = %QuickPanel
@onready var _quick_icon: SemanticIcon = %QuickIcon
@onready var _quick_description: Label = %QuickDescription
@onready var _quick_button: Button = %QuickButton
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_icon: SemanticIcon = %ResultIcon
@onready var _result_title: Label = %ResultTitle
@onready var _result_grade: Label = %ResultGrade
@onready var _result_summary: Label = %ResultSummary
@onready var _result_overall: Label = %ResultOverall
@onready var _result_payout: Label = %ResultPayout
@onready var _result_mastery: Label = %ResultMastery

var _model: Dictionary = {}
var _expected_revision := 0
var _awaiting_result := false
var _reduced_motion := false
var _progress_value := 0.0
var _progress_target := 0.0
var _progress_tween: Tween
var _reveal_tween: Tween
var _choice_rows: Dictionary = {}


func _ready() -> void:
	_work_icon.present(&"action_work", 32, Palette.GOLD)
	_quick_icon.present(&"action_work", 24, Palette.GREEN_BRIGHT)
	_result_icon.present(&"action_work", 32, Palette.GREEN_BRIGHT)
	_progress_track.resized.connect(_sync_progress_fill)
	_quick_button.pressed.connect(_request_quick_resolve)
	_apply_model()


func apply_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_node_ready():
		_apply_model()


func present(model: Dictionary) -> void:
	apply_model(model)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	for card: JobMetricCard in [_production, _quality, _safety]:
		card.set_reduced_motion(enabled)
	for child: Node in _choice_list.get_children():
		if child is ActionRow:
			(child as ActionRow).set_reduced_motion(enabled)
	if enabled:
		Motion.stop(_progress_tween)
		Motion.stop(_reveal_tween)
		_set_progress_value(_progress_target)
		_step_panel.modulate = Color.WHITE


func _apply_model() -> void:
	_awaiting_result = false
	_expected_revision = int(_model.get("expected_revision", _model.get("revision", 0)))
	_reduced_motion = bool(_model.get("reduced_motion", false))
	_title.text = _visible_text(_model.get("title", "Сортировщик вторсырья"), "Сортировщик вторсырья")
	_supervisor.text = _visible_text(_model.get("supervisor_text", "Мастер смены"), "Мастер смены")
	_briefing_title.text = _visible_text(_model.get("briefing_title", "Рабочая смена"), "Рабочая смена")
	_briefing_text.text = _visible_text(_model.get("briefing_text", "Подготовьтесь к задачам смены."), "Подготовьтесь к задачам смены.")
	# DecisionCostRow takes Array[Dictionary]. Passing a bare Array threw at
	# runtime and the shift's cost tokens simply never drew.
	var meta_tokens: Array[Dictionary] = []
	for raw_token: Variant in Array(_model.get("shift_meta_tokens", [])):
		if raw_token is Dictionary:
			meta_tokens.append(raw_token)
	_shift_meta.present(meta_tokens)
	_present_progress(Dictionary(_model.get("progress", {})))
	_present_metrics(Array(_model.get("metrics", [])))
	_present_result(Dictionary(_model.get("result", {})))
	_present_current_step(Dictionary(_model.get("current_step", {})))
	_present_quick_resolve(Dictionary(_model.get("quick_resolve", {})))
	set_reduced_motion(_reduced_motion)


func _present_progress(model: Dictionary) -> void:
	_progress_label.text = _visible_text(model.get("label", "Смена"), "Смена")
	_progress_detail.text = _visible_text(model.get("detail", ""))
	_progress_detail.visible = not _progress_detail.text.is_empty()
	_progress_target = clampf(float(model.get("fraction", 0.0)), 0.0, 1.0)
	_progress_tween = Motion.play_method(
		_progress_tween,
		self,
		_set_progress_value,
		_progress_value,
		_progress_target,
		Motion.meter_duration(_progress_target - _progress_value, 1.0),
		_reduced_motion
	)


func _present_metrics(models: Array) -> void:
	var by_id: Dictionary = {}
	for raw: Variant in models:
		if raw is Dictionary:
			by_id[StringName(Dictionary(raw).get("id", &""))] = Dictionary(raw)
	for entry: Dictionary in [
		{"id": &"production", "card": _production},
		{"id": &"quality", "card": _quality},
		{"id": &"safety", "card": _safety},
	]:
		var metric_id: StringName = entry["id"]
		var card: JobMetricCard = entry["card"]
		var model := Dictionary(by_id.get(metric_id, {
			"id": metric_id,
			"label": "Показатель",
			"value": 50,
		})).duplicate(true)
		model["colour"] = _metric_colour(metric_id, int(model.get("value", 50)))
		card.present(model)


func _present_current_step(model: Dictionary) -> void:
	_choice_rows.clear()
	for child: Node in _choice_list.get_children():
		_choice_list.remove_child(child)
		child.queue_free()
	var visible := not model.is_empty() and not _result_panel.visible
	_step_panel.visible = visible
	_choices_title.visible = visible
	_choice_list.visible = visible
	_no_choices.visible = false
	if not visible:
		return
	_step_icon.present(
		StringName(model.get("icon_id", &"action_work")),
		32,
		Palette.GOLD
	)
	_step_eyebrow.text = _visible_text(model.get("eyebrow", "ЗАДАЧА СМЕНЫ"), "ЗАДАЧА СМЕНЫ")
	_step_title.text = _visible_text(model.get("title", "Текущая задача"), "Текущая задача")
	_step_description.text = _visible_text(model.get("description", "Выберите способ работы."), "Выберите способ работы.")
	for raw_choice: Variant in Array(model.get("choices", [])):
		if not raw_choice is Dictionary:
			continue
		var row := ActionRowScene.instantiate() as ActionRow
		if row == null:
			continue
		_choice_list.add_child(row)
		row.set_reduced_motion(_reduced_motion)
		row.present(raw_choice)
		row.action_requested.connect(_request_choice)
		var choice_id := String(Dictionary(raw_choice).get("id", ""))
		if not choice_id.is_empty():
			_choice_rows[choice_id] = row
	_no_choices.visible = _choice_list.get_child_count() == 0
	_choice_list.visible = not _no_choices.visible
	_step_panel.modulate = Color(1, 1, 1, 0)
	_reveal_tween = Motion.play(_reveal_tween, self, [{
		"target": _step_panel,
		"property": "modulate",
		"to": Color.WHITE,
		"duration": Motion.REVEAL,
	}], _reduced_motion)


func _present_quick_resolve(model: Dictionary) -> void:
	var visible := bool(model.get("visible", false)) and not _result_panel.visible
	_quick_panel.visible = visible
	if not visible:
		return
	_quick_description.text = _visible_text(model.get("description", ""))
	_quick_description.visible = not _quick_description.text.is_empty()
	_quick_button.text = _visible_text(model.get("title", "Рассчитать освоенную смену"), "Рассчитать освоенную смену")
	_quick_button.disabled = not bool(model.get("enabled", true))
	_quick_button.accessibility_name = _quick_button.text


func _present_result(model: Dictionary) -> void:
	_result_panel.visible = bool(model.get("visible", false))
	if not _result_panel.visible:
		return
	_result_title.text = _visible_text(model.get("title", "Смена завершена"), "Смена завершена")
	_result_grade.text = _visible_text(model.get("grade", "Смена завершена"), "Смена завершена")
	_result_summary.text = _visible_text(model.get("summary", "Результат внесён в журнал."), "Результат внесён в журнал.")
	_result_overall.text = _visible_text(model.get("overall_text", ""))
	_result_payout.text = _visible_text(model.get("payout_text", ""))
	_result_mastery.text = _visible_text(model.get("mastery_text", ""))
	for label: Label in [_result_overall, _result_payout, _result_mastery]:
		label.visible = not label.text.is_empty()


func _request_choice(choice_id: String) -> void:
	if _awaiting_result or choice_id.strip_edges().is_empty():
		return
	_lock_inputs(choice_id)
	choice_requested.emit(choice_id, _expected_revision)


func _request_quick_resolve() -> void:
	if _awaiting_result or _quick_button.disabled or not _quick_panel.visible:
		return
	_lock_inputs("")
	_quick_button.text = "Расчёт отправлен…"
	quick_resolve_requested.emit(_expected_revision)


func _lock_inputs(selected_choice_id: String) -> void:
	_awaiting_result = true
	_quick_button.disabled = true
	for child: Node in _choice_list.get_children():
		if child is ActionRow:
			var row := child as ActionRow
			row.set_pending_feedback(row == _choice_rows.get(selected_choice_id))
			row.disabled = true


func _set_progress_value(value: float) -> void:
	_progress_value = clampf(value, 0.0, 1.0)
	_sync_progress_fill()


func _sync_progress_fill() -> void:
	if not is_instance_valid(_progress_track) or not is_instance_valid(_progress_fill):
		return
	_progress_fill.position = Vector2.ZERO
	_progress_fill.size = Vector2(_progress_track.size.x * _progress_value, _progress_track.size.y)


static func _metric_colour(metric_id: StringName, value: int) -> Color:
	match metric_id:
		&"production":
			return Palette.GOLD
		&"quality":
			return Palette.BLUE
		&"safety":
			return Palette.DANGER if value < 35 else Palette.GREEN_BRIGHT
		_:
			return Palette.GREEN_BRIGHT


static func _visible_text(value: Variant, fallback: String = "") -> String:
	var text := String(value).strip_edges()
	return fallback if text.is_empty() else text
