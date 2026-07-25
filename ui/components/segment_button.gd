class_name SegmentButton
extends Button

## One option inside a segmented row.
##
## The selected segment is marked by weight and an accent rail, not by colour
## alone, so the choice stays readable for a colour-blind player and under the
## heaviest psyche filter.

signal chosen(option_id: String)

@onready var _glyph: Control = %Glyph
@onready var _label: Label = %Label

var _option_id := ""


func _ready() -> void:
	pressed.connect(func() -> void:
		if not _option_id.is_empty():
			chosen.emit(_option_id)
	)
	_ignore_child_mouse(self)


func present(model: Dictionary, selected: bool, font_size: int) -> void:
	_option_id = String(model.get("id", ""))
	_label.text = String(model.get("title", _option_id))
	_label.add_theme_font_size_override(&"font_size", font_size)
	var icon_id := String(model.get("icon", ""))
	_glyph.visible = not icon_id.is_empty()
	if _glyph.visible:
		_glyph.set_meta(&"icon_id", icon_id)
		_glyph.queue_redraw()
	disabled = not bool(model.get("enabled", true))
	theme_type_variation = &"SegmentButtonActive" if selected else &"SegmentButton"
	button_pressed = selected


func option_id() -> String:
	return _option_id


func _ignore_child_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_child_mouse(child)
