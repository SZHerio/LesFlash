class_name InventoryScreen
extends Control

signal action_requested(
	stack_id: String,
	action_id: String,
	quantity: int,
	target_container_id: String
)
signal replacement_requested(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
)
signal settings_requested

const ItemCardScene := preload("res://ui/components/inventory_item_card.tscn")

@onready var _header: GameHeader = %GameHeader
@onready var _scroll: ScrollContainer = %InventoryScroll
@onready var _location: Label = %LocationLabel
@onready var _message: Label = %CapacityMessage
@onready var _mass_card: InventoryCapacityCard = %MassCard
@onready var _volume_card: InventoryCapacityCard = %VolumeCard
@onready var _overload: PanelContainer = %OverloadPanel
@onready var _container_filter: OptionButton = %ContainerFilter
@onready var _kind_filter: OptionButton = %KindFilter
@onready var _sort_picker: OptionButton = %SortPicker
@onready var _items_list: VBoxContainer = %ItemsList
@onready var _empty_state: MarginContainer = %EmptyState
@onready var _item_count: Label = %ItemCount
@onready var _sheet: InventoryActionSheet = %ActionSheet

var _model: Dictionary = {}
var _items: Array = []
var _selected_stack_id := ""
var _reduced_motion := false
var _has_presented := false
var _building_filters := false
var _pending_scroll := 0
var _scroll_restore_frames := 0


func _ready() -> void:
	set_process(false)
	_header.settings_requested.connect(func() -> void: settings_requested.emit())
	_container_filter.item_selected.connect(_on_filter_changed)
	_kind_filter.item_selected.connect(_on_filter_changed)
	_sort_picker.item_selected.connect(_on_filter_changed)
	_sheet.confirmed.connect(func(
		stack_id: String,
		action_id: String,
		quantity: int,
		target_container_id: String
	) -> void:
		action_requested.emit(stack_id, action_id, quantity, target_container_id)
	)
	_sheet.replacement_confirmed.connect(func(
		incoming_stack_id: String,
		displaced_stack_id: String,
		target_container_id: String
	) -> void:
		replacement_requested.emit(incoming_stack_id, displaced_stack_id, target_container_id)
	)
	_sheet.retry_requested.connect(_retry_action)


func present(model: Dictionary) -> void:
	var state := _capture_view_state() if _has_presented else {
		"container": "",
		"kind": "",
		"sort": "title",
		"scroll": 0,
	}
	_model = model.duplicate(true)
	_items = Array(model.get("items", [])).duplicate(true)
	_selected_stack_id = String(model.get("selected_stack_id", ""))
	set_reduced_motion(bool(model.get("reduced_motion", false)))
	_header.present(Dictionary(model.get("header", {})))
	_location.text = "Сейчас: %s" % String(model.get("location_title", "текущее место"))
	var summary: Dictionary = model.get("summary", {})
	_message.text = String(summary.get("message", ""))
	_overload.visible = bool(summary.get("overloaded", false))
	_mass_card.present(_capacity_card_model(summary.get("mass", {}), "КГ", "Масса"))
	_volume_card.present(_capacity_card_model(summary.get("volume", {}), "Л", "Объём"))
	_build_filters(Array(model.get("containers", [])), state)
	_rebuild_items()
	_has_presented = true
	_queue_scroll_restore(int(state.get("scroll", 0)))


func _process(_delta: float) -> void:
	if _scroll_restore_frames <= 0:
		set_process(false)
		return
	_scroll.scroll_vertical = mini(
		_pending_scroll,
		int(_scroll.get_v_scroll_bar().max_value)
	)
	_scroll_restore_frames -= 1


func show_capacity_conflict(raw_model: Dictionary) -> void:
	var model := raw_model.duplicate(true)
	var incoming: Dictionary = Dictionary(model.get("incoming", {})).duplicate(true)
	var incoming_id := String(incoming.get("stack_id", ""))
	for raw_item in _items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if String(item.get("stack_id", "")) != incoming_id:
			continue
		incoming["title"] = String(item.get("title", incoming.get("title", "Предмет")))
		incoming["mass_grams"] = int(item.get("mass_grams", incoming.get("mass_grams", 0)))
		incoming["volume_ml"] = int(item.get("volume_ml", incoming.get("volume_ml", 0)))
		break
	model["incoming"] = incoming
	_sheet.open_conflict(model)


func has_open_sheet() -> bool:
	return _sheet != null and _sheet.visible


func handle_back() -> bool:
	if not has_open_sheet():
		return false
	_sheet.close()
	return true


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if is_node_ready():
		_mass_card.set_reduced_motion(enabled)
		_volume_card.set_reduced_motion(enabled)
		_sheet.set_reduced_motion(enabled)
		for child in _items_list.get_children():
			if child.has_method("set_reduced_motion"):
				child.call("set_reduced_motion", enabled)


func _build_filters(containers: Array, state: Dictionary) -> void:
	var compact := get_viewport_rect().size.x <= 400.0
	_building_filters = true
	_container_filter.clear()
	_container_filter.add_item("Место" if compact else "Все места")
	_container_filter.set_item_metadata(0, "")
	for raw_container in containers:
		if not raw_container is Dictionary:
			continue
		var container: Dictionary = raw_container
		if not bool(container.get("active", false)):
			continue
		_container_filter.add_item("%s · %d" % [
			String(container.get("title", "Контейнер")),
			int(container.get("count", 0)),
		])
		_container_filter.set_item_metadata(
			_container_filter.item_count - 1,
			String(container.get("id", ""))
		)
	_kind_filter.clear()
	for option in [
		["Тип" if compact else "Все вещи", ""],
		["Действия" if compact else "Можно использовать", "usable"],
		["Сырьё" if compact else "Материалы", "material"],
		["Забота" if compact else "Еда и медицина", "care"],
	]:
		_kind_filter.add_item(String(option[0]))
		_kind_filter.set_item_metadata(_kind_filter.item_count - 1, String(option[1]))
	_sort_picker.clear()
	for option in [
		["А—Я" if compact else "По названию", "title"],
		["Вес" if compact else "По массе", "mass"],
		["Где" if compact else "По месту", "container"],
	]:
		_sort_picker.add_item(String(option[0]))
		_sort_picker.set_item_metadata(_sort_picker.item_count - 1, String(option[1]))
	_select_metadata(_container_filter, String(state.get("container", "")))
	_select_metadata(_kind_filter, String(state.get("kind", "")))
	_select_metadata(_sort_picker, String(state.get("sort", "title")))
	_building_filters = false


func _rebuild_items() -> void:
	for child in _items_list.get_children():
		_items_list.remove_child(child)
		child.queue_free()
	var visible_items: Array = []
	var container_id := _selected_metadata(_container_filter)
	var kind := _selected_metadata(_kind_filter)
	for raw_item in _items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if not container_id.is_empty() and String(item.get("container_id", "")) != container_id:
			continue
		if not _matches_kind(item, kind):
			continue
		visible_items.append(item)
	_sort_items(visible_items, _selected_metadata(_sort_picker))
	for item in visible_items:
		var card := ItemCardScene.instantiate() as InventoryItemCard
		if card == null:
			continue
		_items_list.add_child(card)
		card.set_reduced_motion(_reduced_motion)
		card.present(item, String(item.get("stack_id", "")) == _selected_stack_id)
		card.selected.connect(_on_selected)
		card.action_requested.connect(_on_action)
	_empty_state.visible = visible_items.is_empty()
	_item_count.text = "%d %s" % [
		visible_items.size(),
		_position_word(visible_items.size()),
	]


func _on_selected(stack_id: String) -> void:
	var next_selected := "" if stack_id == _selected_stack_id else stack_id
	action_requested.emit(next_selected, "select", 0, "")


func _on_action(stack_id: String, _action_id: String, action_model: Dictionary) -> void:
	for raw_item in _items:
		if raw_item is Dictionary and String(raw_item.get("stack_id", "")) == stack_id:
			_sheet.open(raw_item, action_model)
			return


func _retry_action(stack_id: String, action_id: String) -> void:
	for raw_item in _items:
		if not raw_item is Dictionary or String(raw_item.get("stack_id", "")) != stack_id:
			continue
		for raw_action in Array(raw_item.get("actions", [])):
			if raw_action is Dictionary and String(raw_action.get("id", "")) == action_id:
				_sheet.open(raw_item, raw_action)
				return


func _on_filter_changed(_index: int) -> void:
	if not _building_filters:
		_rebuild_items()


func _matches_kind(item: Dictionary, kind: String) -> bool:
	if kind.is_empty():
		return true
	var tags: Array = item.get("tags", [])
	var action_ids: Array[String] = []
	for raw_action in Array(item.get("actions", [])):
		if raw_action is Dictionary:
			action_ids.append(String(raw_action.get("id", "")))
	match kind:
		"usable":
			return "use" in action_ids or "disassemble" in action_ids
		"material":
			return "Материал" in tags or "Вторсырьё" in tags
		"care":
			return "Еда" in tags or "Медицина" in tags
	return true


func _sort_items(items: Array, sort_id: String) -> void:
	items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		match sort_id:
			"mass":
				return _mass_value(left) > _mass_value(right)
			"container":
				return String(left.get("container_title", "")).naturalnocasecmp_to(
					String(right.get("container_title", ""))
				) < 0
			_:
				return String(left.get("title", "")).naturalnocasecmp_to(
					String(right.get("title", ""))
				) < 0
	)


func _mass_value(item: Dictionary) -> int:
	return int(item.get("mass_grams", 0))


func _selected_metadata(picker: OptionButton) -> String:
	return (
		String(picker.get_item_metadata(picker.selected))
		if picker.item_count > 0 and picker.selected >= 0
		else ""
	)


func _select_metadata(picker: OptionButton, wanted: String) -> void:
	for index in range(picker.item_count):
		if String(picker.get_item_metadata(index)) == wanted:
			picker.select(index)
			return
	if picker.item_count > 0:
		picker.select(0)


func _capture_view_state() -> Dictionary:
	return {
		"container": _selected_metadata(_container_filter),
		"kind": _selected_metadata(_kind_filter),
		"sort": _selected_metadata(_sort_picker),
		"scroll": _scroll.scroll_vertical,
	}


func _queue_scroll_restore(value: int) -> void:
	_pending_scroll = maxi(value, 0)
	_scroll_restore_frames = 3
	set_process(true)


func _capacity_card_model(raw: Variant, icon: String, title: String) -> Dictionary:
	var model: Dictionary = Dictionary(raw).duplicate(true) if raw is Dictionary else {}
	model["icon"] = icon
	model["title"] = title
	return model


static func _position_word(count: int) -> String:
	var last_two := count % 100
	if last_two >= 11 and last_two <= 14:
		return "позиций"
	match count % 10:
		1:
			return "позиция"
		2, 3, 4:
			return "позиции"
		_:
			return "позиций"
