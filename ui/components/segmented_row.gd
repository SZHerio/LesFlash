class_name SegmentedRow
extends HBoxContainer

## Horizontal choice between a handful of equal options.
##
## Replaces a dropdown for short lists: the whole choice is visible without
## opening anything, and picking costs one touch instead of two. The row never
## wraps — if the options stop fitting, the type steps down within the scale
## rather than the layout breaking into two lines.

signal option_selected(option_id: String)

const SegmentScene := preload("res://ui/components/segment_button.tscn")
const TokensScript := preload("res://ui/theme/tokens.gd")

## Below this width per option the row switches to the smaller type step.
const COMFORTABLE_OPTION_WIDTH := 96.0

var _options: Array = []
var _selected_id := ""


func _ready() -> void:
	add_theme_constant_override(&"separation", TokensScript.SPACE_HAIR)
	resized.connect(_apply_density)


func present(options: Array, selected_id: String) -> void:
	_options = options.duplicate(true)
	_selected_id = selected_id
	for child in get_children():
		child.queue_free()
	for raw_option: Variant in _options:
		if not raw_option is Dictionary:
			continue
		var segment := SegmentScene.instantiate() as SegmentButton
		add_child(segment)
		segment.chosen.connect(_on_chosen)
	_apply_density()


func selected_id() -> String:
	return _selected_id


## Holds the whole row while a command is in flight, without losing which
## option is chosen.
func set_locked(locked: bool) -> void:
	for child in get_children():
		var segment := child as SegmentButton
		if segment != null:
			segment.disabled = locked or not _option_enabled(segment.option_id())


func _option_enabled(option_id: String) -> bool:
	for raw_option: Variant in _options:
		if raw_option is Dictionary and String(raw_option.get("id", "")) == option_id:
			return bool(raw_option.get("enabled", true))
	return false


func select(option_id: String) -> void:
	if option_id == _selected_id:
		return
	_selected_id = option_id
	_apply_density()


func _on_chosen(option_id: String) -> void:
	if option_id == _selected_id:
		return
	_selected_id = option_id
	_apply_density()
	option_selected.emit(option_id)


func _apply_density() -> void:
	if not is_node_ready():
		return
	var count := get_child_count()
	if count == 0:
		return
	var per_option := size.x / float(count)
	var font_size := (
		TokensScript.TEXT_CAPTION
		if per_option < COMFORTABLE_OPTION_WIDTH
		else TokensScript.TEXT_SECONDARY
	)
	for index in range(count):
		var segment := get_child(index) as SegmentButton
		if segment == null or index >= _options.size():
			continue
		var model: Dictionary = _options[index]
		segment.present(model, String(model.get("id", "")) == _selected_id, font_size)
