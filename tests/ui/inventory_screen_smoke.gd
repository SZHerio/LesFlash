extends SceneTree

const InventoryScreenScene := preload("res://ui/screens/inventory/inventory_screen.tscn")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _failures: Array[String] = []
var _last_intent: Array = []
var _last_replacement: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise(test_size)
	if _failures.is_empty():
		print("M3C INVENTORY SCREEN SMOKE PASSED: 360x640 and 540x960 at 100/200%")
		quit(0)
		return
	for failure in _failures:
		push_error("M3C INVENTORY SCREEN: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := InventoryScreenScene.instantiate() as InventoryScreen
	_require(screen != null, "%s screen could not instantiate" % test_size)
	if screen == null:
		return
	screen.theme = UiTheme
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.action_requested.connect(func(
		stack_id: String,
		action_id: String,
		quantity: int,
		target_id: String
	) -> void:
		_last_intent = [stack_id, action_id, quantity, target_id]
	)
	screen.replacement_requested.connect(func(
		incoming_id: String,
		displaced_id: String,
		target_id: String
	) -> void:
		_last_replacement = [incoming_id, displaced_id, target_id]
	)
	viewport.add_child(screen)
	var model := _model()
	_add_overflow_items(model)
	screen.present(model)
	for _frame in range(5):
		await process_frame
	_check_layout(screen, test_size)
	await _check_intents(screen, model)
	screen.theme = _scaled_theme(2.0)
	for _frame in range(4):
		await process_frame
	_check_layout(screen, test_size)
	_open_detail_sheet(screen)
	await process_frame
	var sheet := screen.get_node("%ActionSheet") as InventoryActionSheet
	var sheet_scroll := sheet.get_node("%SheetScroll") as ScrollContainer
	_require(sheet_scroll.size.y >= 100.0, "%s 200%% action sheet has no usable scroll" % test_size)
	_require(
		sheet_scroll.get_global_rect().end.y <= test_size.y + 1.0,
		"%s 200%% action sheet escaped viewport" % test_size
	)
	screen.handle_back()
	screen.set_reduced_motion(true)
	var scroll := screen.get_node("%InventoryScroll") as ScrollContainer
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await process_frame
	_require(
		scroll.get_global_rect().end.y <= test_size.y + 1.0,
		"%s 200%% scroll escaped viewport" % test_size
	)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_layout(screen: InventoryScreen, test_size: Vector2i) -> void:
	_require(absf(screen.size.x - test_size.x) <= 2.0, "%s wrong screen width" % test_size)
	var scroll := screen.get_node("%InventoryScroll") as ScrollContainer
	_require(scroll.size.y >= 220.0, "%s inventory scroll is too short" % test_size)
	for name in ["ContainerFilter", "KindFilter", "SortPicker"]:
		var button := screen.get_node("%%%s" % name) as BaseButton
		_require(
			button != null and button.size.y >= 48.0,
			"%s %s touch target below 48" % [test_size, name]
		)
	var cards := screen.get_node("%ItemsList").get_children()
	_require(cards.size() == 7, "%s long Russian item cards were not rendered" % test_size)
	for card in cards:
		var title := card.get_node("%TitleLabel") as Label
		_require(title.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s item title cannot wrap" % test_size)
	if not cards.is_empty():
		_require(
			cards[0].get_global_rect().position.y < scroll.get_global_rect().end.y,
			"%s first item is hidden below the initial fold" % test_size
		)


func _check_intents(screen: InventoryScreen, source_model: Dictionary) -> void:
	var container_filter := screen.get_node("%ContainerFilter") as OptionButton
	var sort_picker := screen.get_node("%SortPicker") as OptionButton
	container_filter.select(1)
	sort_picker.select(1)
	container_filter.item_selected.emit(1)
	sort_picker.item_selected.emit(1)
	await process_frame
	var scroll := screen.get_node("%InventoryScroll") as ScrollContainer
	var scroll_target := mini(18, int(scroll.get_v_scroll_bar().max_value))
	scroll.scroll_vertical = scroll_target
	await process_frame
	scroll_target = scroll.scroll_vertical
	_last_intent.clear()
	var first := screen.get_node("%ItemsList").get_child(0) as InventoryItemCard
	first.get_node("%HeaderButton").pressed.emit()
	_require(_last_intent.size() == 4 and _last_intent[1] == "select", "selection intent was lost")
	var updated := source_model.duplicate(true)
	updated["selected_stack_id"] = String(_last_intent[0])
	var selected_id := String(_last_intent[0])
	screen.present(updated)
	await process_frame
	await process_frame
	await process_frame
	_require(container_filter.selected == 1, "container filter reset after model update")
	_require(sort_picker.selected == 1, "sort order reset after model update")
	if scroll_target > 0:
		var expected_scroll := mini(scroll_target, int(scroll.get_v_scroll_bar().max_value))
		_require(
			scroll.scroll_vertical == expected_scroll,
			"scroll position reset after model update (%d → %d at %s)" % [
				expected_scroll,
				scroll.scroll_vertical,
				str(screen.get_viewport_rect().size),
			]
		)
	first = _card_by_stack(screen, selected_id)
	_require(first != null and first.is_expanded(), "selected card did not expand")
	if first == null:
		return
	_last_intent.clear()
	first.get_node("%HeaderButton").pressed.emit()
	_require(
		_last_intent.size() == 4 and String(_last_intent[0]).is_empty(),
		"expanded card cannot be collapsed"
	)
	_last_intent.clear()
	var action_button := first.get_node("%Actions").get_child(0) as Button
	action_button.pressed.emit()
	var sheet := screen.get_node("%ActionSheet") as InventoryActionSheet
	_require(sheet.visible, "item action did not open confirmation sheet")
	_require(screen.handle_back(), "Back did not close action sheet")
	_require(not sheet.visible, "Back left action sheet visible")

	container_filter.select(0)
	screen.get_node("%KindFilter").select(0)
	screen.get_node("%SortPicker").select(0)
	screen.get_node("%ContainerFilter").item_selected.emit(0)
	var external := _card_with_action(screen, "Забрать")
	_require(external != null, "external pickup card was not rendered")
	if external == null:
		return
	var pickup := external.get_node("%Actions").get_child(0) as Button
	pickup.pressed.emit()
	_require(sheet.visible, "external pickup did not open action sheet")
	(sheet.get_node("%IncreaseQuantityButton") as Button).pressed.emit()
	sheet.get_node("%ConfirmButton").pressed.emit()
	_require(_last_intent.size() == 4, "confirmed action did not emit typed intent")
	_require(
		_last_intent[1] == "pick_up" and _last_intent[2] == 2 and not String(_last_intent[3]).is_empty(),
		"pickup quantity or target was lost"
	)

	_last_replacement.clear()
	screen.show_capacity_conflict({
		"code": "capacity_conflict",
		"incoming": {
			"stack_id": "stack:external",
			"title": "Пластиковые бутылки",
			"mass_grams": 90,
			"volume_ml": 1400,
		},
		"container_id": "pockets",
		"capacity": {
			"mass_used_grams": 1700,
			"mass_capacity_grams": 2080,
			"volume_used_ml": 2700,
			"volume_capacity_ml": 3200,
		},
		"comparison": [{
			"stack_id": "stack:000001",
			"title": "Лист картона",
			"mass_grams": 340,
			"volume_ml": 1800,
		}],
		"recoveries": ["choose_other_container", "replace", "leave_at_source"],
	})
	_require(sheet.visible, "capacity conflict did not open recovery sheet")
	_require(
		(sheet.get_node("%ReplacementPicker") as OptionButton).item_count == 1,
		"capacity comparison was not rendered"
	)
	sheet.get_node("%ConfirmButton").pressed.emit()
	_require(
		_last_replacement == ["stack:external", "stack:000001", "pockets"],
		"replacement intent lost one of its atomic participants"
	)


func _open_detail_sheet(screen: InventoryScreen) -> void:
	var cards := screen.get_node("%ItemsList").get_children()
	if cards.is_empty():
		return
	var card := cards[0] as InventoryItemCard
	if card.get_node("%Actions").get_child_count() > 0:
		(card.get_node("%Actions").get_child(0) as Button).pressed.emit()


func _card_with_action(screen: InventoryScreen, action_title: String) -> InventoryItemCard:
	for child in screen.get_node("%ItemsList").get_children():
		var card := child as InventoryItemCard
		if card == null:
			continue
		for raw_button in card.get_node("%Actions").get_children():
			var button := raw_button as Button
			if button != null and button.text == action_title:
				return card
	return null


func _card_by_stack(screen: InventoryScreen, stack_id: String) -> InventoryItemCard:
	for child in screen.get_node("%ItemsList").get_children():
		var card := child as InventoryItemCard
		if card != null and card.stack_id() == stack_id:
			return card
	return null


func _add_overflow_items(model: Dictionary) -> void:
	var items: Array = model.get("items", [])
	var source: Dictionary = Dictionary(items[1])
	for index in range(4):
		var copy := source.duplicate(true)
		copy["stack_id"] = "stack:overflow:%d" % index
		copy["title"] = "Запасной предмет для проверки прокрутки %d" % (index + 1)
		copy["container_id"] = "pockets"
		copy["container_title"] = "Карманы"
		items.append(copy)
	model["items"] = items


func _model() -> Dictionary:
	return {
		"header": {
			"district_title": "ПРИРЕЧНЫЙ РАЙОН",
			"location_title": "Вещи",
			"date_text": "1 сентября 1970",
			"time_text": "08:00",
			"money": 17,
			"show_settings": true,
		},
		"location_title": "Старый подземный переход у вокзальной площади",
		"summary": {
			"mass": {"ratio": 0.72, "value_text": "4,8 / 6,7 кг", "state": "normal"},
			"volume": {"ratio": 0.91, "value_text": "8,2 / 9,0 л", "state": "warning"},
			"overloaded": false,
			"message": "Сила увеличивает переносимую массу, но не объём контейнеров.",
		},
		"containers": [
			{"id": "pockets", "title": "Карманы", "active": true, "count": 1},
			{"id": "hands", "title": "В руках", "active": true, "count": 1},
		],
		"selected_stack_id": "",
		"reduced_motion": false,
		"items": [
			{
				"stack_id": "stack:000001",
				"item_id": "cardboard_sheet",
				"title": "Очень длинное русское название большого листа сухого гофрированного картона",
				"description": "Сухой материал для ночлега. Текст должен переноситься без обрезания.",
				"quantity": 1,
				"quantity_text": "",
				"container_id": "pockets",
				"container_title": "Карманы",
				"mass_text": "340 г",
				"volume_text": "1,8 л",
				"condition_text": "Хорошее состояние",
				"tags": ["Материал", "Ночлег"],
				"mass_grams": 340,
				"volume_ml": 1800,
				"actions": [{
					"id": "move",
					"title": "Переложить",
					"kind": "move",
					"duration_text": "Время не изменится",
					"effect_lines": [],
					"output_lines": [],
					"condition_lines": [],
					"quantity_adjustable": false,
					"max_quantity": 1,
				}],
				"move_targets": [
					{"id": "pockets", "title": "Карманы"},
					{"id": "hands", "title": "В руках"},
				],
			},
			{
				"stack_id": "stack:000002",
				"item_id": "medicine_blister",
				"title": "Целый блистер обезболивающего",
				"description": "Маркировка читается.",
				"quantity": 1,
				"quantity_text": "",
				"container_id": "hands",
				"container_title": "В руках",
				"mass_text": "24 г",
				"volume_text": "35 мл",
				"condition_text": "Хорошее состояние",
				"tags": ["Медицина"],
				"mass_grams": 24,
				"volume_ml": 35,
				"actions": [{
					"id": "use",
					"title": "Принять таблетку",
					"kind": "normal",
					"duration_text": "Время: 3 мин.",
					"effect_lines": ["Здоровье: +5", "Напряжение: −4"],
					"output_lines": [],
					"condition_lines": [],
					"quantity_adjustable": false,
					"max_quantity": 1,
				}],
				"move_targets": [
					{"id": "pockets", "title": "Карманы"},
					{"id": "hands", "title": "В руках"},
				],
			},
			{
				"stack_id": "stack:external",
				"item_id": "plastic_bottle",
				"title": "Пластиковые бутылки рядом",
				"description": "Две чистые бутылки лежат у стены.",
				"quantity": 2,
				"quantity_text": "×2",
				"container_id": "ground:underpass",
				"container_title": "На земле",
				"mass_text": "90 г",
				"volume_text": "1,4 л",
				"mass_grams": 90,
				"volume_ml": 1400,
				"condition_text": "Хорошее состояние",
				"tags": ["Вторсырьё"],
				"external": true,
				"actions": [{
					"id": "pick_up",
					"title": "Забрать",
					"kind": "accent",
					"duration_text": "Время не изменится",
					"effect_lines": [],
					"output_lines": [],
					"condition_lines": [],
					"quantity_adjustable": true,
					"max_quantity": 2,
				}],
				"move_targets": [
					{"id": "pockets", "title": "Карманы"},
					{"id": "hands", "title": "В руках"},
				],
			},
		],
	}


func _scaled_theme(scale: float) -> Theme:
	var result := UiTheme.duplicate(true) as Theme
	result.default_font_size = int(round(float(UiTheme.default_font_size) * scale))
	return result


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
