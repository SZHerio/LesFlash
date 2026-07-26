class_name NavTabButton
extends Button

## One persistent navigation tab. The authored sign accelerates recognition;
## the Russian label remains the primary accessible name.

@onready var _icon: SemanticIcon = %Icon
@onready var _label: Label = %Label

var _icon_id: StringName = &""
var _label_text := ""


func _ready() -> void:
	text = ""
	_ignore_child_mouse(self)
	_sync_visuals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_sync_visuals()


func present(next_icon_id: StringName, label_text: String) -> void:
	_icon_id = next_icon_id
	_label_text = label_text.strip_edges()
	tooltip_text = ""
	accessibility_name = _label_text
	set_meta(&"accessible_text", _label_text)
	if is_node_ready():
		_sync_visuals()


func sync_state() -> void:
	if is_node_ready():
		_sync_visuals()


func _sync_visuals() -> void:
	_label.text = _label_text
	var colour_name := &"font_disabled_color" if disabled else &"font_color"
	var colour := get_theme_color(colour_name)
	_label.add_theme_color_override(&"font_color", colour)
	if _icon_id.is_empty():
		_icon.clear()
	else:
		_icon.present(_icon_id, 24, colour)


func _ignore_child_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_child_mouse(child)
