class_name JobMetricCard
extends PanelContainer

const Motion := preload("res://ui/theme/motion.gd")
const Palette := preload("res://ui/theme/palette.gd")

@onready var _label: Label = %MetricLabel
@onready var _value: Label = %MetricValue
@onready var _track: Control = %MetricTrack
@onready var _fill: ColorRect = %MetricFill

var _current_value := 50.0
var _target_value := 50.0
var _accent := Palette.GREEN_BRIGHT
var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	_track.resized.connect(_sync_fill)
	_sync_fill()


func present(model: Dictionary) -> void:
	var previous := _current_value
	_target_value = clampf(float(model.get("value", 50)), 0.0, 100.0)
	_label.text = String(model.get("label", "Показатель")).strip_edges()
	if _label.text.is_empty():
		_label.text = "Показатель"
	_accent = model.get("colour", Palette.GREEN_BRIGHT) as Color
	_fill.color = _accent
	accessibility_name = "%s: %d из 100" % [_label.text, int(round(_target_value))]
	_tween = Motion.play_method(
		_tween,
		self,
		_set_display_value,
		previous,
		_target_value,
		Motion.meter_duration(_target_value - previous),
		_reduced_motion
	)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		Motion.stop(_tween)
		_set_display_value(_target_value)


func displayed_value() -> int:
	return int(round(_current_value))


func _set_display_value(value: float) -> void:
	_current_value = clampf(value, 0.0, 100.0)
	_value.text = str(int(round(_current_value)))
	_sync_fill()


func _sync_fill() -> void:
	if not is_instance_valid(_track) or not is_instance_valid(_fill):
		return
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(
		maxf(_track.size.x * (_current_value / 100.0), 0.0),
		_track.size.y
	)
