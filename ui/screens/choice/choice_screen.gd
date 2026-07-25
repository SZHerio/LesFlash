class_name ChoiceScreen
extends Control

signal action_requested(action_id: String)
signal settings_requested
signal leave_requested

const ActionRowScene := preload("res://ui/components/action_row.tscn")

@onready var _eyebrow_label: Label = %EyebrowLabel
@onready var _title_label: Label = %TitleLabel
@onready var _context_label: Label = %ContextLabel
@onready var _body_label: Label = %BodyLabel
@onready var _section_label: Label = %SectionLabel
@onready var _options: VBoxContainer = %Options
@onready var _progress_card: PanelContainer = %ProgressCard
@onready var _progress_label: Label = %ProgressLabel
@onready var _progress_value: ProgressBar = %ProgressValue
@onready var _bottom_bar: HBoxContainer = %BottomBar
@onready var _leave_button: Button = %LeaveButton

var _reduced_motion := false


func _ready() -> void:
	%SettingsButton.pressed.connect(func() -> void: settings_requested.emit())
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())


func present(model: Dictionary) -> void:
	_eyebrow_label.text = String(model.get("eyebrow", "СИТУАЦИЯ"))
	_title_label.text = String(model.get("title", "Что произошло"))
	_context_label.text = String(model.get("context", ""))
	_context_label.visible = not _context_label.text.is_empty()
	_body_label.text = String(model.get("body", ""))
	_section_label.text = String(model.get("section_title", "Ваше решение"))
	_present_progress(model.get("progress", {}))
	_present_exit(String(model.get("leave_text", "")))
	for child in _options.get_children():
		child.queue_free()
	for raw_option in Array(model.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var row := ActionRowScene.instantiate() as ActionRow
		_options.add_child(row)
		row.set_reduced_motion(_reduced_motion)
		row.present(Dictionary(raw_option))
		row.action_requested.connect(func(action_id: StringName) -> void:
			action_requested.emit(String(action_id))
		)


## A card whose options can all be closed at once must offer a way out, or the
## player is stuck looking at a list of things they cannot do. Cards that always
## keep an available answer — events, encounters, a job round — leave this empty
## on purpose, because walking out of a decision is not the same as leaving a
## list of shelters that are all shut until evening.
func _present_exit(leave_text: String) -> void:
	_bottom_bar.visible = not leave_text.is_empty()
	_leave_button.text = leave_text


func has_exit() -> bool:
	return _bottom_bar.visible


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	for child in _options.get_children():
		if child.has_method("set_reduced_motion"):
			child.call("set_reduced_motion", enabled)


func _present_progress(value: Variant) -> void:
	if not value is Dictionary or value.is_empty():
		_progress_card.visible = false
		return
	var progress: Dictionary = value
	_progress_card.visible = true
	_progress_label.text = String(progress.get("label", "Прогресс"))
	_progress_value.max_value = maxf(float(progress.get("maximum", 1.0)), 1.0)
	_progress_value.value = clampf(float(progress.get("value", 0.0)), 0.0, _progress_value.max_value)
