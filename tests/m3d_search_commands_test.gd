extends SceneTree

const SessionScript := preload("res://game/run/run_session.gd")
const Service := preload("res://game/search/search_session_service.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")

const ZONE_ID := "underpass_service_yard"

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""


func _init() -> void:
	_run_test("begin is deterministic, atomic and idempotent", _test_begin)
	_run_test("movement checkpoints persist without moving time", _test_movement)
	_run_test("preview is exact and read-only", _test_preview)
	_run_test("interaction commits cost and loot exactly once", _test_interaction)
	_run_test("risk threshold builds a versioned encounter context", _test_risk)
	_run_test("capacity conflict preserves ground loot", _test_capacity_conflict)
	_run_test("compound replacement updates inventory and ground atomically", _test_replace)
	_run_test("finish archives and re-entry restores the same zone", _test_reentry)
	_run_test("six resolved objects unlock deterministic quick search", _test_quick_search)
	_run_test("non-search activities reject search commands", _test_activity_guard)

	if _failures.is_empty():
		print("M3D SEARCH COMMAND TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3D SEARCH COMMAND TESTS FAILED: %d failure(s) across %d test(s)" % [
		_failures.size(),
		_tests_run,
	])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)


func _test_begin() -> void:
	var session := _new_session(91_001)
	if session == null:
		return
	var rng_before := session.run_state.rng.to_dict()
	var result := Service.begin_search(session, ZONE_ID, "begin:1")
	_expect_ok(result, "search must begin")
	if not bool(result.get("ok", false)):
		return
	_expect_equal(session.run_state.rng.to_dict(), rng_before, "zone RNG must be separate")
	_expect_equal(session.get_active_activity().get("kind"), "search", "search activity")
	var after := session.to_dict()
	var duplicate := Service.begin_search(session, ZONE_ID, "begin:1")
	_expect_equal(duplicate.get("code"), "duplicate_command", "begin retry")
	_expect_equal(session.to_dict(), after, "duplicate begin must not touch session")
	var blocked := Service.begin_search(session, ZONE_ID, "begin:other")
	_expect_equal(blocked.get("code"), "activity_in_progress", "new begin is blocked")
	_expect_equal(session.to_dict(), after, "blocked begin must be atomic")


func _test_movement() -> void:
	var session := _active_session(91_002)
	if session == null:
		return
	var time_before := session.run_state.calendar.elapsed_minutes
	var plan := Service.plan_move(session, "open_dumpster", "move:plan")
	_expect_ok(plan, "path must plan")
	if not bool(plan.get("ok", false)):
		return
	var path: Array = Dictionary(plan.get("path", {})).get("points", [])
	_expect(path.size() > 1, "path must contain authored waypoints")
	_expect_equal(session.run_state.calendar.elapsed_minutes, time_before, "planning costs no time")
	var checkpoint := Service.checkpoint_move(
		session,
		path.back(),
		path.size() - 1,
		true,
		"move:finish"
	)
	_expect_ok(checkpoint, "movement must finish")
	_expect_equal(session.run_state.calendar.elapsed_minutes, time_before, "walking costs no time")
	var player: Dictionary = session.active_activity["snapshot"]["player"]
	_expect_equal(player.get("node_id"), "dumpster_lane", "hero reaches approach node")
	_expect(Array(player.get("planned_path", [])).is_empty(), "completed plan is cleared")
	var after := session.to_dict()
	var duplicate := Service.checkpoint_move(
		session,
		path.back(),
		path.size() - 1,
		true,
		"move:finish"
	)
	_expect_equal(duplicate.get("code"), "duplicate_command", "checkpoint retry")
	_expect_equal(session.to_dict(), after, "checkpoint retry must not mutate")


func _test_preview() -> void:
	var session := _active_session(91_003)
	if session == null or not _move_to(session, "open_dumpster", "preview"):
		return
	var before := session.to_dict()
	var preview := Service.preview_interaction(
		session,
		"open_dumpster",
		"sort_by_hand"
	)
	_expect_ok(preview, "preview must resolve")
	_expect(bool(preview.get("allowed", false)), "open dumpster must be available")
	_expect_equal(preview.get("costs"), {
		"minutes": 12,
		"energy": 2,
		"noise": 1,
		"trespass": 0,
	}, "preview exposes exact authored costs")
	_expect_equal(session.to_dict(), before, "preview must be read-only")


func _test_interaction() -> void:
	var session := _active_session(91_004)
	if session == null or not _move_to(session, "open_dumpster", "interact"):
		return
	var before_time := session.run_state.calendar.elapsed_minutes
	var before_energy := session.run_state.get_meter("energy")
	var result := Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"interact:dumpster"
	)
	_expect_ok(result, "interaction must commit")
	if not bool(result.get("ok", false)):
		return
	_expect_equal(
		session.run_state.calendar.elapsed_minutes - before_time,
		12,
		"only confirmed interaction advances time"
	)
	_expect_equal(
		session.run_state.get_meter("energy"),
		before_energy - 2,
		"energy cost must apply exactly"
	)
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var object := _object(snapshot, "open_dumpster")
	_expect_equal(object.get("state"), "exhausted", "object must exhaust")
	_expect(bool(object.get("interacted", false)), "object interaction marker")
	_expect_equal(
		Array(snapshot.get("ground_items", [])).size(),
		Array(object.get("contents", [])).size(),
		"pre-resolved contents materialize once"
	)
	for loot: Variant in Array(object.get("contents", [])):
		_expect(bool(loot.get("claimed", false)), "materialized loot is marked claimed")
	var ground_count := Array(snapshot.get("ground_items", [])).size()
	var after := session.to_dict()
	var duplicate := Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"interact:dumpster"
	)
	_expect_equal(duplicate.get("code"), "duplicate_command", "interaction retry")
	_expect_equal(session.to_dict(), after, "retry must not duplicate costs or loot")
	_expect_equal(
		Array(session.active_activity["snapshot"].get("ground_items", [])).size(),
		ground_count,
		"ground loot count is stable"
	)


func _test_risk() -> void:
	var session := _active_session(91_005)
	if session == null or not _move_to(session, "market_fence", "risk"):
		return
	var result := Service.confirm_interaction(
		session,
		"market_fence",
		"slip_through",
		"risk:market"
	)
	_expect_ok(result, "trespass decision must commit")
	if not bool(result.get("ok", false)):
		return
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var risk: Dictionary = snapshot["risk"]
	_expect_equal(risk.get("trespass"), 8, "trespass delta")
	_expect(int(risk.get("score", 0)) >= 35, "derived risk crosses warning threshold")
	var encounter: Dictionary = snapshot.get("pending_encounter", {})
	_expect_equal(encounter.get("status"), "pending", "encounter is queued")
	var context: Dictionary = encounter.get("context", {})
	_expect_equal(context.get("schema_version"), 2, "EventContext is versioned")
	_expect_equal(
		Dictionary(context.get("source", {})).get("object_id"),
		"market_fence",
		"context identifies the causing object"
	)


func _test_capacity_conflict() -> void:
	var session := _session_with_dumpster_loot(91_006)
	if session == null:
		return
	_expect(session.run_state.add_item("cardboard_sheet", 1, "pockets"), "cardboard fixture")
	_expect(session.run_state.add_item("aluminum_can", 8, "pockets"), "can fixture")
	var snapshot: Dictionary = session.active_activity["snapshot"]
	var incoming := Dictionary(Array(snapshot["ground_items"])[0])
	var before := session.to_dict()
	var result := Service.pick_up(
		session,
		String(incoming["stack_id"]),
		"pockets",
		"pickup:full"
	)
	_expect_equal(result.get("code"), "capacity_conflict", "full pockets return conflict")
	_expect(result.has("incoming"), "capacity conflict retains incoming description")
	_expect(result.has("comparison"), "capacity conflict retains comparison")
	_expect_equal(session.to_dict(), before, "failed pickup leaves whole session unchanged")
	_expect(
		not _ground(session.active_activity["snapshot"], String(incoming["stack_id"])).is_empty(),
		"failed pickup keeps item on ground"
	)


func _test_replace() -> void:
	var session := _session_with_dumpster_loot(91_007)
	if session == null:
		return
	_expect(session.run_state.add_item("cardboard_sheet", 1, "pockets"), "cardboard fixture")
	_expect(session.run_state.add_item("aluminum_can", 8, "pockets"), "can fixture")
	var incoming := Dictionary(Array(session.active_activity["snapshot"]["ground_items"])[0])
	var displaced := _carried_stack(session, "cardboard_sheet")
	var conflict := Service.pick_up(
		session,
		String(incoming["stack_id"]),
		"pockets",
		"replace:preview"
	)
	_expect_equal(conflict.get("code"), "capacity_conflict", "replacement fixture is full")
	var result := Service.replace(
		session,
		String(incoming["stack_id"]),
		String(displaced["stack_id"]),
		"pockets",
		"replace:commit"
	)
	_expect_ok(result, "replacement must commit")
	if not bool(result.get("ok", false)):
		return
	var snapshot: Dictionary = session.active_activity["snapshot"]
	_expect(
		_ground(snapshot, String(incoming["stack_id"])).is_empty(),
		"incoming ground reference is removed"
	)
	_expect(
		not _ground(snapshot, String(displaced["stack_id"])).is_empty(),
		"displaced stack receives a ground reference"
	)
	var displaced_after := InventoryStateScript.find_stack(
		session.run_state.inventory,
		String(displaced["stack_id"])
	)
	_expect(bool(displaced_after.get("external", false)), "displaced item is external")


func _test_reentry() -> void:
	var session := _active_session(91_008)
	if session == null or not _move_to(session, "open_dumpster", "reentry"):
		return
	var expected: Dictionary = session.active_activity["snapshot"].duplicate(true)
	var finished := Service.finish_search(session, "finish:1")
	_expect_ok(finished, "search must finish")
	_expect_equal(session.active_activity.get("kind"), "none", "explicit activity clears")
	_expect_equal(session.search_zone_states.get(ZONE_ID), finished.get("snapshot"), "archive")
	var after_finish := session.to_dict()
	var duplicate := Service.finish_search(session, "finish:1")
	_expect_equal(duplicate.get("code"), "duplicate_command", "finish retry")
	_expect_equal(session.to_dict(), after_finish, "finish retry is read-only")
	var stale_begin := Service.begin_search(session, ZONE_ID, "begin:91008")
	_expect_equal(stale_begin.get("code"), "duplicate_command", "old begin retry")
	_expect_equal(session.to_dict(), after_finish, "old begin must not reopen the zone")
	var reopened := Service.begin_search(session, ZONE_ID, "begin:again")
	_expect_ok(reopened, "archived zone must reopen")
	if bool(reopened.get("ok", false)):
		var restored: Dictionary = reopened["snapshot"].duplicate(true)
		restored["applied_command_ids"].erase("finish:1")
		restored["applied_command_ids"].erase("begin:again")
		expected["applied_command_ids"].erase("finish:1")
		expected["applied_command_ids"].erase("begin:again")
		_expect_equal(restored, expected, "re-entry restores the exact authored state")


func _test_quick_search() -> void:
	var session := _active_session(
		91_009,
		{"strength": 5, "charisma": 1, "intelligence": 7, "luck": 5}
	)
	if session == null:
		return
	_expect(session.run_state.add_item("rusty_tool", 1, "hands"), "tool fixture")
	var snapshot: Dictionary = session.active_activity["snapshot"].duplicate(true)
	for index in range(5):
		var object: Dictionary = snapshot["objects"][index]
		object["state"] = "exhausted"
		object["revealed"] = true
		object["interacted"] = true
		for loot_index in range(object["contents"].size()):
			object["contents"][loot_index]["claimed"] = true
		snapshot["objects"][index] = object
	_place_at_object(snapshot, "market_fence")
	_expect(
		_replace_active_snapshot(session, snapshot),
		"five-object mastery fixture"
	)
	var sixth := Service.confirm_interaction(
		session,
		"market_fence",
		"slip_through",
		"mastery:sixth"
	)
	_expect_ok(sixth, "sixth object must resolve")
	_expect_equal(session.run_state.get_skill_rank("search"), 1, "sixth object unlocks search rank")
	if not bool(sixth.get("ok", false)):
		return
	snapshot = session.active_activity["snapshot"].duplicate(true)
	snapshot["risk"] = {"noise": 0, "trespass": 0, "repeated_attempts": 0}
	snapshot.erase("pending_encounter")
	_expect(
		_replace_active_snapshot(session, snapshot),
		"quick-search fixture must validate"
	)
	var before_time := session.run_state.calendar.elapsed_minutes
	var result := Service.quick_search(session, "quick:1")
	_expect_ok(result, "quick search must resolve deterministic remainder")
	if not bool(result.get("ok", false)):
		return
	_expect_equal(
		result.get("resolved_object_ids"),
		["storm_drain", "dark_tunnel"],
		"authored order determines quick search"
	)
	_expect_equal(
		session.run_state.calendar.elapsed_minutes - before_time,
		31,
		"quick search pays the same interaction minutes"
	)
	var after := session.to_dict()
	var ground_count := Array(session.active_activity["snapshot"]["ground_items"]).size()
	var duplicate := Service.quick_search(session, "quick:1")
	_expect_equal(duplicate.get("code"), "duplicate_command", "quick search retry")
	_expect_equal(session.to_dict(), after, "quick retry must not replay costs")
	_expect_equal(
		Array(session.active_activity["snapshot"]["ground_items"]).size(),
		ground_count,
		"quick retry must not duplicate loot"
	)


func _test_activity_guard() -> void:
	var session := SessionScript.create(_build(), 91_010)
	_expect(session != null, "event session fixture")
	if session == null:
		return
	var before := session.to_dict()
	var result := Service.begin_search(session, ZONE_ID, "guard:begin")
	_expect_equal(result.get("code"), "activity_in_progress", "event blocks search")
	_expect_equal(session.to_dict(), before, "guard failure is atomic")
	result = Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"guard:confirm"
	)
	_expect_equal(result.get("code"), "search_not_active", "normal activity rejects command")
	_expect_equal(session.to_dict(), before, "rejected command changes nothing")


const ZONE_LOCATION_ID := "underpass"


func _new_session(seed: int, build: Dictionary = {}) -> RunSession:
	var selected := _build() if build.is_empty() else build
	var session := SessionScript.create_location_first(selected, seed)
	_expect(session != null, "session must start")
	if session != null:
		# The authored zone belongs to the underpass, and Luck decides where a
		# run actually starts, so the fixture moves the hero to its location.
		session.location = ZONE_LOCATION_ID
	return session


func _active_session(seed: int, build: Dictionary = {}) -> RunSession:
	var session := _new_session(seed, build)
	if session == null:
		return null
	var result := Service.begin_search(session, ZONE_ID, "begin:%d" % seed)
	_expect_ok(result, "search fixture must begin")
	return session if bool(result.get("ok", false)) else null


func _session_with_dumpster_loot(seed: int) -> RunSession:
	var session := _active_session(seed)
	if session == null or not _move_to(session, "open_dumpster", "loot:%d" % seed):
		return null
	var result := Service.confirm_interaction(
		session,
		"open_dumpster",
		"sort_by_hand",
		"loot:interact:%d" % seed
	)
	_expect_ok(result, "loot fixture must resolve")
	return session if bool(result.get("ok", false)) else null


func _move_to(session: RunSession, object_id: String, prefix: String) -> bool:
	var plan := Service.plan_move(session, object_id, "%s:plan" % prefix)
	_expect_ok(plan, "movement plan for %s" % object_id)
	if not bool(plan.get("ok", false)):
		return false
	var path: Array = Dictionary(plan["path"]).get("points", [])
	var result := Service.checkpoint_move(
		session,
		path.back(),
		path.size() - 1,
		true,
		"%s:checkpoint" % prefix
	)
	_expect_ok(result, "movement checkpoint for %s" % object_id)
	return bool(result.get("ok", false))


func _place_at_object(snapshot: Dictionary, object_id: String) -> void:
	var object := _object(snapshot, object_id)
	var node_id := String(object.get("approach_node", ""))
	snapshot["player"]["node_id"] = node_id
	for raw_node: Variant in Array(snapshot["walk_graph"]["nodes"]):
		if raw_node is Dictionary and String(raw_node.get("id", "")) == node_id:
			snapshot["player"]["position"] = Array(raw_node["position"]).duplicate()
			return


func _replace_active_snapshot(
	session: RunSession,
	snapshot: Dictionary
) -> bool:
	var zones := session.search_zone_states.duplicate(true)
	zones[ZONE_ID] = snapshot.duplicate(true)
	return bool(session.replace_search_state(
		{"kind": "search", "id": ZONE_ID, "snapshot": snapshot},
		zones
	).get("ok", false))


func _object(snapshot: Dictionary, object_id: String) -> Dictionary:
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if raw_object is Dictionary and String(raw_object.get("id", "")) == object_id:
			return Dictionary(raw_object).duplicate(true)
	return {}


func _ground(snapshot: Dictionary, stack_id: String) -> Dictionary:
	for raw_ground: Variant in Array(snapshot.get("ground_items", [])):
		if raw_ground is Dictionary and String(raw_ground.get("stack_id", "")) == stack_id:
			return Dictionary(raw_ground).duplicate(true)
	return {}


func _carried_stack(session: RunSession, item_id: String) -> Dictionary:
	for raw_stack: Variant in InventoryStateScript.all_stacks(session.run_state.inventory):
		if (
			raw_stack is Dictionary
			and not bool(raw_stack.get("external", false))
			and String(raw_stack.get("item_id", "")) == item_id
		):
			return Dictionary(raw_stack).duplicate(true)
	return {}


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5}


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s: %s" % [message, str(result)])


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
