class_name SearchCapacityConflictSheet
extends Control

signal replacement_requested(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
)
signal recovery_requested(incoming_stack_id: String, recovery_id: String)
signal dismissed

@onready var _panel: PanelContainer = %SheetPanel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _title: Label = %Title
@onready var _incoming: Label = %Incoming
@onready var _capacity: Label = %Capacity
@onready var _picker: OptionButton = %ReplacementPicker
@onready var _recovery_note: Label = %RecoveryNote
@onready var _other: Button = %OtherContainer
@onready var _leave: Button = %Leave
@onready var _replace: Button = %Replace

var _incoming_stack_id := ""
var _target_container_id := ""
var _recoveries: Array = []
var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	%BackdropButton.pressed.connect(close)
	%Close.pressed.connect(close)
	_other.pressed.connect(_on_other_container)
	_leave.pressed.connect(_on_leave)
	_replace.pressed.connect(_on_replace)
	visible = false


func present(model: Dictionary, reduced_motion: bool) -> void:
	_reduced_motion = reduced_motion
	var incoming: Dictionary = Dictionary(model.get("incoming", {}))
	_incoming_stack_id = String(incoming.get(
		"stack_id",
		incoming.get("loot_id", incoming.get("ground_id", ""))
	))
	_target_container_id = String(model.get("container_id", ""))
	_recoveries = Array(model.get("recoveries", [])).duplicate()
	_title.text = "Не хватает места"
	_incoming.text = "%s ×%d\n%s · %s" % [
		String(incoming.get("title", "Находка")),
		int(incoming.get("quantity", 1)),
		_format_mass(int(incoming.get("mass_grams", 0))),
		_format_volume(int(incoming.get("volume_ml", 0))),
	]
	_capacity.text = _capacity_text(model, incoming)
	_fill_replacements(Array(model.get("comparison", [])))
	_recovery_note.text = _recovery_text(_recoveries)
	_other.visible = "choose_other_container" in _recoveries
	_leave.visible = "leave_at_source" in _recoveries
	_replace.visible = "replace" in _recoveries
	_replace.disabled = _picker.item_count == 0 or _incoming_stack_id.is_empty()
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


func _fill_replacements(comparison: Array) -> void:
	_picker.clear()
	for raw_item: Variant in comparison:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		_picker.add_item("%s · %s · %s" % [
			String(item.get("title", "Предмет")),
			_format_mass(int(item.get("mass_grams", 0))),
			_format_volume(int(item.get("volume_ml", 0))),
		])
		_picker.set_item_metadata(
			_picker.item_count - 1,
			String(item.get("stack_id", ""))
		)


func _on_replace() -> void:
	if _picker.item_count == 0 or _picker.selected < 0:
		return
	var incoming_id := _incoming_stack_id
	var displaced_id := String(_picker.get_item_metadata(_picker.selected))
	var container_id := _target_container_id
	close()
	replacement_requested.emit(incoming_id, displaced_id, container_id)


func _on_other_container() -> void:
	var incoming_id := _incoming_stack_id
	close()
	recovery_requested.emit(incoming_id, "choose_other_container")


func _on_leave() -> void:
	var incoming_id := _incoming_stack_id
	close()
	recovery_requested.emit(incoming_id, "leave_at_source")


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


static func _capacity_text(model: Dictionary, incoming: Dictionary) -> String:
	var capacity: Dictionary = Dictionary(model.get("capacity", {}))
	var next_mass := int(capacity.get("mass_used_grams", 0)) + int(
		incoming.get("mass_grams", 0)
	)
	var next_volume := int(capacity.get("volume_used_ml", 0)) + int(
		incoming.get("volume_ml", 0)
	)
	return "После подбора: %s из %s · %s из %s" % [
		_format_mass(next_mass),
		_format_mass(int(capacity.get("mass_capacity_grams", 0))),
		_format_volume(next_volume),
		_format_volume(int(capacity.get("volume_capacity_ml", 0))),
	]


static func _recovery_text(recoveries: Array) -> String:
	var labels := PackedStringArray()
	if "choose_other_container" in recoveries:
		labels.append("выбрать другое место")
	if "replace" in recoveries:
		labels.append("оставить одну из вещей взамен")
	if "leave_at_source" in recoveries:
		labels.append("оставить находку здесь")
	return (
		"Ничего не потеряно. Можно %s." % ", ".join(labels)
		if not labels.is_empty()
		else "Находка останется на карте."
	)


static func _format_mass(grams: int) -> String:
	return (
		("%0.1f кг" % (grams / 1000.0)).replace(".", ",")
		if grams >= 1000 else "%d г" % grams
	)


static func _format_volume(milliliters: int) -> String:
	return (
		("%0.1f л" % (milliliters / 1000.0)).replace(".", ",")
		if milliliters >= 1000 else "%d мл" % milliliters
	)
