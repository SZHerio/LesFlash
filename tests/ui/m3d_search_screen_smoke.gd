extends SceneTree

const SearchScreenScene := preload("res://ui/screens/search/search_screen.tscn")
const Fixture := preload("res://tests/ui/m3d_search_ui_fixture.gd")
const ApproachRowScript := preload("res://ui/components/search_approach_row.gd")
const CapacitySheetScript := preload(
	"res://ui/components/search_capacity_conflict_sheet.gd"
)
const TEST_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(540, 960)]

var _failures: Array[String] = []
var _moves: Array = []
var _interaction: Array = []
var _pickup: Array = []
var _replacement: Array = []
var _recovery: Array = []
var _finish_count := 0
var _quick_count := 0
var _checkpoint: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for test_size: Vector2i in TEST_SIZES:
		await _exercise(test_size, 1.0)
		await _exercise(test_size, 2.0)
	if _failures.is_empty():
		print("M3D SEARCH SCREEN SMOKE PASSED: 360x640, 540x960 and 200% text")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M3D SEARCH SCREEN: %s" % failure)
	quit(1)


func _exercise(test_size: Vector2i, font_scale: float) -> void:
	_reset_intents()
	var viewport := SubViewport.new()
	viewport.size = test_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := SearchScreenScene.instantiate() as SearchScreen
	_require(screen != null, "%s/%s screen did not instantiate" % [test_size, font_scale])
	if screen == null:
		viewport.queue_free()
		return
	screen.theme = Fixture.scaled_theme(font_scale)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connect_intents(screen)
	viewport.add_child(screen)
	screen.present(Fixture.model(font_scale))
	for _frame: int in range(6):
		await process_frame
	_check_layout(screen, test_size, font_scale)
	if is_equal_approx(font_scale, 1.0):
		await _check_interaction(screen)
		await _check_capacity(screen, test_size)
		await _check_movement(screen)
	else:
		await _check_scaled_modal(screen, test_size)
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _check_layout(
	screen: SearchScreen,
	test_size: Vector2i,
	font_scale: float
) -> void:
	_require(absf(screen.size.x - test_size.x) <= 2.0, "%s wrong screen width" % test_size)
	_require(absf(screen.size.y - test_size.y) <= 2.0, "%s wrong screen height" % test_size)
	var world := screen.get_node("%SearchWorld") as SearchWorld
	_require(world.size.x >= test_size.x - 40.0, "%s world is too narrow" % test_size)
	_require(world.size.y >= 218.0, "%s world is too short" % test_size)
	_require(
		world.get_global_rect().end.y <= test_size.y + 1.0,
		"%s/%s world escaped viewport" % [test_size, font_scale]
	)
	for button_name: String in ["Finish", "QuickSearch"]:
		var button := screen.get_node("%%%s" % button_name) as Button
		_require(
			button != null and button.size.y >= 48.0,
			"%s/%s %s touch target below 48" % [test_size, font_scale, button_name]
		)
	var tray := screen.get_node("%LootTray") as SearchLootTray
	_require(tray.visible, "%s loot tray is not visible" % test_size)
	_require(
		(tray.get_node("%Pickup") as Button).size.y >= 48.0,
		"%s pickup target below 48" % test_size
	)
	var material := world.material as ShaderMaterial
	_require(material != null, "%s world has no psyche shader" % test_size)
	if material != null:
		_require(
			is_equal_approx(
				float(material.get_shader_parameter("psyche_intensity")),
				0.65
			),
			"%s psyche intensity was not applied to world" % test_size
		)
	_require(
		String((screen.get_node("%Repeated") as Label).text).contains("2"),
		"%s repeated-attempt risk is not visible" % test_size
	)
	var object_position := world.object_screen_position("open_dumpster")
	_require(
		object_position.x >= -72.0 and object_position.y >= -72.0,
		"%s array object position was not mapped into the world" % test_size
	)


func _check_interaction(screen: SearchScreen) -> void:
	var world := screen.get_node("%SearchWorld") as SearchWorld
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.position = Vector2(28, 28)
	tap.pressed = true
	world.call("_gui_input", tap)
	_require(_moves.size() == 2, "tap-to-move did not emit a typed target")
	world.object_requested.emit("open_dumpster")
	await process_frame
	var sheet := screen.get_node("%InteractionSheet") as SearchInteractionSheet
	_require(sheet.is_open(), "nearby object did not open interaction sheet")
	var rows := sheet.get_node("%Actions").get_children()
	_require(rows.size() == 2, "all authored approaches were not rendered")
	if rows.size() >= 2:
		var blocked := rows[0] as ApproachRowScript
		var enabled := rows[1] as ApproachRowScript
		_require(
			(blocked.get_node("%Blocked") as Label).visible,
			"blocked reason is invisible on touch UI"
		)
		_require(blocked.action_button().disabled, "blocked approach can be confirmed")
		_require(enabled.action_button().size.y >= 48.0, "approach target below 48")
		enabled.action_button().pressed.emit()
		_require(
			_interaction == ["open_dumpster", "search_slowly"],
			"interaction intent lost object or approach id"
		)
	world.object_requested.emit("open_dumpster")
	await process_frame
	var finish_before := _finish_count
	_require(screen.handle_back(), "Back was not consumed by interaction sheet")
	_require(not sheet.is_open(), "Back left interaction sheet open")
	_require(_finish_count == finish_before, "modal Back also finished search")


func _check_capacity(screen: SearchScreen, test_size: Vector2i) -> void:
	screen.show_capacity_conflict(Fixture.capacity_model())
	await process_frame
	var sheet := screen.get_node("%CapacitySheet") as CapacitySheetScript
	_require(sheet.is_open(), "capacity conflict did not open")
	var picker := sheet.get_node("%ReplacementPicker") as OptionButton
	_require(picker.item_count == 1, "replacement comparison was not rendered")
	for button_name: String in ["OtherContainer", "Leave", "Replace"]:
		var button := sheet.get_node("%%%s" % button_name) as Button
		_require(button.size.y >= 48.0, "%s %s target below 48" % [test_size, button_name])
	(sheet.get_node("%Replace") as Button).pressed.emit()
	_require(
		_replacement == ["ground:loot:1", "stack:coat", "hands"],
		"atomic replacement intent lost a participant"
	)
	screen.show_capacity_conflict(Fixture.capacity_model())
	await process_frame
	var finish_before := _finish_count
	screen.handle_back()
	_require(not sheet.is_open(), "Back left capacity conflict open")
	_require(_finish_count == finish_before, "capacity Back also finished search")
	screen.show_capacity_conflict(Fixture.capacity_model())
	await process_frame
	(sheet.get_node("%OtherContainer") as Button).pressed.emit()
	_require(
		_recovery == ["ground:loot:1", "choose_other_container"],
		"capacity recovery intent was not typed"
	)
	var tray := screen.get_node("%LootTray") as SearchLootTray
	(tray.get_node("%Pickup") as Button).pressed.emit()
	_require(
		_pickup == ["ground:loot:1", "pockets"],
		"loot pickup id or target container was lost"
	)
	(screen.get_node("%QuickSearch") as Button).pressed.emit()
	_require(_quick_count == 1, "quick-search intent was not emitted")
	screen.handle_back()
	_require(_finish_count == 1, "Back outside a modal did not request finish")


func _check_movement(screen: SearchScreen) -> void:
	_checkpoint.clear()
	screen.set_reduced_motion(true)
	screen.animate_path([[823, 912], [909, 596]], "open_dumpster")
	await process_frame
	_require(
		_checkpoint.size() == 3
		and _checkpoint[0] == Vector2(909, 596)
		and _checkpoint[1] == 2
		and bool(_checkpoint[2]),
		"reduced-motion path did not finish deterministically"
	)
	var world := screen.get_node("%SearchWorld") as SearchWorld
	_require(not world.is_moving(), "reduced-motion path stayed active")


func _check_scaled_modal(screen: SearchScreen, test_size: Vector2i) -> void:
	var world := screen.get_node("%SearchWorld") as SearchWorld
	world.object_requested.emit("open_dumpster")
	await process_frame
	var sheet := screen.get_node("%InteractionSheet") as SearchInteractionSheet
	var scroll := sheet.get_node("%Scroll") as ScrollContainer
	_require(scroll.size.y >= 100.0, "%s 200%% sheet has no usable scroll" % test_size)
	_require(
		scroll.get_global_rect().end.y <= test_size.y + 1.0,
		"%s 200%% interaction sheet escaped viewport" % test_size
	)
	var rows := sheet.get_node("%Actions").get_children()
	if not rows.is_empty():
		var button := (rows[0] as ApproachRowScript).action_button()
		_require(button.size.y >= 48.0, "%s 200%% approach target below 48" % test_size)
	screen.handle_back()
	screen.show_capacity_conflict(Fixture.capacity_model())
	await process_frame
	var capacity := screen.get_node("%CapacitySheet") as CapacitySheetScript
	var capacity_scroll := capacity.get_node("%Scroll") as ScrollContainer
	_require(
		capacity_scroll.get_global_rect().end.y <= test_size.y + 1.0,
		"%s 200%% capacity sheet escaped viewport" % test_size
	)
	screen.handle_back()


func _connect_intents(screen: SearchScreen) -> void:
	screen.move_requested.connect(func(target: Vector2, focus_id: String) -> void:
		_moves = [target, focus_id]
	)
	screen.interaction_requested.connect(func(object_id: String, approach_id: String) -> void:
		_interaction = [object_id, approach_id]
	)
	screen.pickup_requested.connect(func(
		stack_id: String,
		target_container_id: String
	) -> void:
		_pickup = [stack_id, target_container_id]
	)
	screen.replacement_requested.connect(func(
		incoming_id: String,
		displaced_id: String,
		container_id: String
	) -> void:
		_replacement = [incoming_id, displaced_id, container_id]
	)
	screen.capacity_recovery_requested.connect(func(
		incoming_id: String,
		recovery_id: String
	) -> void:
		_recovery = [incoming_id, recovery_id]
	)
	screen.finish_requested.connect(func() -> void: _finish_count += 1)
	screen.quick_search_requested.connect(func() -> void: _quick_count += 1)
	screen.movement_checkpoint.connect(func(
		position: Vector2,
		index: int,
		completed: bool
	) -> void:
		_checkpoint = [position, index, completed]
	)


func _reset_intents() -> void:
	_moves.clear()
	_interaction.clear()
	_pickup.clear()
	_replacement.clear()
	_recovery.clear()
	_finish_count = 0
	_quick_count = 0
	_checkpoint.clear()


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
