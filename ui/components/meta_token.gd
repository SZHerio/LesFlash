class_name MetaToken
extends HBoxContainer

## One compact, readable fact such as "6 мин" or "Низкий риск". The model
## supplies semantics explicitly; this component never parses its text.

const ICON_SIZE := 16

@onready var _icon: SemanticIcon = %Icon
@onready var _label: Label = %Text

var _model: Dictionary = {}


func _ready() -> void:
	_apply_model()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_icon()


func present(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_node_ready():
		_apply_model()


func _apply_model() -> void:
	var display_text := String(_model.get("text", "")).strip_edges()
	if display_text.is_empty():
		_label.text = ""
		_icon.clear()
		accessibility_name = ""
		set_meta(&"accessible_text", "")
		visible = false
		return
	_label.text = display_text
	var accessible_text := String(_model.get("accessible_text", "")).strip_edges()
	accessibility_name = display_text if accessible_text.is_empty() else accessible_text
	set_meta(
		&"accessible_text",
		accessibility_name
	)
	visible = true
	_apply_icon()


func _apply_icon() -> void:
	var next_icon_id := StringName(_model.get("icon_id", &""))
	if next_icon_id.is_empty():
		_icon.clear()
		return
	_icon.present(next_icon_id, ICON_SIZE, _label.get_theme_color(&"font_color"))
