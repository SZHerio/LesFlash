extends RefCounted

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const InventoryTransactionScript := preload("res://core/inventory/inventory_transaction.gd")
const SessionMigrationScript := preload("res://game/run/run_session_migration.gd")
const RunSessionScript := preload("res://game/run/run_session.gd")
const RunSaveScript := preload("res://game/run/run_save.gd")
const RunStateSaveScript := preload("res://core/save/run_state_save.gd")

const SESSION_V2_FIXTURE := "res://tests/fixtures/m3b_session_v2.json"

var _failures: Array[String] = []


static func run() -> Array[String]:
	var suite := new()
	suite._test_compact_legacy_migration()
	suite._test_metadata_validation_and_save_round_trips()
	suite._test_non_consuming_use()
	return suite._failures


func _test_compact_legacy_migration() -> void:
	var envelope := _read_json(SESSION_V2_FIXTURE)
	envelope["session"]["run_state"]["inventory"]["simple_meal"] = 1_000_000
	var migration := SessionMigrationScript.migrate_envelope(envelope)
	_expect(bool(migration.get("ok", false)), "maximum valid legacy quantity must migrate")
	if not bool(migration.get("ok", false)):
		return
	var state_data: Dictionary = migration["data"]["session"]["run_state"]
	var state := RunState.from_dict(state_data)
	_expect(state != null, "compact legacy inventory must deserialize")
	if state == null:
		return
	var stacks := InventoryStateScript.all_stacks(state.inventory)
	_expect(stacks.size() <= 5, "migration memory must scale with item ids, not quantities")
	var meal := _stack_anywhere(state, "simple_meal")
	_expect(
		meal.get("quantity_encoding", "") == "legacy_v2_compact",
		"compact migration stack must carry its explicit encoding marker"
	)
	_expect(state.get_item_count("simple_meal") == 1_000_000, "item_count must stay exact")
	_expect(state.remove_item("simple_meal", 123), "ordinary removal must work on compact stacks")
	_expect(state.get_item_count("simple_meal") == 999_877, "compact removal must be exact")
	var partial_drop := InventoryTransactionScript.drop(
		state,
		String(meal.get("stack_id", "")),
		"underpass",
		7
	)
	_expect(bool(partial_drop.get("ok", false)), "partial compact-stack drop must commit")
	_expect(state.get_item_count("simple_meal") == 999_870, "partial move must preserve exact count")
	_expect(
		InventoryStateScript.all_stacks(state.inventory).size() <= 6,
		"compact-stack operations must remain memory bounded"
	)
	var excessive := _read_json(SESSION_V2_FIXTURE)
	excessive["session"]["run_state"]["inventory"]["simple_meal"] = 1_000_001
	_expect(
		not bool(SessionMigrationScript.migrate_envelope(excessive).get("ok", true)),
		"legacy quantity above the documented limit must fail without allocation"
	)
	var invalid_marker := state.inventory.duplicate(true)
	invalid_marker["containers"]["backpack"]["stacks"][0]["quantity_encoding"] = "unknown"
	_expect(
		not bool(InventoryStateScript.validate(invalid_marker).get("ok", true)),
		"inventory schema must reject unknown compact-quantity markers"
	)


func _test_metadata_validation_and_save_round_trips() -> void:
	var invalid_inventory := InventoryStateScript.fresh()
	var invalid := InventoryStateScript.add_item(
		invalid_inventory,
		"scrap_wire",
		1,
		100,
		"pockets",
		6,
		false,
		{"unsafe": 9_007_199_254_740_992}
	)
	_expect(invalid.get("code", "") == "invalid_metadata", "unsafe metadata integers must fail")
	var non_string_key := {1: "bad"}
	invalid = InventoryStateScript.add_item(
		invalid_inventory, "scrap_wire", 1, 100, "pockets", 6, false, non_string_key
	)
	_expect(invalid.get("code", "") == "invalid_metadata", "metadata keys must be strings")
	var too_deep: Dictionary = {}
	var cursor := too_deep
	for index in range(34):
		cursor["next"] = {}
		cursor = cursor["next"]
	invalid = InventoryStateScript.add_item(
		invalid_inventory, "scrap_wire", 1, 100, "pockets", 6, false, too_deep
	)
	_expect(invalid.get("code", "") == "invalid_metadata", "metadata depth must be bounded")

	var metadata := {
		"origin": "service_yard",
		"nested": [true, null, 2.5, 4.0, {"safe": 9_007_199_254_740_991}],
	}
	var state := RunState.new(_build(), 42_003)
	_add_with_metadata(state, "scrap_wire", metadata)
	var canonical: Dictionary = _stack_anywhere(state, "scrap_wire").get("metadata", {})
	_expect(canonical["nested"][3] is int, "safe integral floats must normalize to integers")
	_round_trip_run_state(state, canonical)
	_round_trip_session(state, canonical)


func _test_non_consuming_use() -> void:
	var state := RunState.new(_build(), 42_004)
	_expect(state.add_item("plastic_bottle", 1), "bottle fixture must fit")
	var bottle := _stack_anywhere(state, "plastic_bottle")
	var used := InventoryTransactionScript.use(state, String(bottle.get("stack_id", "")))
	_expect(bool(used.get("ok", false)), "non-consuming bottle action must commit")
	_expect(state.get_item_count("plastic_bottle") == 1, "Проверить и убрать must not destroy bottle")


func _round_trip_run_state(state: RunState, expected_metadata: Dictionary) -> void:
	var path := _temporary_path("run")
	var saved := RunStateSaveScript.save_state(state, path)
	_expect(bool(saved.get("ok", false)), "RunState envelope must save metadata")
	var loaded := RunStateSaveScript.load_state(path)
	_expect(bool(loaded.get("ok", false)), "RunState envelope must load metadata")
	if bool(loaded.get("ok", false)):
		_expect(
			_stack_anywhere(loaded.state, "scrap_wire").get("metadata", {}) == expected_metadata,
			"RunState envelope metadata must round-trip exactly"
		)
	_cleanup(path)


func _round_trip_session(state: RunState, expected_metadata: Dictionary) -> void:
	var session = RunSessionScript.create_location_first(_build(), 42_005)
	_expect(session != null, "session fixture must be created")
	if session == null:
		return
	session.run_state = state.clone()
	var path := _temporary_path("session")
	var saved := RunSaveScript.save_session(session, path)
	_expect(bool(saved.get("ok", false)), "session envelope must save metadata")
	var loaded := RunSaveScript.load_session(path)
	_expect(bool(loaded.get("ok", false)), "session envelope must load metadata")
	if bool(loaded.get("ok", false)):
		_expect(
			_stack_anywhere(loaded.session.run_state, "scrap_wire").get("metadata", {})
				== expected_metadata,
			"session envelope metadata must round-trip exactly"
		)
	_cleanup(path)


func _add_with_metadata(state: RunState, item_id: String, metadata: Dictionary) -> void:
	var result := InventoryStateScript.add_item(
		state.inventory,
		item_id,
		1,
		100,
		"pockets",
		state.get_characteristic("strength"),
		false,
		metadata
	)
	_expect(bool(result.get("ok", false)), "metadata fixture must fit: %s" % item_id)
	if bool(result.get("ok", false)):
		state.inventory = result["inventory"]


func _stack_anywhere(state: RunState, item_id: String) -> Dictionary:
	for stack in InventoryStateScript.all_stacks(state.inventory):
		if stack.get("item_id", "") == item_id:
			return stack
	return {}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parser := JSON.new()
	if file == null or parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _temporary_path(label: String) -> String:
	return ProjectSettings.globalize_path(
		"res://.godot/.m3c_integrity_%s_%d.json" % [label, Time.get_ticks_usec()]
	)


func _cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = path + String(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _build() -> Dictionary:
	return {"strength": 6, "charisma": 4, "intelligence": 5, "luck": 3}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
