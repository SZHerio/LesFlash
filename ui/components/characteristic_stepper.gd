class_name CharacteristicStepper
extends PanelContainer

signal delta_requested(characteristic_id: String, delta: int)

@onready var _title_label: Label = %TitleLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _value_label: Label = %ValueLabel
@onready var _minus_button: Button = %MinusButton
@onready var _plus_button: Button = %PlusButton

var _characteristic_id := ""
var _value := 1
var _reduced_motion := false
var _value_tween: Tween


func _ready() -> void:
	_minus_button.pressed.connect(_request_delta.bind(-1))
	_plus_button.pressed.connect(_request_delta.bind(1))


func present(model: Dictionary) -> void:
	_characteristic_id = String(model.get("id", ""))
	_title_label.text = String(model.get("title", _characteristic_id))
	_description_label.text = String(model.get("description", ""))
	var next_value := int(model.get("value", 1))
	var changed := next_value != _value
	_value = next_value
	_value_label.text = str(_value)
	_minus_button.disabled = not bool(model.get("can_decrease", true))
	_plus_button.disabled = not bool(model.get("can_increase", true))
	if changed and not _reduced_motion and is_inside_tree():
		if _value_tween != null and _value_tween.is_valid():
			_value_tween.kill()
		_value_label.pivot_offset = _value_label.size * 0.5
		_value_label.scale = Vector2(0.82, 0.82)
		_value_tween = create_tween()
		_value_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_value_tween.tween_property(_value_label, "scale", Vector2.ONE, 0.18)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		if _value_tween != null and _value_tween.is_valid():
			_value_tween.kill()
		_value_label.scale = Vector2.ONE


func _request_delta(delta: int) -> void:
	if _characteristic_id.is_empty():
		return
	delta_requested.emit(_characteristic_id, delta)
