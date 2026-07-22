class_name SettingsScreen
extends Control

signal back_requested
signal preference_changed(key: String, value: Variant)

@onready var _locked_toggle: CheckButton = %LockedToggle
@onready var _motion_toggle: CheckButton = %MotionToggle
@onready var _psyche_option: OptionButton = %PsycheOption
@onready var _font_option: OptionButton = %FontOption

var _presenting := false


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: back_requested.emit())
	_locked_toggle.toggled.connect(_on_toggle.bind("show_locked_options"))
	_motion_toggle.toggled.connect(_on_toggle.bind("reduced_motion"))
	_psyche_option.item_selected.connect(_on_option_selected.bind(_psyche_option, "psyche_effect_mode"))
	_font_option.item_selected.connect(_on_option_selected.bind(_font_option, "font_scale"))


func present(model: Dictionary) -> void:
	_presenting = true
	_locked_toggle.button_pressed = bool(model.get("show_locked_options", false))
	_motion_toggle.button_pressed = bool(model.get("reduced_motion", false))
	_select_metadata(_psyche_option, String(model.get("psyche_effect_mode", "full")))
	_select_metadata(_font_option, float(model.get("font_scale", 1.0)))
	_presenting = false


func set_reduced_motion(_enabled: bool) -> void:
	pass


func _on_toggle(enabled: bool, key: String) -> void:
	if not _presenting:
		preference_changed.emit(key, enabled)


func _on_option_selected(index: int, option: OptionButton, key: String) -> void:
	if not _presenting:
		preference_changed.emit(key, option.get_item_metadata(index))


func _select_metadata(option: OptionButton, value: Variant) -> void:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return
