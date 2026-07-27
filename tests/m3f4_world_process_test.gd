extends SceneTree

const WorldCatalog := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)
const WorldFactory := preload("res://game/content/world_state_factory.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")
const TimeAdvancer := preload(
	"res://game/world/world_process_time_advancer.gd"
)
const ProcessProjection := preload(
	"res://game/world/world_process_projection.gd"
)

const PROCESS_ID := "process_recycling_inspection"

var _catalog: Dictionary = {}
var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	var loaded := WorldCatalog.load_default()
	if bool(loaded.get("ok", false)):
		_catalog = Dictionary(loaded.get("catalog", {})).duplicate(true)
	else:
		_failures.append("bootstrap — %s" % str(loaded.get("errors", [])))
	_run("authored process contract is versioned and rejects ambiguity", _test_contract)
	_run("only confirmed due time plans one pure transition", _test_due_transition)
	_run("a large interval cannot chain multiple stages", _test_no_transition_chain)
	_run("terminal branch priority is explicit and deterministic", _test_terminal_priority)
	_run("restricted and closed branches are mutually exclusive", _test_exclusive_branches)
	_run("stage projection changes multiple observable surfaces", _test_projection)
	if _failures.is_empty():
		print("M3F.4 WORLD PROCESS TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.4 WORLD PROCESS TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_contract() -> void:
	_expect_equal(_catalog.get("schema_version"), 2, "current authored schema")
	_expect_equal(
		_catalog.get("catalog_id"),
		"world_definition_catalog_v2",
		"current authored catalog ID"
	)
	_expect(FileAccess.file_exists(WorldCatalog.PREVIOUS_PATH), "v1 fixture remains physical")
	var previous := WorldCatalog.load_path(WorldCatalog.PREVIOUS_PATH)
	_expect(not bool(previous.get("ok", true)), "v1 is not silently read as v2")

	var missing_priority := _catalog.duplicate(true)
	var missing_process: Dictionary = Array(missing_priority["processes"])[0]
	var missing_transitions: Array = missing_process["transitions"]
	Dictionary(missing_transitions[0]).erase("priority")
	_expect(
		not bool(WorldCatalog.validate(missing_priority).get("ok", true)),
		"every transition requires explicit priority"
	)

	var ambiguous := _catalog.duplicate(true)
	var process: Dictionary = Array(ambiguous["processes"])[0]
	var transitions: Array = process["transitions"]
	var restricted := _transition(transitions, "transition_recycling_inspection_restricted")
	restricted["required_fact_ids"] = ["fact_recycling_scale_calibrated"]
	var closed := _transition(transitions, "transition_recycling_inspection_closed")
	closed["excluded_fact_ids"] = ["fact_recycling_press_safe"]
	_expect(
		not bool(WorldCatalog.validate(ambiguous).get("ok", true)),
		"restricted and closed definitions cannot overlap"
	)


func _test_due_transition() -> void:
	var state := _fresh_state()
	if state == null:
		return
	var original := state.to_dict()
	var zero_time := TimeAdvancer.plan(state, 0, 0, _catalog)
	_expect(bool(zero_time.get("ok", false)), "zero-time plan is valid")
	_expect(not bool(zero_time.get("advanced", true)), "zero-time plan stays idle")
	_expect_equal(zero_time.get("code"), "no_confirmed_time", "zero-time reason")
	var backwards := TimeAdvancer.plan(state, 10, 9, _catalog)
	_expect(not bool(backwards.get("ok", true)), "backwards time is rejected")
	_expect_equal(backwards.get("code"), "time_went_backwards", "backwards-time reason")
	var early := TimeAdvancer.plan(state, 0, 1439, _catalog)
	_expect(not bool(early.get("advanced", true)), "time below threshold stays idle")
	var due := TimeAdvancer.plan(state, 1439, 1440, _catalog)
	_expect(bool(due.get("ok", false)), "due plan succeeds")
	_expect(bool(due.get("advanced", false)), "confirmed crossing advances")
	_expect_equal(due.get("from_stage_id"), "latent", "source stage")
	_expect_equal(due.get("to_stage_id"), "warning", "target stage")
	_expect_equal(Array(due.get("effects", [])).size(), 1, "exactly one effect")
	_expect_equal(state.to_dict(), original, "planner never mutates world state")


func _test_no_transition_chain() -> void:
	var state := _fresh_state()
	if state == null:
		return
	var first := TimeAdvancer.plan(state, 0, 10_000, _catalog)
	_expect_equal(first.get("to_stage_id"), "warning", "large interval selects first edge")
	_expect(_apply_plan(state, first, 10_000), "planned edge applies through WorldMutation")
	_expect_equal(state.process_stage(PROCESS_ID), "warning", "only first edge committed")
	var same_command := TimeAdvancer.plan(state, 0, 10_000, _catalog)
	_expect(
		not bool(same_command.get("advanced", true)),
		"a process changed in this command cannot advance twice"
	)
	_expect_equal(
		same_command.get("code"),
		"already_changed_in_command",
		"anti-chain reason is explicit"
	)
	var next_command := TimeAdvancer.plan(state, 10_000, 10_001, _catalog)
	_expect_equal(
		next_command.get("to_stage_id"),
		"preparation",
		"later confirmed command may advance one next edge"
	)


func _test_terminal_priority() -> void:
	var state := _state_at("inspection", [
		"fact_recycling_scale_calibrated",
		"fact_recycling_yard_cleared",
		"fact_recycling_press_safe",
	])
	if state == null:
		return
	var before := state.to_dict()
	var first := TimeAdvancer.plan(state, 5759, 5760, _catalog)
	var second := TimeAdvancer.plan(state, 5759, 5760, _catalog)
	_expect_equal(first, second, "same state and time produce byte-equivalent plan")
	_expect_equal(first.get("to_stage_id"), "approved", "highest priority branch wins")
	_expect_equal(first.get("priority"), 300, "selected priority is exposed")
	_expect_equal(
		first.get("eligible_candidate_ids"),
		[
			"transition_recycling_inspection_approved",
			"transition_recycling_inspection_restricted",
		],
		"deterministic trace keeps all eligible candidates"
	)
	_expect_equal(state.to_dict(), before, "determinism test leaves state unchanged")


func _test_exclusive_branches() -> void:
	var restricted_state := _state_at("inspection", ["fact_recycling_press_safe"])
	var closed_state := _state_at("inspection", [])
	if restricted_state == null or closed_state == null:
		return
	var restricted := TimeAdvancer.plan(restricted_state, 5759, 5760, _catalog)
	var closed := TimeAdvancer.plan(closed_state, 5759, 5760, _catalog)
	_expect_equal(restricted.get("to_stage_id"), "restricted", "safe press avoids closure")
	_expect_equal(
		restricted.get("eligible_candidate_ids"),
		["transition_recycling_inspection_restricted"],
		"restricted branch is the sole match"
	)
	_expect_equal(closed.get("to_stage_id"), "closed_temporarily", "critical hazard closes")
	_expect_equal(
		closed.get("eligible_candidate_ids"),
		["transition_recycling_inspection_closed"],
		"closure branch is the sole match"
	)


func _test_projection() -> void:
	var latent_state := _fresh_state()
	var inspection_state := _state_at("inspection", [])
	var restricted_state := _state_at("restricted", [])
	if latent_state == null or inspection_state == null or restricted_state == null:
		return
	var latent_before := latent_state.to_dict()
	var latent := ProcessProjection.recycling_inspection(latent_state, _catalog)
	var inspection := ProcessProjection.recycling_inspection(inspection_state, _catalog)
	var restricted := ProcessProjection.recycling_inspection(restricted_state, _catalog)
	_expect(bool(latent.get("job_available", false)), "latent job is available")
	_expect_equal(latent.get("job_pay_basis_points"), 10_000, "latent pay modifier")
	_expect(not bool(inspection.get("job_available", true)), "inspection suspends job")
	_expect(
		not bool(inspection.get("recycling_accepting_materials", true)),
		"inspection suspends material intake"
	)
	_expect_equal(
		inspection.get("location_status_id"),
		"inspection_in_progress",
		"location status is observable"
	)
	_expect_equal(
		inspection.get("event_tags"),
		["recycling_inspection_active"],
		"event director gets a stable stage tag"
	)
	_expect_equal(restricted.get("job_pay_basis_points"), 8_000, "restriction lowers pay")
	_expect_equal(
		restricted.get("recycling_price_basis_points"),
		8_500,
		"restriction changes recycling price"
	)
	_expect_equal(latent_state.to_dict(), latent_before, "projection is pure")


func _fresh_state() -> WorldState:
	if _catalog.is_empty():
		_expect(false, "world catalog must load")
		return null
	var state := WorldFactory.from_catalog(_catalog, _stamp(0))
	_expect(state != null, "world factory creates process state")
	return state


func _state_at(stage_id: String, true_fact_ids: Array[String]) -> WorldState:
	var state := _fresh_state()
	if state == null:
		return null
	state.processes[PROCESS_ID] = {
		"stage": stage_id,
		"source_id": "m3f4_fixture",
		"changed_at": _stamp(4320),
	}
	for fact_id: String in true_fact_ids:
		state.facts[fact_id] = {
			"value": true,
			"source_id": "m3f4_fixture",
			"changed_at": _stamp(5000),
		}
	_expect(bool(state.validate().get("ok", false)), "world fixture validates")
	return state


func _apply_plan(state: WorldState, plan: Dictionary, elapsed: int) -> bool:
	if not bool(plan.get("ok", false)) or Array(plan.get("effects", [])).is_empty():
		return false
	var result := WorldMutationScript.apply(state, {
		"schema_version": 1,
		"source_id": "world_process_time_advancer",
		"at": _stamp(elapsed),
		"operations": Array(plan["effects"]).duplicate(true),
	}, _catalog)
	return bool(result.get("ok", false))


func _transition(entries: Array, transition_id: String) -> Dictionary:
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == transition_id:
			return raw_entry
	return {}


func _stamp(elapsed: int) -> Dictionary:
	return {
		"year": 1980,
		"month": 9,
		"day": 1 + int(elapsed / 1440),
		"hour": int(elapsed % 1440 / 60),
		"minute": elapsed % 60,
		"elapsed_minutes": elapsed,
	}


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_expect(false, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
