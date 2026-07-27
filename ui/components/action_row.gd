class_name ActionRow
extends Button

signal action_requested(action_id: String)

const Palette = preload("res://ui/theme/palette.gd")
const Motion := preload("res://ui/theme/motion.gd")

@onready var _accent_rail: ColorRect = %AccentRail
@onready var _content: HBoxContainer = $Content
@onready var _category_icon: SemanticIcon = %CategoryIcon
@onready var _title_label: Label = %TitleLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _meta_row: DecisionCostRow = %MetaRow
@onready var _reason_label: Label = %ReasonLabel
@onready var _trailing_icon: SemanticIcon = %TrailingIcon

var _action_id: StringName
var _reduced_motion := false
var _motion_tween: Tween
var _pending_feedback := false


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
	_pending_feedback = false
	_action_id = StringName(model.get("id", &""))
	_title_label.text = String(model.get("title", "Действие"))
	_description_label.text = String(model.get("description", ""))
	_description_label.visible = not _description_label.text.is_empty()

	_meta_row.present(_meta_tokens(model))

	disabled = not bool(model.get("enabled", true))
	_reason_label.text = String(model.get("locked_reason", ""))
	_reason_label.visible = disabled and not _reason_label.text.is_empty()

	var variant := StringName(model.get("variant", &"normal"))
	var icon_colour := Palette.GOLD
	match variant:
		&"accent":
			theme_type_variation = &"ActionButtonAccent"
			_accent_rail.color = Palette.GREEN_BRIGHT
			icon_colour = Palette.GREEN_BRIGHT
		&"danger":
			theme_type_variation = &"ActionButtonDanger"
			_accent_rail.color = Palette.DANGER
			icon_colour = Palette.DANGER
		_:
			theme_type_variation = &"ActionButton"
			_accent_rail.color = Palette.GOLD if not disabled else Palette.FAINT
			icon_colour = Palette.GOLD
	if disabled:
		icon_colour = Palette.FAINT
	_category_icon.present(
		StringName(model.get("category_icon_id", &"action_observe")),
		32,
		icon_colour
	)
	_trailing_icon.present(
		&"utility_locked" if disabled else &"utility_chevron_right",
		20 if disabled else 16,
		Palette.FAINT if disabled else Palette.TEXT
	)
	# No tooltip: both texts are already on the card. On a touch device a tooltip
	# needs a long press and then covers the very thing it was called about.
	call_deferred("_update_minimum_height")


func set_pending_feedback(enabled: bool) -> void:
	_pending_feedback = enabled
	if not enabled:
		return
	_meta_row.present([{
		"icon_id": &"meta_time",
		"text": "Отправлено…",
		"accessible_text": "Решение отправлено, ожидается результат",
	}])
	_trailing_icon.present(&"meta_time", 16, Palette.GOLD)
	_accent_rail.color = Palette.GOLD
	accessibility_name = "%s. Решение отправлено, ожидается результат" % _title_label.text
	call_deferred("_update_minimum_height")


func is_pending_feedback() -> bool:
	return _pending_feedback


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
	for control in [_description_label, _meta_row, _reason_label]:
		if control.visible:
			copy_height += control.get_combined_minimum_size().y + 3.0
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


func _meta_tokens(model: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen_text: Dictionary = {}
	var typed: Variant = model.get("meta_tokens", [])
	if typed is Array:
		for raw_token: Variant in typed:
			if not raw_token is Dictionary:
				continue
			var token: Dictionary = Dictionary(raw_token).duplicate(true)
			var token_text := String(token.get("text", "")).strip_edges()
			if token_text.is_empty() or seen_text.has(token_text):
				continue
			seen_text[token_text] = true
			result.append(token)
	for mapping: Dictionary in [
		{"key": "time_text", "icon_id": &"meta_time"},
		{"key": "cost_text", "icon_id": &"currency_arden_compact"},
		{"key": "energy_text", "icon_id": &"meta_energy"},
		{"key": "risk_text", "icon_id": &"meta_risk"},
	]:
		var text := String(model.get(mapping["key"], "")).strip_edges()
		if text.is_empty() or seen_text.has(text):
			continue
		seen_text[text] = true
		result.append({
			"icon_id": mapping["icon_id"],
			"text": text,
			"accessible_text": text,
		})
	for raw_text: Variant in Array(model.get("meta", [])):
		var text := String(raw_text).strip_edges()
		if text.is_empty() or seen_text.has(text):
			continue
		seen_text[text] = true
		result.append({"icon_id": &"", "text": text, "accessible_text": text})
	return result
