class_name SearchInteractionSheet
extends Control

signal interaction_confirmed(object_id: String, approach_id: String)
signal dismissed

const ApproachRowScene := preload("res://ui/components/search_approach_row.tscn")
const ApproachRowScript := preload("res://ui/components/search_approach_row.gd")

@onready var _panel: PanelContainer = %SheetPanel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _eyebrow: Label = %Eyebrow
@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _actions: VBoxContainer = %Actions
@onready var _empty: Label = %Empty
@onready var _close: Button = %Close

var _object_id := ""
var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	_close.pressed.connect(close)
	%BackdropButton.pressed.connect(close)
	visible = false


func present(object_model: Dictionary, reduced_motion: bool) -> void:
	_reduced_motion = reduced_motion
	_object_id = String(object_model.get("id", ""))
	_eyebrow.text = _type_label(String(object_model.get("type", "open")))
	_title.text = String(object_model.get("title", "Объект"))
	_description.text = _description_for(object_model)
	_rebuild_actions(Array(object_model.get(
		"approaches",
		object_model.get("interactions", [])
	)))
	visible = true
	_scroll.scroll_vertical = 0
	_animate_open()


func close() -> void:
	if not visible:
		return
	visible = false
	_panel.position.y = 0.0
	_panel.modulate = Color.WHITE
	dismissed.emit()


func is_open() -> bool:
	return visible


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_panel.position.y = 0.0
		_panel.modulate = Color.WHITE


func _rebuild_actions(raw_approaches: Array) -> void:
	for child: Node in _actions.get_children():
		child.queue_free()
	var count := 0
	for raw_approach: Variant in raw_approaches:
		if not raw_approach is Dictionary:
			continue
		var row := ApproachRowScene.instantiate() as ApproachRowScript
		_actions.add_child(row)
		row.confirmed.connect(_on_approach_confirmed)
		row.present(Dictionary(raw_approach))
		count += 1
	_empty.visible = count == 0


func _on_approach_confirmed(approach_id: String) -> void:
	var object_id := _object_id
	close()
	interaction_confirmed.emit(object_id, approach_id)


func _animate_open() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.position.y = 0.0
	_panel.modulate = Color.WHITE
	if _reduced_motion:
		return
	_panel.position.y = 24.0
	_panel.modulate = Color(1, 1, 1, 0)
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position:y", 0.0, 0.2)
	_tween.tween_property(_panel, "modulate", Color.WHITE, 0.17)


static func _type_label(type_id: String) -> String:
	match type_id:
		"hidden":
			return "СКРЫТОЕ МЕСТО"
		"locked":
			return "ЗАПЕРТО"
		"heavy":
			return "ТЯЖЁЛЫЙ ОБЪЕКТ"
		"social":
			return "НУЖНО ДОГОВОРИТЬСЯ"
		"trespass":
			return "ЗАКРЫТАЯ ТЕРРИТОРИЯ"
		"technical":
			return "ТЕХНИЧЕСКИЙ ОБЪЕКТ"
		"hazardous":
			return "ОПАСНОЕ МЕСТО"
		_:
			return "МОЖНО ОСМОТРЕТЬ"


static func _description_for(object_model: Dictionary) -> String:
	if bool(object_model.get("interacted", false)):
		return "Здесь уже всё осмотрено. Состояние места сохранится после выхода."
	return String(object_model.get(
		"description",
		"Выберите способ. Время и состояние изменятся только после подтверждения."
	))
