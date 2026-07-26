class_name ActionRow
extends Button

signal action_requested(action_id: String)

const Palette = preload("res://ui/theme/palette.gd")
const Motion := preload("res://ui/theme/motion.gd")

@onready var _accent_rail: ColorRect = %AccentRail
@onready var _content: HBoxContainer = $Content
@onready var _title_label: Label = %TitleLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _meta_label: Label = %MetaLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _trailing_label: Label = %TrailingLabel

var _action_id: StringName
var _reduced_motion := false
var _motion_tween: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	button_down.connect(_animate_scale.bind(0.985))
	button_up.connect(_animate_scale.bind(1.0))
	mouse_entered.connect(_animate_scale.bind(1.008))
	mouse_exited.connect(_animate_scale.bind(1.0))
	resized.connect(_update_pivot)
	_ignore_child_mouse(self)
	_update_pivot()
	call_deferred("_update_minimum_height")


func present(model: Dictionary) -> void:
	_action_id = StringName(model.get("id", &""))
	_title_label.text = String(model.get("title", "Действие"))
	_description_label.text = String(model.get("description", ""))
	_description_label.visible = not _description_label.text.is_empty()

	var meta_parts: Array[String] = []
	if model.get("meta", []) is Array:
		for raw_part in model.get("meta", []):
			var part := String(raw_part)
			if not part.is_empty():
				meta_parts.append(part)
	for key in ["time_text", "cost_text", "energy_text", "risk_text"]:
		var part := String(model.get(key, ""))
		if not part.is_empty() and not meta_parts.has(part):
			meta_parts.append(part)
	_meta_label.text = "  ·  ".join(PackedStringArray(meta_parts))
	_meta_label.visible = not _meta_label.text.is_empty()

	disabled = not bool(model.get("enabled", true))
	_reason_label.text = String(model.get("locked_reason", ""))
	_reason_label.visible = disabled and not _reason_label.text.is_empty()
	_trailing_label.text = "—" if disabled else "›"

	var variant := StringName(model.get("variant", &"normal"))
	match variant:
		&"accent":
			theme_type_variation = &"ActionButtonAccent"
			_accent_rail.color = Palette.GREEN_BRIGHT
		&"danger":
			theme_type_variation = &"ActionButtonDanger"
			_accent_rail.color = Palette.DANGER
		_:
			theme_type_variation = &"ActionButton"
			_accent_rail.color = Palette.GOLD if not disabled else Palette.FAINT
	# No tooltip: both texts are already on the card. On a touch device a tooltip
	# needs a long press and then covers the very thing it was called about.
	call_deferred("_update_minimum_height")


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		if _motion_tween != null and _motion_tween.is_valid():
			_motion_tween.kill()
		scale = Vector2.ONE


func _on_pressed() -> void:
	if not disabled and not _action_id.is_empty():
		action_requested.emit(String(_action_id))


func _update_pivot() -> void:
	pivot_offset = size * 0.5
	call_deferred("_update_minimum_height")


func _update_minimum_height() -> void:
	if not is_instance_valid(_content):
		return
	var copy_height := _title_label.get_combined_minimum_size().y
	for label in [_description_label, _meta_label, _reason_label]:
		if label.visible:
			copy_height += label.get_combined_minimum_size().y + 3.0
	var needed := maxf(92.0, copy_height + 18.0)
	if absf(custom_minimum_size.y - needed) > 1.0:
		custom_minimum_size.y = needed


func _animate_scale(target: float) -> void:
	_motion_tween = Motion.press(_motion_tween, self, self, target, _reduced_motion or disabled)


func _ignore_child_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_child_mouse(child)
