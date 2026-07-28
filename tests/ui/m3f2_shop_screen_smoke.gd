extends SceneTree

const ShopScreenScene := preload("res://ui/screens/shop/shop_screen.tscn")
const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _failures: Array[String] = []
var _last_purchase: Array = []
var _back_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size in TEST_SIZES:
		await _exercise(test_size, 1.0)
		await _exercise(test_size, 2.0)
	await _exercise_states()
	if _failures.is_empty():
		print("M3F.2 SHOP SCREEN SMOKE PASSED: 360x640 / 540x960 at 100/200%")
		quit(0)
		return
	for failure in _failures:
		push_error("M3F.2 SHOP SCREEN: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i, scale: float) -> void:
	var setup := _spawn(test_size, scale)
	var viewport: SubViewport = setup[0]
	var screen: ShopScreen = setup[1]
	screen.apply_model(_open_model())
	for _frame in range(5):
		await process_frame
	var scroll := screen.get_node("%OffersScroll") as ScrollContainer
	_require(absf(screen.size.x - test_size.x) <= 2.0, "%s %.0f%% wrong width" % [test_size, scale * 100.0])
	_require(scroll.size.y >= 120.0, "%s %.0f%% scroll collapsed" % [test_size, scale * 100.0])
	_require(not scroll.get_h_scroll_bar().visible, "%s %.0f%% content spills sideways" % [test_size, scale * 100.0])
	_check_touch_targets(screen, test_size, scale)
	var rows := screen.get_node("%OfferList").get_children()
	_require(rows.size() == 4, "%s %.0f%% offers missing" % [test_size, scale * 100.0])
	for raw_row in rows:
		var row := raw_row as ShopOfferRow
		_require(row != null, "offer is not a ShopOfferRow")
		if row != null:
			_require((row.get_node("%TitleLabel") as Label).autowrap_mode != TextServer.AUTOWRAP_OFF, "long title cannot wrap")
	await _check_purchase(screen)
	(screen.get_node("%BackButton") as Button).pressed.emit()
	_require(_back_count > 0, "Back intent was not emitted")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _exercise_states() -> void:
	var setup := _spawn(Vector2i(360, 640), 1.0)
	var viewport: SubViewport = setup[0]
	var screen: ShopScreen = setup[1]
	var closed := _open_model()
	closed["open"] = false
	closed["availability"] = {"reason": "Сегодня комиссионка работает с 10:00 до 18:00"}
	screen.apply_model(closed)
	await process_frame
	_require((screen.get_node("%ClosedState") as Control).visible, "closed state is hidden")
	_require(not (screen.get_node("%OfferList") as Control).visible, "closed store still shows offers")
	var empty := _open_model()
	empty["offers"] = []
	screen.apply_model(empty)
	await process_frame
	_require((screen.get_node("%EmptyState") as Control).visible, "empty state is hidden")
	_require(not (screen.get_node("%ClosedState") as Control).visible, "empty open store looks closed")
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _spawn(test_size: Vector2i, scale: float) -> Array:
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := ShopScreenScene.instantiate() as ShopScreen
	_require(screen != null, "%s screen could not instantiate" % test_size)
	if screen == null:
		return [viewport, null]
	screen.theme = _scaled_theme(scale)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.purchase_requested.connect(func(
		store_id: String,
		offer_id: String,
		quantity: int,
		target_id: String,
		revision: int
	) -> void:
		_last_purchase = [store_id, offer_id, quantity, target_id, revision]
	)
	screen.back_requested.connect(func() -> void: _back_count += 1)
	viewport.add_child(screen)
	return [viewport, screen]


func _check_purchase(screen: ShopScreen) -> void:
	var first := screen.get_node("%OfferList").get_child(0) as ShopOfferRow
	_last_purchase.clear()
	(first.get_node("%IncreaseButton") as Button).pressed.emit()
	(first.get_node("%BuyButton") as Button).pressed.emit()
	_require(
		_last_purchase == ["store_market_food_row", "offer:bread:0", 2, "pockets", 7],
		"purchase intent lost store, quantity, target or revision: %s" % str(_last_purchase)
	)
	var expensive := screen.get_node("%OfferList").get_child(3) as ShopOfferRow
	_require((expensive.get_node("%BuyButton") as Button).disabled, "unaffordable offer is enabled")
	_require((expensive.get_node("%ReasonLabel") as Label).visible, "unaffordable reason is hidden")


func _check_touch_targets(node: Node, test_size: Vector2i, scale: float) -> void:
	for child in node.get_children():
		var button := child as BaseButton
		if button != null and button.is_visible_in_tree():
			_require(
				button.size.x >= 48.0 and button.size.y >= 48.0,
				"%s %.0f%% %s touch target %.0fx%.0f" % [
					test_size, scale * 100.0, button.name, button.size.x, button.size.y,
				]
			)
		_check_touch_targets(child, test_size, scale)


func _open_model() -> Dictionary:
	return {
		"store_id": "store_market_food_row",
		"title": "Рыночный продовольственный ряд Тамары Беловой",
		"money": 190,
		"open": true,
		"availability": {"reason": "Открыто до 18:00"},
		"revision": 7,
		"target_container_id": "pockets",
		"offers": [
			{"offer_id": "offer:bread:0", "item_id": "rye_bread", "title": "Большая буханка свежего ржаного хлеба", "quantity": 4, "unit_price": 42, "condition": 95, "quality": 70},
			{"offer_id": "offer:tea:0", "item_id": "tea", "title": "Стакан крепкого чая без сахара", "quantity": 3, "unit_price": 18, "condition": 100, "quality": 61},
			{"offer_id": "offer:soap:0", "item_id": "soap", "title": "Простое хозяйственное мыло", "quantity": 2, "unit_price": 31, "condition": 100, "quality": 76},
			{"offer_id": "offer:coat:0", "item_id": "coat", "title": "Тёплое непромокаемое пальто с длинным названием", "quantity": 1, "unit_price": 420, "condition": 63, "quality": 58},
		],
	}


func _scaled_theme(scale: float) -> Theme:
	var result := UiTheme.duplicate(true) as Theme
	result.default_font_size = int(round(float(UiTheme.default_font_size) * scale))
	return result


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
