class_name CharacteristicStepper
extends HBoxContainer

## One characteristic as a single row: name, value, and the two controls that
## change it.
##
## The description lives behind the name rather than in the row, so four
## characteristics and their budget fit on one screen instead of turning the
## first decision of a run into a scroll.

signal delta_requested(characteristic_id: String, delta: int)
signal description_requested(characteristic_id: String)

@onready var _name_button: Button = %NameButton
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
	_name_button.pressed.connect(func() -> void:
		if not _characteristic_id.is_empty():
			description_requested.emit(_characteristic_id)
	)


func present(model: Dictionary) -> void:
	_characteristic_id = String(model.get("id", ""))
	_name_button.text = String(model.get("title", _characteristic_id))
	var next_value := int(model.get("value", 1))
	var changed := next_value != _value
	_value = next_value
	_value_label.text = str(_value)
	_minus_button.disabled = not bool(model.get("can_decrease", true))
	_plus_button.disabled = not bool(model.get("can_increase", true))
	if changed and not _reduced_motion and is_inside_tree():
		_animate_value()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		if _value_tween != null and _value_tween.is_valid():
			_value_tween.kill()
		_value_label.scale = Vector2.ONE


## The value settles, it does not bounce: overshoot is the wrong voice for this
## game, and it is barred by the motion rules.
func _animate_value() -> void:
	if _value_tween != null and _value_tween.is_valid():
		_value_tween.kill()
	_value_label.pivot_offset = _value_label.size * 0.5
	_value_label.scale = Vector2(0.88, 0.88)
	_value_tween = create_tween()
	_value_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_value_tween.tween_property(_value_label, "scale", Vector2.ONE, 0.16)


func _request_delta(delta: int) -> void:
	if _characteristic_id.is_empty():
		return
	delta_requested.emit(_characteristic_id, delta)
