extends RefCounted

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const InventoryTransactionScript := preload("res://core/inventory/inventory_transaction.gd")

var _failures: Array[String] = []


static func run() -> Array[String]:
	var suite := new()
	suite._test_metadata_transfer_and_merge()
	return suite._failures


func _test_metadata_transfer_and_merge() -> void:
	var state := RunState.new(_build(), 42_001)
	var metadata_a := {"origin": "yard", "clues": [1, {"dry": true}]}
	var metadata_b := {"origin": "yard", "clues": [1, {"dry": false}]}
	_add_with_metadata(state, "scrap_wire", 3, "pockets", metadata_a)
	_add_with_metadata(state, "scrap_wire", 2, "pockets", metadata_a)
	_add_with_metadata(state, "scrap_wire", 1, "pockets", metadata_b)
	var wire_stacks := _carried_stacks(state, "scrap_wire")
	_expect(wire_stacks.size() == 2, "only exactly equal metadata may merge")
	var source := _stack_with_metadata(wire_stacks, metadata_a)
	_expect(int(source.get("quantity", 0)) == 5, "equal metadata must merge quantities")
	var source_id := String(source.get("stack_id", ""))
	var partial := InventoryTransactionScript.move(state, source_id, "hands", 2)
	_expect(bool(partial.get("ok", false)), "partial move must commit")
	var source_after := InventoryStateScript.find_stack(state.inventory, source_id)
	_expect(source_after.get("metadata", {}) == metadata_a, "partial source must retain metadata")
	_expect(int(source_after.get("quantity", 0)) == 3, "partial source must retain its remainder")
	var hand_stack := _stack_in(state, "scrap_wire", "hands")
	_expect(hand_stack.get("metadata", {}) == metadata_a, "partial destination must retain metadata")
	_expect(int(hand_stack.get("quantity", 0)) == 2, "partial destination quantity must be exact")

	var partial_drop := InventoryTransactionScript.drop(state, source_id, "underpass", 1)
	_expect(bool(partial_drop.get("ok", false)), "partial drop must commit")
	source_after = InventoryStateScript.find_stack(state.inventory, source_id)
	_expect(int(source_after.get("quantity", 0)) == 2, "partial drop must retain source remainder")
	_expect(source_after.get("metadata", {}) == metadata_a, "partial drop source metadata must survive")
	var dropped := InventoryTransactionScript.drop(
		state,
		String(hand_stack.get("stack_id", "")),
		"underpass"
	)
	_expect(bool(dropped.get("ok", false)), "full drop must commit")
	var ground_stack := _stack_in(state, "scrap_wire", "ground:underpass")
	_expect(ground_stack.get("metadata", {}) == metadata_a, "drop must retain metadata")
	_expect(int(ground_stack.get("quantity", 0)) == 3, "partial and full drops must merge exactly")
	var picked := InventoryTransactionScript.pick_up(
		state,
		String(ground_stack.get("stack_id", "")),
		"hands",
		1
	)
	_expect(bool(picked.get("ok", false)), "partial pickup must commit")
	_expect(
		_stack_in(state, "scrap_wire", "hands").get("metadata", {}) == metadata_a,
		"pickup must retain metadata"
	)
	ground_stack = _stack_in(state, "scrap_wire", "ground:underpass")
	picked = InventoryTransactionScript.pick_up(
		state,
		String(ground_stack.get("stack_id", "")),
		"hands"
	)
	_expect(bool(picked.get("ok", false)), "full pickup must commit")
	_expect(
		_stack_in(state, "scrap_wire", "ground:underpass").is_empty(),
		"full pickup must remove the external remainder"
	)
	var metadata_b_stack := _stack_with_metadata(_carried_stacks(state, "scrap_wire"), metadata_b)
	var full_move := InventoryTransactionScript.move(
		state,
		String(metadata_b_stack.get("stack_id", "")),
		"hands"
	)
	_expect(bool(full_move.get("ok", false)), "full move must commit")
	_expect(
		_stack_with_metadata(_carried_stacks(state, "scrap_wire"), metadata_b)
			.get("metadata", {}) == metadata_b,
		"full move must retain distinct metadata"
	)
	_test_replacement_metadata()


func _test_replacement_metadata() -> void:
	var state := RunState.new(_build(), 42_002)
	var displaced_metadata := {"owner": "hero", "serial": 7}
	var incoming_metadata := {"found": {"place": "yard"}, "serial": 8}
	_add_with_metadata(state, "recyclables", 1, "pockets", displaced_metadata)
	state.inventory = InventoryStateScript.ensure_external_container(
		state.inventory,
		"ground:yard",
		"На земле"
	)
	_add_with_metadata(state, "plastic_bottle", 1, "ground:yard", incoming_metadata)
	var incoming := _stack_in(state, "plastic_bottle", "ground:yard")
	var displaced := _stack_in(state, "recyclables", "pockets")
	var replacement := InventoryTransactionScript.replace(
		state,
		String(incoming.get("stack_id", "")),
		String(displaced.get("stack_id", "")),
		"pockets"
	)
	_expect(bool(replacement.get("ok", false)), "replacement must commit")
	_expect(
		_stack_in(state, "plastic_bottle", "pockets").get("metadata", {}) == incoming_metadata,
		"replacement incoming metadata must survive"
	)
	_expect(
		_stack_in(state, "recyclables", "ground:yard").get("metadata", {})
			== displaced_metadata,
		"replacement displaced metadata must survive"
	)
	var equal_state := RunState.new(_build(), 42_006)
	var equal_metadata := {"batch": "same"}
	_add_with_metadata(equal_state, "scrap_wire", 2, "pockets", equal_metadata)
	equal_state.inventory = InventoryStateScript.ensure_external_container(
		equal_state.inventory, "ground:equal", "На земле"
	)
	_add_with_metadata(equal_state, "scrap_wire", 3, "ground:equal", equal_metadata)
	var equal_incoming := _stack_in(equal_state, "scrap_wire", "ground:equal")
	var equal_displaced := _stack_in(equal_state, "scrap_wire", "pockets")
	replacement = InventoryTransactionScript.replace(
		equal_state,
		String(equal_incoming.get("stack_id", "")),
		String(equal_displaced.get("stack_id", "")),
		"pockets"
	)
	_expect(bool(replacement.get("ok", false)), "equal-metadata replacement must commit")
	_expect(equal_state.get_item_count("scrap_wire") == 3, "replacement must not pull both stacks")
	_expect(
		int(_stack_in(equal_state, "scrap_wire", "ground:equal").get("quantity", 0)) == 2,
		"equal-metadata displaced quantity must remain external"
	)


func _add_with_metadata(
	state: RunState,
	item_id: String,
	quantity: int,
	container_id: String,
	metadata: Dictionary
) -> void:
	var result := InventoryStateScript.add_item(
		state.inventory,
		item_id,
		quantity,
		100,
		container_id,
		state.get_characteristic("strength"),
		false,
		metadata
	)
	_expect(bool(result.get("ok", false)), "metadata fixture must fit: %s" % item_id)
	if bool(result.get("ok", false)):
		state.inventory = result["inventory"]


func _carried_stacks(state: RunState, item_id: String) -> Array:
	var result: Array = []
	for stack in InventoryStateScript.all_stacks(state.inventory):
		if not bool(stack.get("external", false)) and stack.get("item_id", "") == item_id:
			result.append(stack)
	return result


func _stack_with_metadata(stacks: Array, metadata: Dictionary) -> Dictionary:
	for stack in stacks:
		if stack.get("metadata", {}) == metadata:
			return stack
	return {}


func _stack_in(state: RunState, item_id: String, container_id: String) -> Dictionary:
	for stack in InventoryStateScript.all_stacks(state.inventory):
		if stack.get("item_id", "") == item_id and stack.get("container_id", "") == container_id:
			return stack
	return {}


func _build() -> Dictionary:
	return {"strength": 6, "charisma": 4, "intelligence": 5, "luck": 3}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
