extends SceneTree

const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const InventoryTransactionScript := preload("res://core/inventory/inventory_transaction.gd")
const SessionMigration := preload("res://game/run/run_session_migration.gd")
const RunSaveScript := preload("res://game/run/run_save.gd")
const RunStateSaveScript := preload("res://core/save/run_state_save.gd")
const IntegritySuiteScript := preload("res://tests/m3c_inventory_integrity_suite.gd")
const SaveIntegritySuiteScript := preload("res://tests/m3c_inventory_save_integrity_suite.gd")
const SESSION_V2_FIXTURE := "res://tests/fixtures/m3b_session_v2.json"
const RUN_ENVELOPE_V1_FIXTURE := "res://tests/fixtures/run_state_envelope_v1.json"

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _save_path := ""
func _init() -> void:
	_save_path = ProjectSettings.globalize_path(
		"res://.godot/.m3c_inventory_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_run_test("versioned item catalog and safe fallback", _test_catalog)
	_run_test("new run has body containers but no belongings", _test_empty_inventory)
	_run_test("mass and volume are independent", _test_capacity_dimensions)
	_run_test("stack split merge and selection", _test_stack_and_selection)
	_run_test("full container preserves incoming item", _test_capacity_conflict)
	_run_test("replacement swaps items atomically", _test_atomic_replacement)
	_run_test("use and disassembly are atomic", _test_item_actions)
	_run_test("drop persists outside carried inventory", _test_drop)
	_run_test("v2 session fixture migrates every layer", _test_v2_fixture)
	_run_test("malformed legacy payload is non-destructive", _test_bad_migration)
	_run_test("standalone envelope migrates and current state round-trips", _test_save_round_trip)
	_run_test("metadata, compact migration and action integrity", _test_integrity_suite)
	_cleanup_save()

	if _failures.is_empty():
		print("M3C INVENTORY TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3C INVENTORY TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)
func _test_catalog() -> void:
	var validation := ItemCatalogScript.validation()
	_expect(bool(validation.get("ok", false)), "catalog must validate: %s" % str(validation.get("errors", [])))
	for item_id in ["cardboard_sheet", "simple_meal", "scrap_wire", "recyclables"]:
		_expect(ItemCatalogScript.has(item_id), "legacy item must be defined: %s" % item_id)
	var fallback = ItemCatalogScript.definition("forgotten_v2_item")
	_expect(fallback.is_unknown(), "unknown old id must resolve to a safe fallback")
	_expect_equal(fallback.id(), "forgotten_v2_item", "fallback must preserve original id")
	_expect_equal(fallback.allowed_actions(), ["drop"], "fallback must not become usable or sellable")
func _test_empty_inventory() -> void:
	var state := RunState.new(_build(), 41_001)
	var validation := InventoryStateScript.validate(state.inventory)
	_expect(bool(validation.get("ok", false)), "fresh inventory must validate")
	_expect(InventoryStateScript.all_stacks(state.inventory).is_empty(), "new hero must own no items")
	_expect(not bool(state.inventory["containers"]["backpack"]["active"]), "new hero must not start with a backpack")
	_expect_equal(state.get_skill_rank("search"), 0, "search skill must start unopened")


func _test_capacity_dimensions() -> void:
	var inventory := InventoryStateScript.fresh()
	var weak := InventoryStateScript.capacity(inventory, "pockets", 1)
	var strong := InventoryStateScript.capacity(inventory, "pockets", 10)
	_expect(
		int(strong.get("mass_capacity_grams", 0)) > int(weak.get("mass_capacity_grams", 0)),
		"Strength must increase mass capacity"
	)
	_expect_equal(
		strong.get("volume_capacity_ml"),
		weak.get("volume_capacity_ml"),
		"Strength must not change volume"
	)


func _test_stack_and_selection() -> void:
	var state := RunState.new(_build(), 41_002)
	_expect(state.add_item("scrap_wire", 10), "ten wire pieces must fit across stacks")
	var stacks: Array = InventoryStateScript.all_stacks(state.inventory)
	_expect_equal(stacks.size(), 2, "stack limit eight must split ten items")
	var stack_id := String(stacks[0].get("stack_id", ""))
	var selected := InventoryTransactionScript.select(state, stack_id)
	_expect(bool(selected.get("ok", false)), "selection must commit")
	var restored := RunState.from_dict(state.to_dict())
	_expect(restored != null, "selected inventory must deserialize")
	if restored != null:
		_expect_equal(
			restored.inventory.get("selected_stack_id"),
			stack_id,
			"selected stack must survive serialization"
		)


func _test_capacity_conflict() -> void:
	var inventory := InventoryStateScript.fresh()
	var before := inventory.duplicate(true)
	var result := InventoryStateScript.add_item(
		inventory,
		"blanket_roll",
		1,
		100,
		"pockets",
		1
	)
	_expect_equal(result.get("code"), "capacity_conflict", "oversized find must return an explicit conflict")
	_expect_equal(inventory, before, "failed pickup preview must not mutate inventory")
	_expect(result.get("incoming", {}) is Dictionary, "conflict must retain incoming item details")
	_expect(result.get("comparison", []) is Array, "conflict must expose replacement comparison")


func _test_atomic_replacement() -> void:
	var state := RunState.new(_build(), 41_006)
	_expect(state.add_item("cardboard_sheet", 1, "pockets"), "cardboard fixture must fit")
	_expect(state.add_item("recyclables", 1, "pockets"), "recyclables fixture must fit")
	state.inventory = InventoryStateScript.ensure_external_container(
		state.inventory,
		"ground:test",
		"На земле"
	)
	var addition := InventoryStateScript.add_item(
		state.inventory,
		"plastic_bottle",
		1,
		100,
		"ground:test",
		state.get_characteristic("strength")
	)
	_expect(bool(addition.get("ok", false)), "incoming ground item fixture must be created")
	if not bool(addition.get("ok", false)):
		return
	state.inventory = addition["inventory"]
	var incoming := _stack_for_anywhere(state, "plastic_bottle")
	var displaced := _stack_for(state, "recyclables")
	var result := InventoryTransactionScript.replace(
		state,
		String(incoming.get("stack_id", "")),
		String(displaced.get("stack_id", "")),
		"pockets"
	)
	_expect(bool(result.get("ok", false)), "compound replacement must commit")
	_expect_equal(state.get_item_count("plastic_bottle"), 1, "incoming item must become carried")
	_expect_equal(state.get_item_count("recyclables"), 0, "displaced item must stop counting as carried")
	var moved := _stack_for_anywhere(state, "recyclables")
	_expect_equal(moved.get("container_id"), "ground:test", "displaced item must persist at incoming source")


func _test_item_actions() -> void:
	var state := RunState.new(_build(), 41_003)
	state.set_meter("hunger", 60)
	_expect(state.add_item("simple_meal", 1), "meal fixture must fit")
	var meal := _stack_for(state, "simple_meal")
	var before_time := state.calendar.elapsed_minutes
	var eaten := InventoryTransactionScript.use(state, String(meal.get("stack_id", "")))
	_expect(bool(eaten.get("ok", false)), "meal use must commit")
	_expect_equal(state.get_item_count("simple_meal"), 0, "used meal must be consumed")
	_expect(state.get_meter("hunger") < 60, "meal must reduce hunger")
	_expect_equal(state.calendar.elapsed_minutes - before_time, 12, "use must advance only its declared time")

	_expect(state.add_item("scrap_wire", 1), "wire fixture must fit")
	var wire := _stack_for(state, "scrap_wire")
	var dismantled := InventoryTransactionScript.disassemble(state, String(wire.get("stack_id", "")))
	_expect(bool(dismantled.get("ok", false)), "wire disassembly must commit")
	_expect_equal(state.get_item_count("scrap_wire"), 0, "source item must be consumed")
	_expect_equal(state.get_item_count("copper_scrap"), 1, "declared output must be created")


func _test_drop() -> void:
	var state := RunState.new(_build(), 41_004)
	_expect(state.add_item("cloth_rag", 1), "rag fixture must fit")
	var stack := _stack_for(state, "cloth_rag")
	var result := InventoryTransactionScript.drop(state, String(stack.get("stack_id", "")), "underpass")
	_expect(bool(result.get("ok", false)), "drop must commit")
	_expect_equal(state.get_item_count("cloth_rag"), 0, "dropped item must not count as carried")
	var dropped := InventoryStateScript.find_stack(state.inventory, String(stack.get("stack_id", "")))
	_expect_equal(dropped.get("container_id"), "ground:underpass", "drop must persist at the actual location")
	_expect(bool(dropped.get("external", false)), "ground item must remain external")


func _test_v2_fixture() -> void:
	var source := _read_json(SESSION_V2_FIXTURE)
	var before := JSON.stringify(source)
	var migration := SessionMigration.migrate_envelope(source)
	_expect(bool(migration.get("ok", false)), "v2 envelope migration must succeed: %s" % str(migration))
	_expect_equal(JSON.stringify(source), before, "migration must not mutate parsed source")
	_expect_equal(migration.get("source_schema_version"), 2, "source envelope version must be reported")
	_expect_equal(migration.get("source_session_version"), 2, "source session version must be reported")
	_expect_equal(migration.get("source_run_state_version"), 2, "source state version must be reported")
	var loaded := RunSaveScript.load_session(ProjectSettings.globalize_path(SESSION_V2_FIXTURE))
	_expect(bool(loaded.get("ok", false)), "real v2 fixture must load")
	if not bool(loaded.get("ok", false)):
		return
	var session = loaded.get("session")
	_expect_equal(session.run_state.get_skill_rank("search"), 0, "migration must add unopened search")
	for item_id in ["cardboard_sheet", "simple_meal", "scrap_wire", "recyclables", "legacy_mystery"]:
		_expect(session.run_state.get_item_count(item_id) > 0, "migration must preserve %s" % item_id)
	_expect(ItemCatalogScript.definition("legacy_mystery").is_unknown(), "unknown legacy id must remain recoverable")
	var ids: Array[String] = []
	for stack in InventoryStateScript.all_stacks(session.run_state.inventory):
		ids.append(String(stack.get("stack_id", "")))
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	_expect_equal(ids, sorted_ids, "legacy stack ids must be deterministic")


func _test_bad_migration() -> void:
	var source := _read_json(SESSION_V2_FIXTURE)
	source["session"]["run_state"]["inventory"]["cardboard_sheet"] = -1
	var before := JSON.stringify(source)
	var result := SessionMigration.migrate_envelope(source)
	_expect(not bool(result.get("ok", true)), "negative legacy quantity must fail migration")
	_expect_equal(JSON.stringify(source), before, "failed migration must leave source untouched")


func _test_save_round_trip() -> void:
	var legacy := RunStateSaveScript.load_state(ProjectSettings.globalize_path(RUN_ENVELOPE_V1_FIXTURE))
	_expect(bool(legacy.get("ok", false)), "standalone v1 envelope must migrate")
	_expect_equal(legacy.get("source_schema_version"), 1, "standalone source envelope must be reported")
	_expect_equal(legacy.get("source_run_state_version"), 2, "nested state source must be reported")
	if bool(legacy.get("ok", false)):
		_expect_equal(legacy.state.get_skill_rank("search"), 0, "standalone migration must add search")
		_expect_equal(legacy.state.get_item_count("legacy_mystery"), 2, "standalone migration must preserve unknown item")

	var state := RunState.new(_build(), 41_005)
	_expect(state.add_item("medicine_blister", 1), "round-trip item fixture must fit")
	var stack := _stack_for(state, "medicine_blister")
	InventoryTransactionScript.select(state, String(stack.get("stack_id", "")))
	var saved := RunStateSaveScript.save_state(state, _save_path)
	_expect(bool(saved.get("ok", false)), "current inventory save must succeed")
	var restored := RunStateSaveScript.load_state(_save_path)
	_expect(bool(restored.get("ok", false)), "current inventory save must load")
	if bool(restored.get("ok", false)):
		_expect_equal(restored.state.to_dict(), state.to_dict(), "container, condition and selection must round-trip")


func _test_integrity_suite() -> void:
	for failure in IntegritySuiteScript.run():
		_failures.append("%s — %s" % [_current_test, String(failure)])
	for failure in SaveIntegritySuiteScript.run():
		_failures.append("%s — %s" % [_current_test, String(failure)])


func _stack_for(state: RunState, item_id: String) -> Dictionary:
	for stack in InventoryStateScript.all_stacks(state.inventory):
		if not bool(stack.get("external", false)) and String(stack.get("item_id", "")) == item_id:
			return stack
	return {}


func _stack_for_anywhere(state: RunState, item_id: String) -> Dictionary:
	for stack in InventoryStateScript.all_stacks(state.inventory):
		if String(stack.get("item_id", "")) == item_id:
			return stack
	return {}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _build() -> Dictionary:
	return {"strength": 6, "charisma": 4, "intelligence": 5, "luck": 3}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current_test,
			message,
			str(expected),
			str(actual),
		])


func _cleanup_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = _save_path + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
