class_name ToastOverlay
extends Control

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
	_timer.start(4.2 if is_error else 3.2)
	if _reduced_motion:
		return
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.18)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_panel.modulate = Color.WHITE


func _hide() -> void:
	if not _panel.visible:
		return
	if _reduced_motion:
		_panel.visible = false
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.16)
	_tween.tween_callback(func() -> void: _panel.visible = false)
