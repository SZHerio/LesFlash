extends SceneTree

const SearchCatalog := preload("res://game/search/search_zone_catalog.gd")
const SearchGenerator := preload("res://game/search/search_snapshot_generator.gd")
const SearchInteraction := preload("res://game/search/search_interaction_transaction.gd")
const WeekInventory := preload("res://game/week/week_inventory_command.gd")
const GameSessionScript := preload("res://app/session/game_session.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const SurvivalTimeRules = preload("res://game/survival/survival_time_rules.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


class ReplacingSession extends RefCounted:
	var run_state: RunState
	var world_state: WorldState = WorldState.new()
	var social_state: SocialState = SocialState.new()
	var survival_state: SurvivalState
	var applied_command_ids: Dictionary = {}
	var base_location := "underpass"

	func _init(state: RunState) -> void:
		run_state = state
		survival_state = SurvivalState.fresh(state.calendar.elapsed_minutes)

	func clone() -> ReplacingSession:
		var result := ReplacingSession.new(run_state.clone())
		result.world_state = world_state.clone()
		result.social_state = social_state.clone()
		result.survival_state = survival_state.clone()
		result.applied_command_ids = applied_command_ids.duplicate(true)
		result.base_location = base_location
		return result

	## Deliberately replace object identities. This catches stale RunState refs.
	func replace_from(other: ReplacingSession) -> bool:
		if other == null or not bool(other.validate().get("ok", false)):
			return false
		run_state = other.run_state.clone()
		world_state = other.world_state.clone()
		social_state = other.social_state.clone()
		survival_state = other.survival_state.clone()
		applied_command_ids = other.applied_command_ids.duplicate(true)
		base_location = other.base_location
		return true

	func validate() -> Dictionary:
		var errors: Array[String] = []
		for result: Dictionary in [
			run_state.validate(),
			world_state.validate(),
			social_state.validate(),
			survival_state.validate(),
		]:
			for raw_error: Variant in Array(result.get("errors", [])):
				errors.append(String(raw_error))
		if survival_state.processed_elapsed_minutes != run_state.calendar.elapsed_minutes:
			errors.append("survival and calendar are desynchronized")
		return {"ok": errors.is_empty(), "errors": errors}


func _init() -> void:
	_run("search uses the session time gateway and fresh RunState", _test_search_gateway)
	_run("timed item use is atomic and idempotent", _test_item_use)
	_run("disassembly commits outputs with survival time", _test_disassemble)
	_run("recycling sale delegates through the time gateway", _test_recycling_sale)
	_run("blocked inventory decisions leave the aggregate unchanged", _test_inventory_failures)
	if _failures.is_empty():
		print("M3F.2 TIME GATEWAY TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.2 TIME GATEWAY TESTS FAILED: %d failure(s) across %d test(s)" % [_failures.size(), _tests_run])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_search_gateway() -> void:
	var loaded := SearchCatalog.load_default()
	_expect(bool(loaded.get("ok", false)), "search catalog must load")
	if not bool(loaded.get("ok", false)):
		return
	var generated := SearchGenerator.generate(loaded["template"], 92_001, 1, {
		"luck": 5, "depletion": 0, "weather": "dry", "time_band": "day",
	})
	_expect(bool(generated.get("ok", false)), "search snapshot must generate")
	if not bool(generated.get("ok", false)):
		return
	var snapshot: Dictionary = generated["snapshot"]
	_place_at_object(snapshot, "open_dumpster")
	var session := ReplacingSession.new(RunState.new(_build(), 92_001))
	var old_state := session.run_state
	var result := SearchInteraction.apply(
		session,
		snapshot,
		"open_dumpster",
		"sort_by_hand",
		true,
		"search:gateway:1"
	)
	_expect(bool(result.get("ok", false)), "interaction must commit: %s" % str(result))
	if not bool(result.get("ok", false)):
		return
	_expect(session.run_state != old_state, "fixture must replace RunState identity")
	_expect_equal(session.run_state.calendar.elapsed_minutes, 12, "authored search time must advance once")
	_expect_equal(session.survival_state.processed_elapsed_minutes, 12, "survival time must follow search time")
	# Twelve minutes at the authored hunger rate, bound to the rule rather than
	# to a literal so a balance change does not read as a broken gateway.
	_expect_equal(
		session.survival_state.remainders.get("hunger"),
		12 * int(SurvivalTimeRules.DEFAULT_PROFILE["hunger_units_per_minute"]),
		"search must accumulate fixed-point hunger"
	)
	_expect(bool(Dictionary(result.get("transaction", {})).get("success", false)), "legacy actor transaction result contract must remain")
	_expect(session.applied_command_ids.has("search:gateway:1"), "shared command ledger must record interaction")
	var ground_items: Array = result["ground_items"]
	_expect(not ground_items.is_empty(), "resolved search must materialize its loot")
	for raw_ground: Variant in ground_items:
		var stack := InventoryStateScript.find_stack(
			session.run_state.inventory,
			String(raw_ground.get("stack_id", ""))
		)
		_expect(not stack.is_empty(), "loot must be written to the post-commit RunState")
		_expect(bool(stack.get("external", false)), "materialized loot must remain on search ground")


func _test_item_use() -> void:
	var run := RunState.new(_build(), 92_002)
	_expect(run.set_meter("hunger", 50), "hunger fixture")
	_expect(run.set_meter("energy", 80), "energy fixture")
	_expect(run.add_item("simple_meal", 1, "pockets"), "meal fixture")
	var session = GameSessionScript.new(run, "underpass")
	var stack := _carried_stack(run, "simple_meal")
	var result := WeekInventory.execute(session, String(stack.get("stack_id", "")), "use", "item:meal:1")
	_expect(bool(result.get("ok", false)), "meal must commit: %s" % str(result))
	if not bool(result.get("ok", false)):
		return
	_expect_equal(session.run_state.get_item_count("simple_meal"), 0, "consumed meal must leave inventory")
	_expect_equal(session.run_state.calendar.elapsed_minutes, 12, "meal must spend authored time")
	_expect_equal(session.survival_state.processed_elapsed_minutes, 12, "meal time must update survival")
	_expect_equal(session.run_state.get_meter("hunger"), 22, "meal effect must apply after passage")
	_expect_equal(session.run_state.get_meter("energy"), 85, "meal energy effect must apply")
	var after := session.to_dict()
	var duplicate := WeekInventory.execute(session, String(stack.get("stack_id", "")), "use", "item:meal:1")
	_expect_equal(duplicate.get("code"), "already_applied", "retry must resolve before looking for consumed stack")
	_expect_equal(session.to_dict(), after, "retry must not consume time or items twice")


func _test_disassemble() -> void:
	var run := RunState.new(_build(), 92_003)
	_expect(run.add_item("scrap_wire", 1, "pockets"), "wire fixture")
	var session = GameSessionScript.new(run, "underpass")
	var stack := _carried_stack(run, "scrap_wire")
	var result := WeekInventory.execute(session, String(stack.get("stack_id", "")), "disassemble", "item:wire:1")
	_expect(bool(result.get("ok", false)), "wire must disassemble: %s" % str(result))
	_expect_equal(session.run_state.get_item_count("scrap_wire"), 0, "input must be consumed")
	_expect_equal(session.run_state.get_item_count("copper_scrap"), 1, "authored output must be created")
	_expect_equal(session.run_state.calendar.elapsed_minutes, 18, "disassembly must spend time")
	_expect_equal(session.survival_state.processed_elapsed_minutes, 18, "disassembly must keep survival synchronized")
	_expect_equal(Array(result.get("outputs", [])).size(), 1, "result must explain created output")


func _test_recycling_sale() -> void:
	var run := RunState.new(_build(), 92_004)
	_expect(run.add_item("copper_scrap", 2, "pockets"), "recyclable fixture")
	var session = GameSessionScript.new(run, "recycling_point")
	var stack := _carried_stack(run, "copper_scrap")
	var result := WeekInventory.execute(session, String(stack.get("stack_id", "")), "sell", "item:sell:1", 1)
	_expect(bool(result.get("ok", false)), "recycling sale must commit: %s" % str(result))
	_expect_equal(session.run_state.get_item_count("copper_scrap"), 1, "only requested quantity must be sold")
	_expect_equal(session.run_state.money, 28, "sale must pay the material appraisal")
	_expect_equal(session.run_state.calendar.elapsed_minutes, 8, "one-item handover must spend eight minutes")
	_expect_equal(session.survival_state.processed_elapsed_minutes, 8, "sale time must update survival")
	_expect_equal(Dictionary(result.get("receipt", {})).get("payout"), 28, "receipt must explain payout")


func _test_inventory_failures() -> void:
	var run := RunState.new(_build(), 92_005)
	_expect(run.add_item("copper_scrap", 1, "pockets"), "failure fixture")
	var session = GameSessionScript.new(run, "underpass")
	var stack := _carried_stack(run, "copper_scrap")
	var before := session.to_dict()
	var wrong_place := WeekInventory.execute(session, String(stack.get("stack_id", "")), "sell", "item:sell:wrong", 1)
	_expect_equal(wrong_place.get("code"), "wrong_location", "recycling sale must require the authored place")
	_expect_equal(session.to_dict(), before, "blocked sale must leave full aggregate unchanged")
	var unsupported := WeekInventory.execute(session, String(stack.get("stack_id", "")), "equip", "item:equip:wrong")
	_expect_equal(unsupported.get("code"), "unsupported_inventory_action", "non-timed action must stay outside this command")
	_expect_equal(session.to_dict(), before, "unsupported action must be read-only")
	var missing := WeekInventory.execute(session, "missing_stack", "use", "item:missing:1")
	_expect_equal(missing.get("code"), "missing_stack", "missing item must fail explicitly")
	_expect_equal(session.to_dict(), before, "missing item must not advance survival or calendar")


func _place_at_object(snapshot: Dictionary, object_id: String) -> void:
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if not raw_object is Dictionary or String(raw_object.get("id", "")) != object_id:
			continue
		var node_id := String(raw_object.get("approach_node", ""))
		snapshot["player"]["node_id"] = node_id
		for raw_node: Variant in Array(snapshot["walk_graph"]["nodes"]):
			if raw_node is Dictionary and String(raw_node.get("id", "")) == node_id:
				snapshot["player"]["position"] = Array(raw_node.get("position", [0, 0])).duplicate()
				return


func _carried_stack(run_state: RunState, item_id: String) -> Dictionary:
	for raw_stack: Variant in InventoryStateScript.all_stacks(run_state.inventory):
		if raw_stack is Dictionary and not bool(raw_stack.get("external", false)) and String(raw_stack.get("item_id", "")) == item_id:
			return Dictionary(raw_stack).duplicate(true)
	return {}


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [_current, message, str(expected), str(actual)])
