class_name MainMenuScreen
extends Control

signal new_game_requested
signal continue_requested
signal settings_requested
signal quit_requested

@onready var _continue_button: Button = %ContinueButton
@onready var _autosave_label: Label = %AutosaveLabel
@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	%NewGameButton.pressed.connect(func() -> void: new_game_requested.emit())
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	%SettingsButton.pressed.connect(func() -> void: settings_requested.emit())
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())
	resized.connect(_sync_scroll_height)
	call_deferred("_sync_scroll_height")


func present(model: Dictionary) -> void:
	var can_continue := bool(model.get("can_continue", false))
	_continue_button.disabled = not can_continue
	_continue_button.text = "Продолжить"
	_continue_button.tooltip_text = "" if can_continue else "Нет сохранённой жизни"
	_autosave_label.visible = bool(model.get("show_autosave", false))
	_autosave_label.text = String(model.get("autosave_text", "Автосохранение включено"))


func set_reduced_motion(_enabled: bool) -> void:
	pass


func _sync_scroll_height() -> void:
	_content.custom_minimum_size.y = maxf(size.y, 0.0)
