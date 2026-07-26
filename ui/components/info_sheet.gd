class_name InfoSheet
extends Control

## Explanation panel for a control the player tapped to understand.
##
## It carries reference text only and never a decision, so dismissing it can
## never cost anything. Progressive disclosure: the screen behind it shows the
## choice, this shows what the choice means.

const Motion := preload("res://ui/theme/motion.gd")
signal dismissed

@onready var _panel: PanelContainer = %SheetPanel
@onready var _title: Label = %Title
@onready var _body: Label = %Body

var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	%BackdropButton.pressed.connect(close)
	%Close.pressed.connect(close)
	visible = false


func present(title: String, body: String, reduced_motion: bool = false) -> void:
	_reduced_motion = reduced_motion
	_title.text = title
	_body.text = body
	visible = true
	_animate_open()


func close() -> void:
	if not visible:
		return
	visible = false
	_panel.position.y = 0.0
	_panel.modulate = Color.WHITE
	dismissed.emit()


func is_open() -> bool:
	return visible


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_panel.position.y = 0.0
		_panel.modulate = Color.WHITE


func _animate_open() -> void:
	_panel.position.y = 16.0
	_panel.modulate = Color(1, 1, 1, 0)
	_tween = Motion.play(_tween, self, [
		{"target": _panel, "property": "position:y", "to": 0.0, "duration": Motion.SHEET},
		{"target": _panel, "property": "modulate", "to": Color.WHITE, "duration": Motion.FADE},
	], _reduced_motion)
