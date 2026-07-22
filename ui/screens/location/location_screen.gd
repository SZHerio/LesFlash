class_name LocationScreen
extends Control

signal action_requested(action_id: String, action_model: Dictionary)
signal status_requested(status_id: String)
signal settings_requested

const ActionRowScene = preload("res://ui/components/action_row.tscn")
const STATUS_IDS: Array[StringName] = [&"health", &"hunger", &"energy", &"tension", &"morale"]
const STATUS_TITLES := {
	&"health": "Здоровье",
	&"hunger": "Голод",
	&"energy": "Энергия",
	&"tension": "Напряжение",
	&"morale": "Мораль",
}

@onready var _background: TextureRect = %Background
@onready var _content_frame: VBoxContainer = %ContentFrame
@onready var _header: PanelContainer = %GameHeader
@onready var _status_glyphs: Array[BaseButton] = [
	%HealthGlyph,
	%HungerGlyph,
	%EnergyGlyph,
	%TensionGlyph,
	%MoraleGlyph,
]
@onready var _scroll: ScrollContainer = %LocationScroll
@onready var _place_eyebrow: Label = %PlaceEyebrow
@onready var _description_label: Label = %DescriptionLabel
@onready var _context_label: Label = %ContextLabel
@onready var _status_detail: PanelContainer = %StatusDetail
@onready var _status_detail_title: Label = %StatusDetailTitle
@onready var _status_detail_value: Label = %StatusDetailValue
@onready var _status_detail_copy: Label = %StatusDetailCopy
@onready var _status_detail_forecast: Label = %StatusDetailForecast
@onready var _status_detail_close: Button = %StatusDetailClose
@onready var _actions_heading: Label = %ActionsHeading
@onready var _actions_count: Label = %ActionsCount
@onready var _actions_list: VBoxContainer = %ActionsList
@onready var _empty_actions: Label = %EmptyActions

var _reduced_motion := false
var _status_models: Dictionary = {}
var _action_models: Dictionary = {}
var _entrance_tween: Tween
var _detail_tween: Tween


func _ready() -> void:
	_header.connect("settings_requested", func() -> void: settings_requested.emit())
	_status_detail_close.pressed.connect(_hide_status_detail)
	for glyph in _status_glyphs:
		glyph.connect("detail_requested", _on_status_detail_requested)
	_apply_reduced_motion()


func present(model: Dictionary) -> void:
	set_reduced_motion(bool(model.get("reduced_motion", _reduced_motion)))
	_header.call("present", _header_model(model))
	_present_background(model)

	_place_eyebrow.text = String(model.get("place_eyebrow", "СЕЙЧАС ВЫ ЗДЕСЬ")).to_upper()
	_description_label.text = String(model.get("description", "Осмотритесь и выберите, чем заняться дальше."))
	_context_label.text = _context_text(model)
	_context_label.visible = not _context_label.text.is_empty()

	_present_statuses(model.get("statuses", model.get("meters", [])))
	_present_actions(model.get("actions", []))
	_hide_status_detail()
	_scroll.scroll_vertical = 0
	_animate_entrance()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if is_node_ready():
		_apply_reduced_motion()


func _header_model(model: Dictionary) -> Dictionary:
	var header_model: Dictionary = {}
	if model.get("header", {}) is Dictionary:
		header_model = Dictionary(model.get("header", {})).duplicate(true)
	for key in ["district_title", "location_title", "date_text", "time_text", "money", "money_text", "show_settings"]:
		if not header_model.has(key) and model.has(key):
			header_model[key] = model[key]
	return header_model


func _present_background(model: Dictionary) -> void:
	var raw_texture: Variant = model.get("background_texture", null)
	if raw_texture is Texture2D:
		_background.texture = raw_texture
	else:
		var background_path := String(model.get("background_path", ""))
		if background_path.is_empty():
			var background_key := String(model.get("background_key", ""))
			if not background_key.is_empty():
				background_path = "res://assets/backgrounds/%s.png" % background_key
		if not background_path.is_empty() and ResourceLoader.exists(background_path):
			var loaded := ResourceLoader.load(background_path)
			if loaded is Texture2D:
				_background.texture = loaded

	var material := _background.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("psyche_intensity", clampf(float(model.get("psyche_intensity", 0.0)), 0.0, 1.0))


func _context_text(model: Dictionary) -> String:
	var explicit := String(model.get("context_text", ""))
	if not explicit.is_empty():
		return explicit
	var tags: Array[String] = []
	if model.get("context_tags", []) is Array:
		for raw_tag in model.get("context_tags", []):
			var tag := String(raw_tag)
			if not tag.is_empty():
				tags.append(tag)
	return "  ·  ".join(PackedStringArray(tags))


func _present_statuses(raw_statuses: Variant) -> void:
	var models_by_id: Dictionary = {}
	if raw_statuses is Array:
		for raw_model in raw_statuses:
			if raw_model is Dictionary:
				var status_model: Dictionary = raw_model
				models_by_id[StringName(status_model.get("id", &""))] = status_model
	elif raw_statuses is Dictionary:
		for raw_id in raw_statuses:
			var status_id := StringName(raw_id)
			var raw_value: Variant = raw_statuses[raw_id]
			var status_model: Dictionary
			if raw_value is Dictionary:
				status_model = Dictionary(raw_value).duplicate(true)
			else:
				status_model = {"value": raw_value}
			status_model["id"] = status_id
			models_by_id[status_id] = status_model

	_status_models.clear()
	for index in range(STATUS_IDS.size()):
		var status_id := STATUS_IDS[index]
		var status_model: Dictionary = (
			Dictionary(models_by_id[status_id]).duplicate(true)
			if models_by_id.has(status_id)
			else {"value": 0}
		)
		status_model["id"] = status_id
		if not status_model.has("title"):
			status_model["title"] = STATUS_TITLES[status_id]
		if not status_model.has("maximum"):
			status_model["maximum"] = 100
		_status_models[String(status_id)] = status_model.duplicate(true)
		_status_glyphs[index].call("present", status_model)


func _present_actions(raw_actions: Variant) -> void:
	for child in _actions_list.get_children():
		_actions_list.remove_child(child)
		child.queue_free()
	_action_models.clear()

	var visible_count := 0
	var available_count := 0
	if raw_actions is Array:
		for raw_action in raw_actions:
			if not raw_action is Dictionary:
				continue
			var action_model: Dictionary = Dictionary(raw_action).duplicate(true)
			var action_id := String(action_model.get("id", ""))
			if action_id.is_empty():
				continue
			var row := ActionRowScene.instantiate() as Button
			if row == null:
				continue
			row.name = "Action_%s" % action_id.validate_node_name()
			_actions_list.add_child(row)
			row.call("set_reduced_motion", _reduced_motion)
			row.call("present", action_model)
			row.connect("action_requested", _on_action_requested)
			_action_models[action_id] = action_model
			visible_count += 1
			if bool(action_model.get("enabled", true)):
				available_count += 1

	_actions_heading.text = "Что сделать здесь"
	_actions_count.text = "%d доступно" % available_count
	_empty_actions.visible = visible_count == 0


func _on_action_requested(action_id: String) -> void:
	var action_model: Dictionary = (
		Dictionary(_action_models[action_id]).duplicate(true)
		if _action_models.has(action_id)
		else {}
	)
	action_requested.emit(action_id, action_model)


func _on_status_detail_requested(status_id: String) -> void:
	status_requested.emit(status_id)
	if not _status_models.has(status_id):
		return
	var model: Dictionary = Dictionary(_status_models[status_id])
	var value := int(round(float(model.get("value", 0))))
	var maximum := int(round(float(model.get("maximum", 100))))
	_status_detail_title.text = String(model.get("title", "Состояние"))
	_status_detail_value.text = "%d из %d" % [value, maximum]
	_status_detail_copy.text = String(model.get("detail", "Нет дополнительных сведений."))
	_status_detail_forecast.text = String(model.get("forecast", ""))
	_status_detail_forecast.visible = not _status_detail_forecast.text.is_empty()
	_status_detail.visible = true
	call_deferred("_reveal_status_detail")

	if not _reduced_motion:
		if _detail_tween != null and _detail_tween.is_valid():
			_detail_tween.kill()
		_status_detail.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_detail_tween = create_tween()
		_detail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_detail_tween.tween_property(_status_detail, "modulate", Color.WHITE, 0.18)


func _reveal_status_detail() -> void:
	if is_instance_valid(_scroll) and is_instance_valid(_status_detail) and _status_detail.visible:
		_scroll.ensure_control_visible(_status_detail)


func _hide_status_detail() -> void:
	if is_instance_valid(_status_detail):
		_status_detail.visible = false
		_status_detail.modulate = Color.WHITE


func _apply_reduced_motion() -> void:
	for glyph in _status_glyphs:
		glyph.call("set_reduced_motion", _reduced_motion)
	for child in _actions_list.get_children():
		if child.has_method("set_reduced_motion"):
			child.call("set_reduced_motion", _reduced_motion)
	if _reduced_motion:
		if _entrance_tween != null and _entrance_tween.is_valid():
			_entrance_tween.kill()
		if _detail_tween != null and _detail_tween.is_valid():
			_detail_tween.kill()
		_content_frame.modulate = Color.WHITE


func _animate_entrance() -> void:
	if _reduced_motion:
		_content_frame.modulate = Color.WHITE
		return
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_content_frame.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_entrance_tween = create_tween()
	_entrance_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_entrance_tween.tween_property(_content_frame, "modulate", Color.WHITE, 0.24)
