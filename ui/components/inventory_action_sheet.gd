class_name InventoryActionSheet
extends Control

const Motion := preload("res://ui/theme/motion.gd")
signal confirmed(
	stack_id: String,
	action_id: String,
	quantity: int,
	target_container_id: String
)
signal replacement_confirmed(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
)
signal retry_requested(stack_id: String, action_id: String)

@onready var _panel: PanelContainer = %SheetPanel
@onready var _title: Label = %TitleLabel
@onready var _body: Label = %BodyLabel
@onready var _duration: Label = %DurationLabel
@onready var _effects: Label = %EffectsLabel
@onready var _outputs: Label = %OutputsLabel
@onready var _conditions: Label = %ConditionsLabel
@onready var _quantity_row: HBoxContainer = %QuantityRow
@onready var _quantity_value: Label = %QuantityValue
@onready var _decrease_quantity: Button = %DecreaseQuantityButton
@onready var _increase_quantity: Button = %IncreaseQuantityButton
@onready var _target_row: VBoxContainer = %TargetRow
@onready var _target_picker: OptionButton = %TargetPicker
@onready var _conflict: VBoxContainer = %ConflictSection
@onready var _conflict_capacity: Label = %ConflictCapacityLabel
@onready var _replacement_picker: OptionButton = %ReplacementPicker
@onready var _recoveries: Label = %RecoveriesLabel
@onready var _alternate: Button = %AlternateButton
@onready var _cancel: Button = %CancelButton
@onready var _confirm: Button = %ConfirmButton

var _stack_id := ""
var _action_id := ""
var _quantity := 1
var _max_quantity := 1
var _mode := "action"
var _target_container_id := ""
var _reduced_motion := false
var _tween: Tween


func _ready() -> void:
	%BackdropButton.pressed.connect(close)
	_cancel.pressed.connect(close)
	_confirm.pressed.connect(_on_confirmed)
	_alternate.pressed.connect(_on_alternate)
	_decrease_quantity.pressed.connect(_change_quantity.bind(-1))
	_increase_quantity.pressed.connect(_change_quantity.bind(1))
	visible = false


func open(item_model: Dictionary, action_model: Dictionary) -> void:
	_mode = "action"
	_stack_id = String(item_model.get("stack_id", ""))
	_action_id = String(action_model.get("id", ""))
	_quantity = 1
	_max_quantity = maxi(int(action_model.get("max_quantity", 1)), 1)
	_target_container_id = ""
	_title.text = _action_title(_action_id, String(item_model.get("title", "предмет")))
	_body.text = _action_body(_action_id)
	_duration.text = String(action_model.get("duration_text", "Время не изменится"))
	_set_detail_label(_effects, "Последствия", Array(action_model.get("effect_lines", [])))
	_set_detail_label(_outputs, "Результат", Array(action_model.get("output_lines", [])))
	_set_detail_label(_conditions, "Условия", Array(action_model.get("condition_lines", [])))
	_quantity_row.visible = bool(action_model.get("quantity_adjustable", false))
	_update_quantity()
	_fill_targets(item_model, _action_id)
	_conflict.visible = false
	_alternate.visible = false
	_cancel.text = "Отмена"
	_confirm.text = "Подтвердить"
	_confirm.disabled = _action_id in ["move", "pick_up"] and _target_picker.item_count == 0
	_show()


func open_conflict(model: Dictionary) -> void:
	_mode = "conflict"
	var incoming: Dictionary = model.get("incoming", {})
	_stack_id = String(incoming.get("stack_id", ""))
	_action_id = "replace"
	_target_container_id = String(model.get("container_id", ""))
	_title.text = "Находка не помещается"
	_body.text = "«%s» не входит в выбранное место. Ничего ещё не изменено." % String(
		incoming.get("title", "Предмет")
	)
	_duration.text = "Замена не расходует игровое время"
	_effects.visible = false
	_outputs.visible = false
	_conditions.visible = false
	_quantity_row.visible = false
	_target_row.visible = false
	_conflict.visible = true
	_conflict_capacity.text = _capacity_conflict_text(model)
	_fill_replacements(Array(model.get("comparison", [])))
	var recoveries: Array = model.get("recoveries", [])
	_recoveries.text = _recovery_text(recoveries)
	_alternate.visible = "choose_other_container" in recoveries
	_alternate.text = "Выбрать другое место"
	_cancel.text = "Оставить здесь"
	_confirm.text = "Заменить"
	_confirm.disabled = (
		not ("replace" in recoveries)
		or _replacement_picker.item_count == 0
	)
	_show()


func close() -> void:
	visible = false
	_panel.position.y = 0.0
	_panel.modulate = Color.WHITE


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _tween != null and _tween.is_valid():
		_tween.kill()
		_panel.position.y = 0.0
		_panel.modulate = Color.WHITE


func _show() -> void:
	visible = true
	%SheetScroll.scroll_vertical = 0
	_panel.position.y = 24.0
	_panel.modulate = Color(1, 1, 1, 0)
	_tween = Motion.play(_tween, self, [
		{"target": _panel, "property": "position:y", "to": 0.0, "duration": Motion.SHEET},
		{"target": _panel, "property": "modulate", "to": Color.WHITE, "duration": Motion.FADE},
	], _reduced_motion)


func _on_confirmed() -> void:
	if _mode == "conflict":
		var displaced_id := _selected_metadata(_replacement_picker)
		var incoming_id := _stack_id
		var target_id := _target_container_id
		close()
		replacement_confirmed.emit(incoming_id, displaced_id, target_id)
		return
	var target_id := ""
	if _action_id in ["move", "pick_up"]:
		target_id = _selected_metadata(_target_picker)
	var stack_id := _stack_id
	var action_id := _action_id
	var quantity := _quantity
	close()
	confirmed.emit(stack_id, action_id, quantity, target_id)


func _on_alternate() -> void:
	var stack_id := _stack_id
	close()
	retry_requested.emit(stack_id, "pick_up")


func _change_quantity(delta: int) -> void:
	_quantity = clampi(_quantity + delta, 1, _max_quantity)
	_update_quantity()


func _update_quantity() -> void:
	_quantity_value.text = "%d из %d" % [_quantity, _max_quantity]
	_decrease_quantity.disabled = _quantity <= 1
	_increase_quantity.disabled = _quantity >= _max_quantity


func _fill_targets(item_model: Dictionary, action_id: String) -> void:
	_target_row.visible = action_id in ["move", "pick_up"]
	_target_picker.clear()
	for raw_target in Array(item_model.get("move_targets", [])):
		if not raw_target is Dictionary:
			continue
		var target: Dictionary = raw_target
		if String(target.get("id", "")) == String(item_model.get("container_id", "")):
			continue
		_target_picker.add_item(String(target.get("title", "Контейнер")))
		_target_picker.set_item_metadata(
			_target_picker.item_count - 1,
			String(target.get("id", ""))
		)


func _fill_replacements(comparison: Array) -> void:
	_replacement_picker.clear()
	for raw_item in comparison:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		_replacement_picker.add_item("%s · %s · %s" % [
			String(item.get("title", "Предмет")),
			_format_mass(int(item.get("mass_grams", 0))),
			_format_volume(int(item.get("volume_ml", 0))),
		])
		_replacement_picker.set_item_metadata(
			_replacement_picker.item_count - 1,
			String(item.get("stack_id", ""))
		)


func _set_detail_label(label: Label, heading: String, lines: Array) -> void:
	label.visible = not lines.is_empty()
	if label.visible:
		var text_lines := PackedStringArray()
		for line in lines:
			text_lines.append("• %s" % String(line))
		label.text = "%s\n%s" % [heading, "\n".join(text_lines)]


func _capacity_conflict_text(model: Dictionary) -> String:
	var incoming: Dictionary = model.get("incoming", {})
	var capacity: Dictionary = model.get("capacity", {})
	var next_mass := int(capacity.get("mass_used_grams", 0)) + int(incoming.get("mass_grams", 0))
	var next_volume := int(capacity.get("volume_used_ml", 0)) + int(incoming.get("volume_ml", 0))
	return "После добавления: %s из %s · %s из %s" % [
		_format_mass(next_mass),
		_format_mass(int(capacity.get("mass_capacity_grams", 0))),
		_format_volume(next_volume),
		_format_volume(int(capacity.get("volume_capacity_ml", 0))),
	]


func _recovery_text(recoveries: Array) -> String:
	var lines := PackedStringArray()
	if "choose_other_container" in recoveries:
		lines.append("выбрать другое место")
	if "replace" in recoveries:
		lines.append("оставить одну из вещей взамен")
	if "leave_at_source" in recoveries:
		lines.append("оставить находку здесь")
	return "Доступно: %s." % ", ".join(lines)


func _selected_metadata(picker: OptionButton) -> String:
	return (
		String(picker.get_item_metadata(picker.selected))
		if picker.item_count > 0 and picker.selected >= 0
		else ""
	)


func _action_title(action_id: String, item_title: String) -> String:
	match action_id:
		"move":
			return "Куда переложить «%s»?" % item_title
		"pick_up":
			return "Куда положить «%s»?" % item_title
		"use":
			return "Использовать «%s»?" % item_title
		"disassemble":
			return "Разобрать «%s»?" % item_title
		"drop":
			return "Оставить «%s» здесь?" % item_title
		"equip":
			return "Надеть «%s»?" % item_title
		"unequip":
			return "Снять «%s»?" % item_title
	return "Подтвердить действие"


func _action_body(action_id: String) -> String:
	match action_id:
		"move", "pick_up":
			return "Масса и объём выбранного места будут проверены до изменения."
		"use":
			return "Предмет будет израсходован только после подтверждения."
		"disassemble":
			return "Исходный предмет исчезнет, а указанные материалы займут его место."
		"drop":
			return "Вещь останется в текущей локации и перестанет считаться переносимой."
		"equip":
			return "Вещь займёт свой слот и начнёт действовать, пока надета."
		"unequip":
			return "Вещь вернётся в переносимые и перестанет действовать. Сумку нужно сначала опустошить."
	return "Это действие изменит состояние попытки."


func _format_mass(grams: int) -> String:
	return "%d г" % grams if grams < 1000 else ("%.1f кг" % (grams / 1000.0)).replace(".", ",")


func _format_volume(ml: int) -> String:
	return "%d мл" % ml if ml < 1000 else ("%.1f л" % (ml / 1000.0)).replace(".", ",")
