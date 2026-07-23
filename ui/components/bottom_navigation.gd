class_name BottomNavigation
extends PanelContainer

signal tab_requested(tab_id: String)

const TAB_IDS: Array[StringName] = [&"place", &"map", &"hero", &"items", &"tasks"]

@onready var _buttons: Array[Button] = [
	%PlaceButton,
	%MapButton,
	%HeroButton,
	%ItemsButton,
	%TasksButton,
]

var _active_tab: StringName = &"place"
var _reduced_motion := false
var _tweens: Dictionary = {}


func _ready() -> void:
	for index in range(_buttons.size()):
		var button := _buttons[index]
		var tab_id := TAB_IDS[index]
		button.pressed.connect(_on_tab_pressed.bind(tab_id))
		button.button_down.connect(_animate_button.bind(button, 0.95))
		button.button_up.connect(_animate_button.bind(button, 1.0))
		button.resized.connect(_update_pivot.bind(button))
		_update_pivot(button)
	_apply_active_style()


func present(model: Dictionary) -> void:
	_active_tab = StringName(model.get("active_tab", &"place"))
	var enabled_tabs: Dictionary = model.get("enabled_tabs", {}) if model.get("enabled_tabs", {}) is Dictionary else {}
	for index in range(_buttons.size()):
		var tab_id := TAB_IDS[index]
		_buttons[index].disabled = not bool(enabled_tabs.get(tab_id, enabled_tabs.get(String(tab_id), true)))
	_apply_active_style()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		for tween_value in _tweens.values():
			var tween := tween_value as Tween
			if tween != null and tween.is_valid():
				tween.kill()
		for button in _buttons:
			button.scale = Vector2.ONE
		_tweens.clear()


func _on_tab_pressed(tab_id: StringName) -> void:
	tab_requested.emit(String(tab_id))


func _apply_active_style() -> void:
	for index in range(_buttons.size()):
		_buttons[index].theme_type_variation = (
			&"BottomNavButtonActive" if TAB_IDS[index] == _active_tab else &"BottomNavButton"
		)


func _update_pivot(button: Button) -> void:
	button.pivot_offset = button.size * 0.5


func _animate_button(button: Button, target: float) -> void:
	if _reduced_motion or button.disabled:
		return
	var previous: Variant = _tweens.get(button)
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target, 0.09)
	_tweens[button] = tween
