class_name SegmentButton
extends Button

## One option inside a segmented row.
##
## The selected segment is marked by weight and an accent rail, not by colour
## alone, so the choice stays readable for a colour-blind player and under the
## heaviest psyche filter.

signal chosen(option_id: String)

const Palette := preload("res://ui/theme/palette.gd")

@onready var _glyph: SemanticIcon = %Glyph
@onready var _label: Label = %Label

var _option_id := ""
var _icon_id: StringName = &""
var _selected := false


func _ready() -> void:
	pressed.connect(func() -> void:
		if not _option_id.is_empty():
			chosen.emit(_option_id)
	)
	_ignore_child_mouse(self)


func present(model: Dictionary, selected: bool, font_size: int) -> void:
	_option_id = String(model.get("id", ""))
	_label.text = String(model.get("title", _option_id))
	accessibility_name = _label.text
	_label.add_theme_font_size_override(&"font_size", font_size)
	disabled = not bool(model.get("enabled", true))
	theme_type_variation = &"SegmentButtonActive" if selected else &"SegmentButton"
	button_pressed = selected
	_icon_id = StringName(model.get("icon_id", &""))
	_selected = selected
	_sync_icon()


func sync_state() -> void:
	_sync_icon()


func _sync_icon() -> void:
	if _icon_id.is_empty():
		_glyph.clear()
	else:
		_glyph.present(
			_icon_id,
			24,
			Palette.FAINT if disabled else Palette.GOLD if _selected else Palette.TEXT
		)


func option_id() -> String:
	return _option_id


func _ignore_child_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_child_mouse(child)
