class_name SearchLootTray
extends PanelContainer

signal pickup_requested(stack_id: String, target_container_id: String)
signal details_requested(stack_id: String)

@onready var _title: Label = %Title
@onready var _meta: Label = %Meta
@onready var _pickup: Button = %Pickup
@onready var _details: Button = %Details

var _stack_id := ""
var _target_container_id := ""
var _tween: Tween


func _ready() -> void:
	_pickup.pressed.connect(func() -> void:
		if not _stack_id.is_empty() and not _target_container_id.is_empty():
			pickup_requested.emit(_stack_id, _target_container_id)
	)
	_details.pressed.connect(func() -> void:
		if not _stack_id.is_empty():
			details_requested.emit(_stack_id)
	)
	# The details sheet has no destination yet. Showing a button that answers
	# nothing costs a narrow tray the width its find name needs.
	_details.visible = false
	_title.clip_text = true
	_meta.clip_text = true
	resized.connect(_apply_density)
	visible = false
	_apply_density()


func present(
	entries: Array,
	reduced_motion: bool = false,
	font_scale: float = 1.0
) -> void:
	if entries.is_empty() or not entries.back() is Dictionary:
		visible = false
		_stack_id = ""
		_target_container_id = ""
		return
	var entry: Dictionary = entries.back()
	var previous_id := _stack_id
	_stack_id = String(entry.get(
		"stack_id",
		entry.get("loot_id", entry.get("ground_id", ""))
	))
	_target_container_id = String(entry.get("target_container_id", ""))
	_title.text = "%s ×%d" % [
		String(entry.get("title", "Находка")),
		int(entry.get("quantity", 1)),
	]
	_meta.text = (
		"%s  ·  %s" % [
			String(entry.get("mass_text", "")),
			String(entry.get("volume_text", "")),
		]
		if font_scale >= 1.5
		else "%s  ·  %s  ·  состояние %d%%" % [
			String(entry.get("mass_text", "")),
			String(entry.get("volume_text", "")),
			int(entry.get("condition", 100)),
		]
	)
	var blocked_reason := String(entry.get(
		"pickup_blocked_reason",
		"Выберите место в инвентаре."
	))
	if _target_container_id.is_empty():
		_meta.text = blocked_reason
	_pickup.text = "Взять" if font_scale >= 1.5 else "Забрать"
	_pickup.disabled = (
		_stack_id.is_empty()
		or _target_container_id.is_empty()
		or not bool(entry.get("pickup_enabled", true))
	)
	# The reason is already printed in the meta line under the title.
	visible = true
	_apply_density()
	if previous_id != _stack_id:
		_animate_entrance(reduced_motion)


func _apply_density() -> void:
	if not is_node_ready():
		return
	var compact := size.x < 420.0
	_pickup.custom_minimum_size.x = 76.0 if compact else 88.0


func _animate_entrance(reduced_motion: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position.y = 0.0
	modulate = Color.WHITE
	if reduced_motion:
		return
	position.y = 12.0
	modulate = Color(1, 1, 1, 0)
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", 0.0, 0.2)
	_tween.tween_property(self, "modulate", Color.WHITE, 0.16)
