class_name InventoryCapacityCard
extends PanelContainer

const Motion := preload("res://ui/theme/motion.gd")
@onready var _icon: Label = %IconLabel
@onready var _title: Label = %TitleLabel
@onready var _value: Label = %ValueLabel
@onready var _bar: ProgressBar = %CapacityBar
@onready var _state: Label = %StateLabel

var _reduced_motion := false
var _tween: Tween


func present(model: Dictionary) -> void:
	_icon.text = String(model.get("icon", "•"))
	_title.text = String(model.get("title", "Вместимость"))
	_value.text = String(model.get("value_text", "0 / 0"))
	var ratio := clampf(float(model.get("ratio", 0.0)), 0.0, 1.0)
	var state := String(model.get("state", "normal"))
	_state.text = (
		"ПЕРЕГРУЗ"
		if state == "overload"
		else ("ПОЧТИ ПОЛНО" if state == "warning" else "СВОБОДНО")
	)
	_state.modulate = (
		Color(0.96, 0.48, 0.38)
		if state == "overload"
		else (Color(0.95, 0.73, 0.34) if state == "warning" else Color(0.55, 0.82, 0.64))
	)
	var target := ratio * 100.0
	_tween = Motion.play(_tween, self, [{
		"target": _bar,
		"property": "value",
		"to": target,
		"duration": Motion.meter_duration(target - float(_bar.value)),
	}], _reduced_motion)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
