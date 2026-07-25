class_name SearchScreen
extends Control

signal move_requested(target: Vector2, focus_object_id: String)
signal movement_checkpoint(position: Vector2, path_index: int, completed: bool)
signal interaction_requested(object_id: String, approach_id: String)
signal pickup_requested(stack_id: String, target_container_id: String)
signal loot_details_requested(stack_id: String)
signal replacement_requested(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
)
signal capacity_recovery_requested(incoming_stack_id: String, recovery_id: String)
signal finish_requested
signal quick_search_requested

const CapacitySheetScript := preload(
	"res://ui/components/search_capacity_conflict_sheet.gd"
)

@onready var _world: SearchWorld = %SearchWorld
@onready var _title: Label = %Title
@onready var _risk_value: Label = %RiskValue
@onready var _risk_bar: ProgressBar = %RiskBar
@onready var _noise: Label = %Noise
@onready var _trespass: Label = %Trespass
@onready var _repeated: Label = %Repeated
@onready var _hint: Label = %Hint
@onready var _map_hint: Control = %MapHint
@onready var _loot_tray: SearchLootTray = %LootTray
@onready var _quick_search: Button = %QuickSearch
@onready var _finish: Button = %Finish
@onready var _actions: HBoxContainer = %Actions
@onready var _sheet: SearchInteractionSheet = %InteractionSheet
@onready var _capacity_sheet: CapacitySheetScript = %CapacitySheet

var _model: Dictionary = {}
var _objects: Dictionary = {}
var _reduced_motion := false
var _risk: Dictionary = {}
var _actions_paired := false


func _ready() -> void:
	resized.connect(_apply_density)
	_world.move_requested.connect(func(target: Vector2, focus_id: String) -> void:
		move_requested.emit(target, focus_id)
	)
	_world.object_requested.connect(_open_object)
	_world.movement_checkpoint.connect(func(
		position: Vector2,
		index: int,
		completed: bool
	) -> void:
		movement_checkpoint.emit(position, index, completed)
	)
	_sheet.interaction_confirmed.connect(func(
		object_id: String,
		approach_id: String
	) -> void:
		interaction_requested.emit(object_id, approach_id)
	)
	_loot_tray.pickup_requested.connect(func(
		stack_id: String,
		target_container_id: String
	) -> void:
		pickup_requested.emit(stack_id, target_container_id)
	)
	_loot_tray.details_requested.connect(func(stack_id: String) -> void:
		loot_details_requested.emit(stack_id)
	)
	_capacity_sheet.replacement_requested.connect(func(
		incoming_id: String,
		displaced_id: String,
		container_id: String
	) -> void:
		replacement_requested.emit(incoming_id, displaced_id, container_id)
	)
	_capacity_sheet.recovery_requested.connect(func(
		incoming_id: String,
		recovery_id: String
	) -> void:
		capacity_recovery_requested.emit(incoming_id, recovery_id)
	)
	_quick_search.pressed.connect(func() -> void: quick_search_requested.emit())
	_finish.pressed.connect(func() -> void: finish_requested.emit())
	_apply_density()


func present(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_reduced_motion = bool(model.get("reduced_motion", false))
	_title.text = String(model.get("title", "Поиск"))
	_hint.text = String(model.get(
		"subtitle",
		"Ходьба не тратит игровое время. Время меняют только подтверждённые действия."
	))
	_present_risk(Dictionary(model.get("risk", {})))
	_objects.clear()
	for raw_object: Variant in Array(model.get("objects", [])):
		if raw_object is Dictionary:
			var object: Dictionary = raw_object
			_objects[String(object.get("id", ""))] = object.duplicate(true)
	_world.present(model)
	_loot_tray.present(
		Array(model.get("loot_tray", [])),
		_reduced_motion,
		float(model.get("font_scale", 1.0))
	)
	_present_quick_search(Dictionary(model.get("quick_search", {})))
	_sheet.set_reduced_motion(_reduced_motion)
	_capacity_sheet.set_reduced_motion(_reduced_motion)
	_apply_density()


func refresh(model: Dictionary) -> void:
	present(model)


func animate_path(path: Array, focus_object_id: String = "") -> void:
	_world.animate_path(path, focus_object_id)


func show_capacity_conflict(model: Dictionary) -> void:
	if _sheet.is_open():
		_sheet.close()
	_capacity_sheet.present(model, _reduced_motion)


func has_open_modal() -> bool:
	return _capacity_sheet.is_open() or _sheet.is_open()


func handle_back() -> bool:
	if _capacity_sheet.is_open():
		_capacity_sheet.close()
		return true
	if _sheet.is_open():
		_sheet.close()
		return true
	finish_requested.emit()
	return true


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_world.set_reduced_motion(enabled)
	_sheet.set_reduced_motion(enabled)
	_capacity_sheet.set_reduced_motion(enabled)


func _open_object(object_id: String) -> void:
	if _objects.has(object_id):
		_sheet.present(Dictionary(_objects[object_id]), _reduced_motion)


## A control the player has not earned yet is absent, not greyed out: no
## placeholder and no explanation of what would bring it in.
func _present_quick_search(quick: Dictionary) -> void:
	var earned := bool(quick.get("visible", false))
	_quick_search.visible = earned
	_quick_search.disabled = not bool(quick.get("enabled", false))
	_layout_actions(earned)


## Alone, the exit sits centred at its own width. Once quick search is earned the
## pair shares the row evenly.
func _layout_actions(paired: bool) -> void:
	_actions_paired = paired
	_actions.alignment = (
		BoxContainer.ALIGNMENT_BEGIN if paired else BoxContainer.ALIGNMENT_CENTER
	)
	_finish.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if paired else Control.SIZE_SHRINK_CENTER
	)
	_finish.custom_minimum_size.x = 0.0 if paired else 200.0
	_apply_density()


func _present_risk(risk: Dictionary) -> void:
	_risk = risk.duplicate(true)
	var score := clampi(int(risk.get("score", 0)), 0, 100)
	var warning := maxi(int(risk.get("warning_threshold", 35)), 1)
	_risk_value.text = String(risk.get("label", "Низкий"))
	_risk_bar.value = score
	_risk_bar.modulate = (
		Color("#df8e82")
		if score >= warning
		else Color("#e4c078") if score >= warning / 2 else Color("#86c7aa")
	)
	_noise.text = "Шум  %d" % int(risk.get("noise", 0))
	_trespass.text = "Проникновение  %d" % int(risk.get("trespass", 0))
	_repeated.text = "Повторы  %d" % int(risk.get("repeated_attempts", 0))


func _apply_density() -> void:
	if not is_node_ready():
		return
	var font_scale := float(_model.get("font_scale", 1.0))
	var compact := size.x < 410.0 or size.y < 720.0 or font_scale >= 1.5
	# Alone the exit has the whole row to itself and keeps its full label.
	_finish.text = "Закончить" if compact and _actions_paired else "Закончить поиск"
	_quick_search.text = "Быстро" if compact else "Быстрый поиск"
	_hint.visible = not (font_scale >= 1.75 and size.y < 760.0)
	_map_hint.visible = font_scale < 1.5
	if compact:
		_noise.text = "Шум %d" % int(_risk.get("noise", 0))
		_trespass.text = "Зона %d" % int(_risk.get("trespass", 0))
		_repeated.text = "Повторы %d" % int(_risk.get("repeated_attempts", 0))
	else:
		_noise.text = "Шум  %d" % int(_risk.get("noise", 0))
		_trespass.text = "Проникновение  %d" % int(_risk.get("trespass", 0))
		_repeated.text = "Повторы  %d" % int(_risk.get("repeated_attempts", 0))
