extends SceneTree

const InteractionCatalog := preload("res://game/npc/npc_interaction_catalog.gd")
const ScheduleResolver := preload("res://game/npc/npc_schedule_resolver.gd")
const InteractionHistory := preload("res://game/npc/npc_interaction_history.gd")
const InteractionService := preload("res://game/npc/npc_interaction_service.gd")
const InteractionCommand := preload("res://game/npc/npc_interaction_command.gd")
const NpcCatalog := preload("res://game/content/catalogs/npc_catalog.gd")
const Bundle := preload("res://game/content/catalogs/content_catalog_bundle.gd")
const WorldFactory := preload("res://game/content/world_state_factory.gd")
const GameSessionScript := preload("res://app/session/game_session.gd")

const BUILD := {
	"strength": 6,
	"charisma": 4,
	"intelligence": 4,
	"luck": 4,
}
const NPC_IDS := [
	"npc_viktor_koren",
	"npc_lidia_maren",
	"npc_tamara_roven",
]

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""
var _npc_catalog: Dictionary = {}
var _interactions: Dictionary = {}
var _world_definitions: Dictionary = {}


func _init() -> void:
	_bootstrap()
	_run("versioned catalog contains three interactions per canonical NPC", _test_catalog)
	_run("schedule boundaries use ISO weekdays and end-exclusive windows", _test_schedules)
	_run("presence and interaction reads are deterministic and pure", _test_pure_reads)
	_run("blocked interactions are hidden or explained by preference", _test_hidden_and_shown_blocked)
	_run("journal history enforces daily and cooldown repeat policies", _test_repeat_history)
	_run("one command atomically commits time actor social world and memory", _test_atomic_command)
	_run("duplicate and blocked commands leave the full session untouched", _test_idempotency_and_atomic_block)
	_run("saved memory and two distinct meetings unlock a follow-up", _test_memory_followup)
	_finish()


func _bootstrap() -> void:
	var npcs := NpcCatalog.load_default()
	var interactions := InteractionCatalog.load_default()
	var bundle := Bundle.load_default()
	if bool(npcs.get("ok", false)):
		_npc_catalog = Dictionary(npcs.get("catalog", {}))
	else:
		_failures.append("bootstrap — NPC catalog: %s" % str(npcs.get("errors", [])))
	if bool(interactions.get("ok", false)):
		_interactions = Dictionary(interactions.get("catalog", {}))
	else:
		_failures.append("bootstrap — interaction catalog: %s" % str(interactions.get("errors", [])))
	if bool(bundle.get("ok", false)):
		_world_definitions = Dictionary(bundle.get("catalogs", {})).get("world", {}).duplicate(true)
	else:
		_failures.append("bootstrap — content bundle: %s" % str(bundle.get("errors", [])))


func _test_catalog() -> void:
	_expect_equal(_interactions.get("schema_version"), 1, "schema version")
	_expect_equal(_interactions.get("catalog_id"), "npc_interaction_catalog_v1", "catalog ID")
	_expect_equal(Array(_interactions.get("interactions", [])).size(), 9, "interaction count")
	var counts: Dictionary = {}
	for raw: Variant in _interactions.get("interactions", []):
		var entry: Dictionary = raw
		var npc_id := String(entry.get("npc_id", ""))
		counts[npc_id] = int(counts.get(npc_id, 0)) + 1
		_expect(Array(entry.get("effects", [])).size() >= 1, "%s has effects" % entry.get("id", ""))
		_expect(String(entry.get("outcome", "")).strip_edges() != "", "%s has Russian outcome" % entry.get("id", ""))
	for npc_id: String in NPC_IDS:
		_expect_equal(counts.get(npc_id, 0), 3, "%s interaction count" % npc_id)
	var broken := _interactions.duplicate(true)
	broken["interactions"][0]["effects"].append({"type": "run_script", "path": "res://bad.gd"})
	_expect(not bool(InteractionCatalog.validate(broken).get("ok", true)), "executable effect must fail validation")


func _test_schedules() -> void:
	_expect(not _present("npc_viktor_koren", _stamp(1980, 9, 1, 449), "recycling_point"), "Viktor before 07:30")
	_expect(_present("npc_viktor_koren", _stamp(1980, 9, 1, 450), "recycling_point"), "Viktor at 07:30")
	_expect(_present("npc_viktor_koren", _stamp(1980, 9, 1, 1049), "recycling_point"), "Viktor before 17:30")
	_expect(not _present("npc_viktor_koren", _stamp(1980, 9, 1, 1050), "recycling_point"), "Viktor at 17:30")
	_expect(not _present("npc_viktor_koren", _stamp(1980, 9, 7, 600), "recycling_point"), "Viktor Sunday")
	_expect(_present("npc_lidia_maren", _stamp(1980, 9, 6, 719), "clinic_yard"), "Lidia Saturday before noon")
	_expect(not _present("npc_lidia_maren", _stamp(1980, 9, 6, 720), "clinic_yard"), "Lidia Saturday at noon")
	_expect(not _present("npc_tamara_roven", _stamp(1980, 9, 1, 600), "market"), "Tamara Monday")
	_expect(_present("npc_tamara_roven", _stamp(1980, 9, 2, 360), "market"), "Tamara Tuesday at 06:00")
	_expect(not _present("npc_tamara_roven", _stamp(1980, 9, 2, 600), "clinic_yard"), "wrong location")


func _test_pure_reads() -> void:
	var session := _session("recycling_point")
	if session == null:
		return
	var before := session.to_dict()
	var first := InteractionService.location_actions(session, false)
	var second := InteractionService.location_actions(session, false)
	_expect_equal(second, first, "location NPC models are stable")
	_expect_equal(first.size(), 1, "only Viktor is present at the recycling point")
	_expect_equal(first[0].get("intent", {}).get("payload", {}).get("npc_id"), "npc_viktor_koren", "typed NPC intent")
	var model_a := InteractionService.npc_model(session, "npc_viktor_koren", true)
	var model_b := InteractionService.npc_model(session, "npc_viktor_koren", true)
	_expect_equal(model_b, model_a, "NPC model is deterministic")
	_expect_equal(session.to_dict(), before, "all reads leave session and RNG untouched")


func _test_hidden_and_shown_blocked() -> void:
	var session := _session("clinic_yard")
	if session == null:
		return
	var hidden := InteractionService.npc_model(session, "npc_lidia_maren", false)
	var shown := InteractionService.npc_model(session, "npc_lidia_maren", true)
	_expect(bool(hidden.get("ok", false)), "Lidia model resolves")
	_expect_equal(Array(hidden.get("interactions", [])).size(), 1, "only baseline interaction is visible")
	_expect_equal(Array(shown.get("interactions", [])).size(), 3, "preference reveals both locked interactions")
	var blocked := _find(Array(shown.get("interactions", [])), "npc_interaction_lidia_sort_supplies")
	_expect(not bool(blocked.get("available", true)), "intelligence-gated interaction is blocked")
	_expect(not Array(blocked.get("reasons", [])).is_empty(), "blocked interaction has exact reason")
	_expect(String(Array(blocked.get("reasons", []))[0].get("message", "")).contains("Интеллект"), "reason is authored Russian text")


func _test_repeat_history() -> void:
	var viktor := _session("recycling_point")
	if viktor == null:
		return
	var first := InteractionCommand.execute(viktor, "npc_viktor_koren", "npc_interaction_viktor_ask_shift", "npc_test_daily_1")
	_expect(bool(first.get("ok", false)), "first daily conversation succeeds")
	var same_day := InteractionService.preview(viktor, "npc_viktor_koren", "npc_interaction_viktor_ask_shift")
	_expect(not bool(same_day.get("available", true)), "same civil day is blocked")
	_expect_equal(same_day.get("repeat", {}).get("code"), "already_used_today", "daily repeat code")
	_expect(_advance_fixture(viktor, 1440), "fixture reaches next civil day")
	var next_day := InteractionService.preview(viktor, "npc_viktor_koren", "npc_interaction_viktor_ask_shift")
	_expect(bool(next_day.get("available", false)), "daily conversation reopens next day")

	var lidia := _session("clinic_yard")
	if lidia == null:
		return
	_expect(bool(InteractionCommand.execute(lidia, "npc_lidia_maren", "npc_interaction_lidia_ask_support", "npc_test_cooldown_1").get("ok", false)), "cooldown conversation succeeds")
	var cooling := InteractionService.preview(lidia, "npc_lidia_maren", "npc_interaction_lidia_ask_support")
	_expect(not bool(cooling.get("available", true)), "cooldown starts after confirmation")
	_expect_equal(cooling.get("repeat", {}).get("code"), "cooldown_active", "cooldown code")
	var summary := InteractionHistory.summary(lidia.run_state, "npc_interaction_lidia_ask_support")
	_expect_equal(summary.get("occurrences"), 1, "history reconstructs occurrence")


func _test_atomic_command() -> void:
	var session := _session("recycling_point")
	if session == null:
		return
	var minutes_before := session.run_state.calendar.elapsed_minutes
	var energy_before := session.run_state.get_meter("energy")
	var result := InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_clear_yard", "npc_test_atomic_1")
	_expect(bool(result.get("ok", false)), "meaningful interaction succeeds: %s" % result.get("error", ""))
	_expect_equal(session.run_state.calendar.elapsed_minutes, minutes_before + 20, "authored time commits")
	_expect(session.run_state.get_meter("energy") < energy_before, "actor cost commits")
	_expect_equal(session.social_state.relationship("npc_viktor_koren")["trust"], 1, "small trust step commits")
	_expect_equal(session.social_state.memories_for("npc_viktor_koren").size(), 1, "typed memory commits")
	_expect(session.world_state.fact_value("fact_recycling_yard_cleared"), "world trace commits")
	_expect_equal(session.survival_state.processed_elapsed_minutes, session.run_state.calendar.elapsed_minutes, "survival stays synchronized")


func _test_idempotency_and_atomic_block() -> void:
	var session := _session("recycling_point")
	if session == null:
		return
	var command_id := "npc_test_idempotent_1"
	var first := InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_clear_yard", command_id)
	_expect(bool(first.get("ok", false)), "first command succeeds")
	var after := session.to_dict()
	var duplicate := InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_clear_yard", command_id)
	_expect_equal(duplicate.get("code"), "already_applied", "duplicate is explicit")
	_expect_equal(session.to_dict(), after, "duplicate changes nothing")
	var blocked_before := session.to_dict()
	var blocked := InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_clear_yard", "npc_test_blocked_2")
	_expect_equal(blocked.get("code"), "interaction_blocked", "one-per-life repeat is blocked")
	_expect_equal(session.to_dict(), blocked_before, "blocked command is fully atomic")


func _test_memory_followup() -> void:
	var session := _session("recycling_point")
	if session == null:
		return
	var before := InteractionService.preview(session, "npc_viktor_koren", "npc_interaction_viktor_inspection_followup")
	_expect(not bool(before.get("available", true)), "follow-up starts locked")
	_expect(bool(InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_ask_shift", "npc_test_followup_talk").get("ok", false)), "first distinct meeting succeeds")
	_expect(bool(InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_clear_yard", "npc_test_followup_help").get("ok", false)), "meaningful help succeeds")
	var after := InteractionService.preview(session, "npc_viktor_koren", "npc_interaction_viktor_inspection_followup")
	_expect(bool(after.get("available", false)), "knowledge, trust and memory unlock follow-up")
	_expect(bool(InteractionCommand.execute(session, "npc_viktor_koren", "npc_interaction_viktor_inspection_followup", "npc_test_followup_finish").get("ok", false)), "follow-up commits")
	_expect(session.run_state.get_knowledge_level("recycling_inspection_rules") >= 1, "follow-up grants relevant knowledge")


func _session(location_id: String) -> GameSession:
	if _world_definitions.is_empty():
		_expect(false, "world definitions must load")
		return null
	var state := RunState.new(BUILD, 19_803_001)
	var world := WorldFactory.from_catalog(_world_definitions, state.calendar.current_stamp())
	var session := GameSessionScript.new(state, location_id, {}, world, SocialState.fresh(), {})
	_expect(bool(session.validate().get("ok", false)), "session fixture validates")
	return session


func _present(npc_id: String, stamp: Dictionary, location_id: String) -> bool:
	return bool(ScheduleResolver.presence(_npc_catalog, npc_id, stamp, location_id).get("present", false))


func _stamp(year: int, month: int, day: int, minute: int) -> Dictionary:
	return {"year": year, "month": month, "day": day, "minute_of_day": minute, "elapsed_minutes": 0}


func _advance_fixture(session: GameSession, minutes: int) -> bool:
	if not session.run_state.calendar.advance_minutes(minutes):
		return false
	session.survival_state.processed_elapsed_minutes += minutes
	return bool(session.validate().get("ok", false))


func _find(entries: Array, interaction_id: String) -> Dictionary:
	for raw: Variant in entries:
		if raw is Dictionary and String(raw.get("id", "")) == interaction_id:
			return Dictionary(raw)
	return {}


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M3F.3 NPC DOMAIN TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
