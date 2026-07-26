class_name InventoryItemCard
extends PanelContainer

const Motion := preload("res://ui/theme/motion.gd")
signal selected(stack_id: String)
signal action_requested(stack_id: String, action_id: String, action_model: Dictionary)

@onready var _header: Button = %HeaderButton
@onready var _title: Label = %TitleLabel
@onready var _quantity: Label = %QuantityLabel
@onready var _location: Label = %LocationLabel
@onready var _summary: Label = %SummaryLabel
@onready var _chevron: Label = %ChevronLabel
@onready var _details: VBoxContainer = %Details
@onready var _description: Label = %DescriptionLabel
@onready var _tags: Label = %TagsLabel
@onready var _condition: Label = %ConditionLabel
@onready var _actions: HFlowContainer = %Actions

var _model: Dictionary = {}
var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	_header.pressed.connect(func() -> void:
		selected.emit(String(_model.get("stack_id", "")))
	)


func present(model: Dictionary, expanded: bool) -> void:
	_model = model.duplicate(true)
	_title.text = String(model.get("title", "Предмет"))
	_quantity.text = String(model.get("quantity_text", ""))
	_quantity.visible = not _quantity.text.is_empty()
	_location.text = String(model.get("container_title", ""))
	_summary.text = "%s  ·  %s" % [
		String(model.get("mass_text", "0 г")),
		String(model.get("volume_text", "0 мл")),
	]
	_description.text = String(model.get("description", ""))
	var tags := PackedStringArray()
	for tag in Array(model.get("tags", [])):
		tags.append(String(tag))
	_tags.text = "  ·  ".join(tags)
	_tags.visible = not tags.is_empty()
	_condition.text = String(model.get("condition_text", "Состояние неизвестно"))
	if bool(model.get("unknown_fallback", false)):
		_condition.text += "  ·  сохранено из старой версии"
	_build_actions(Array(model.get("actions", [])))
	_set_expanded(expanded, false)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_details.modulate = Color.WHITE


func stack_id() -> String:
	return String(_model.get("stack_id", ""))


func is_expanded() -> bool:
	return _details.visible


func _build_actions(raw_actions: Array) -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	for raw_action in raw_actions:
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 48)
		button.text = String(action.get("title", "Действовать"))
		match String(action.get("kind", "")):
			"danger":
				button.theme_type_variation = &"ActionButtonDanger"
			"accent":
				button.theme_type_variation = &"ActionButtonAccent"
			_:
				button.theme_type_variation = &"SecondaryButton"
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func() -> void:
			action_requested.emit(
				String(_model.get("stack_id", "")),
				String(action.get("id", "")),
				action.duplicate(true)
			)
		)
		_actions.add_child(button)
	_actions.visible = _actions.get_child_count() > 0


func _set_expanded(expanded: bool, animate: bool) -> void:
	_details.visible = expanded
	_chevron.text = "⌃" if expanded else "⌄"
	theme_type_variation = &"StatusDetailPanel" if expanded else &"SurfaceCard"
	_details.modulate = Color(1, 1, 1, 0)
	_tween = Motion.play(_tween, self, [
		{"target": _details, "property": "modulate", "to": Color.WHITE, "duration": Motion.REVEAL},
	], not expanded or not animate or _reduced_motion)
