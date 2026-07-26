class_name SemanticIconButton
extends Button

## A touch target whose only visual is an authored semantic icon. The caller
## still supplies a readable Russian name for tooltip/accessibility metadata.

@onready var _icon: SemanticIcon = %Icon

var _icon_id: StringName = &""
var _icon_size := 24
var _accessible_text := ""


func _ready() -> void:
	text = ""
	_sync_icon()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_sync_icon()


func present(
	next_icon_id: StringName,
	accessible_text: String,
	size_dp: int = 24
) -> void:
	_icon_id = next_icon_id
	_icon_size = size_dp
	_accessible_text = accessible_text.strip_edges()
	tooltip_text = _accessible_text
	accessibility_name = _accessible_text
	set_meta(&"accessible_text", _accessible_text)
	if is_node_ready():
		_sync_icon()


func _sync_icon() -> void:
	if _icon_id.is_empty():
		_icon.clear()
		return
	var colour_name := &"font_disabled_color" if disabled else &"font_color"
	_icon.present(_icon_id, _icon_size, get_theme_color(colour_name))
