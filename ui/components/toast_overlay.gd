class_name ToastOverlay
extends Control

const Motion := preload("res://ui/theme/motion.gd")
@onready var _panel: PanelContainer = %ToastPanel
@onready var _label: Label = %ToastLabel
@onready var _timer: Timer = %HideTimer

var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer.timeout.connect(_hide)


func show_message(message: String, is_error: bool = false) -> void:
	if message.strip_edges().is_empty():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.text = message
	_panel.theme_type_variation = &"ToastErrorPanel" if is_error else &"ToastPanel"
	_panel.visible = true
	_panel.modulate = Color.WHITE
	_timer.start(Motion.TOAST_DWELL_ERROR if is_error else Motion.TOAST_DWELL)
	_panel.modulate.a = 0.0
	_tween = Motion.play(_tween, self, [
		{"target": _panel, "property": "modulate:a", "to": 1.0, "duration": Motion.FADE},
	], _reduced_motion)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_panel.modulate = Color.WHITE


func _hide() -> void:
	if not _panel.visible:
		return
	_tween = Motion.play(_tween, self, [
		{"target": _panel, "property": "modulate:a", "to": 0.0, "duration": Motion.FADE},
	], _reduced_motion, Motion.Shape.EXIT)
	if _tween == null:
		_panel.visible = false
	else:
		_tween.tween_callback(func() -> void: _panel.visible = false)
