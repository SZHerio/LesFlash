extends SceneTree

const Bundle := preload("res://game/content/catalogs/content_catalog_bundle.gd")
const WorldFactory := preload("res://game/content/world_state_factory.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")
const WorldReadModelScript := preload("res://core/world/world_read_model.gd")
const SocialMutationScript := preload("res://core/social/social_mutation.gd")
const EventContextScript := preload("res://game/events/event_context.gd")
const EventConditions := preload("res://game/events/event_condition_evaluator.gd")
const EventDirectorScript := preload("res://game/events/event_director.gd")
const EventHistoryScript := preload("res://game/events/event_history.gd")
const SessionTransaction := preload("res://game/session/session_command_transaction.gd")
const GameSessionScript := preload("res://app/session/game_session.gd")
const EventCommandScript := preload("res://game/events/event_command.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""
var _world_definitions: Dictionary = {}


func _init() -> void:
	var loaded := Bundle.load_default()
	if bool(loaded.get("ok", false)):
		_world_definitions = Dictionary(loaded["catalogs"]["world"]).duplicate(true)
	else:
		_failures.append("bootstrap — %s" % str(loaded.get("errors", [])))
	_run("world bootstrap and read model are deterministic", _test_world_bootstrap)
	_run("world mutations enforce process graph and facts", _test_world_mutation)
	_run("typed social state stores relationships memory and commitments", _test_social_state)
	_run("EventContext v2 exposes world and social conditions", _test_event_context)
	_run("session command commits actor social world time and stock once", _test_session_transaction)
	_run("failed session command leaves the complete session unchanged", _test_session_atomic_failure)
	_run("event session command applies authored world and social effects", _test_event_session_command)
	_run("due world mutations wait for confirmed time passage", _test_due_requires_time)
	_run("event lifetime limit is rebuilt from the authoritative journal", _test_event_history_limit)
	if _failures.is_empty():
		print("M3F.1 WORLD TRANSACTION TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.1 WORLD TRANSACTION TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_world_bootstrap() -> void:
	var state := _world_state()
	_expect(state != null, "factory must create a valid state")
	if state == null:
		return
	_expect_equal(state.metrics.size(), 5, "all district metrics are initialized")
	_expect_equal(state.metric_value("metric_riverside_goods_supply"), 52, "metric default")
	_expect(not state.fact_value("fact_recycling_press_safe"), "world fact default")
	_expect_equal(state.process_stage("process_recycling_inspection"), "latent", "initial process stage")
	var rules := WorldReadModelScript.rules_projection(state)
	var observed := WorldReadModelScript.observed_projection(state, {
		"metrics": ["metric_riverside_goods_supply"],
		"facts": [],
		"processes": [],
	})
	_expect_equal(rules["metrics"].size(), 5, "rules projection retains hidden metrics")
	_expect_equal(observed["metrics"].size(), 1, "observed projection filters hidden metrics")
	_expect_equal(state.revision, 0, "read models never mutate state")


func _test_world_mutation() -> void:
	var state := _world_state()
	if state == null:
		return
	var before := state.to_dict()
	var invalid := _world_apply(state, [{
		"type": "advance_world_process",
		"id": "process_recycling_inspection",
		"stage": "approved",
		"trigger_id": "requirements_met",
	}])
	_expect(not bool(invalid.get("ok", true)), "process cannot skip stages")
	_expect_equal(state.to_dict(), before, "rejected world mutation is atomic")
	for transition: Dictionary in [
		{"stage": "warning", "trigger_id": "inspection_notice_received"},
		{"stage": "preparation", "trigger_id": "preparation_started"},
		{"stage": "inspection", "trigger_id": "inspection_time_reached"},
	]:
		var result := _world_apply(state, [{
			"type": "advance_world_process",
			"id": "process_recycling_inspection",
			"stage": transition["stage"],
			"trigger_id": transition["trigger_id"],
		}])
		_expect(bool(result.get("ok", false)), "valid transition to %s" % transition["stage"])
	var blocked := _world_apply(state, [{
		"type": "advance_world_process",
		"id": "process_recycling_inspection",
		"stage": "approved",
		"trigger_id": "requirements_met",
	}])
	_expect(not bool(blocked.get("ok", true)), "approval requires objective facts")
	var facts: Array = []
	for fact_id: String in [
		"fact_recycling_scale_calibrated",
		"fact_recycling_yard_cleared",
		"fact_recycling_press_safe",
	]:
		facts.append({"type": "set_world_fact", "id": fact_id, "value": true})
	_expect(bool(_world_apply(state, facts).get("ok", false)), "facts commit together")
	_expect(bool(_world_apply(state, [{
		"type": "advance_world_process",
		"id": "process_recycling_inspection",
		"stage": "approved",
		"trigger_id": "requirements_met",
	}]).get("ok", false)), "facts unlock approval")


func _test_social_state() -> void:
	var social := SocialState.fresh()
	var result := SocialMutationScript.apply(social, {
		"schema_version": 1,
		"source_id": "test_help",
		"at": _state().calendar.current_stamp(),
		"operations": [
			{"type": "change_relationship", "npc_id": "npc_viktor_koren", "field": "trust", "delta": 12},
			{"type": "change_reputation", "reputation_id": "rep_recycling_reliability", "delta": 7},
			{"type": "add_npc_memory", "npc_id": "npc_viktor_koren", "memory": {
				"memory_id": "memory_helped_yard", "type_id": "helped", "valence": 20, "salience": 45,
			}},
			{"type": "create_commitment", "commitment": {
				"commitment_id": "commitment_return_gloves", "type_id": "return_item",
				"debtor_id": "hero", "creditor_id": "npc_viktor_koren", "subject_id": "work_gloves",
			}},
		],
	})
	_expect(bool(result.get("ok", false)), "typed social mutation must succeed: %s" % result.get("error", ""))
	_expect_equal(social.relationship("npc_viktor_koren")["trust"], 12, "trust changed")
	_expect_equal(social.memories_for("npc_viktor_koren").size(), 1, "memory stored")
	_expect_equal(social.commitments["commitment_return_gloves"]["state"], "open", "commitment stored")
	_expect(bool(social.validate().get("ok", false)), "result remains serializable")


func _test_event_context() -> void:
	var session := _session()
	if session == null:
		return
	var social_result := SocialMutationScript.apply(session.social_state, {
		"schema_version": 1, "source_id": "context_fixture", "at": session.run_state.calendar.current_stamp(),
		"operations": [
			{"type": "change_relationship", "npc_id": "npc_viktor_koren", "field": "respect", "delta": 8},
			{"type": "add_npc_memory", "npc_id": "npc_viktor_koren", "memory": {
				"memory_id": "memory_worked_well", "type_id": "worked_well", "valence": 15, "salience": 30,
			}},
		],
	})
	_expect(bool(social_result.get("ok", false)), "social fixture")
	var context := EventContextScript.build(session.run_state, {
		"kind": "location_action", "id": "inspect_scale", "action_id": "inspect_scale", "object_id": "scale",
	}, {
		"location_id": "recycling_point", "era_id": "ard_1980", "weather_id": "dry",
		"world": WorldReadModelScript.rules_projection(session.world_state),
		"relationships": session.social_state.relationships,
		"npc_memories": session.social_state.memories,
		"commitments": session.social_state.commitments,
		"reputations": session.social_state.reputations,
	})
	_expect(bool(EventContextScript.validate(context).get("ok", false)), "EventContext v2 validates")
	for condition: Dictionary in [
		{"kind": "world_metric", "id": "metric_riverside_goods_supply", "operator": ">=", "value": 50},
		{"kind": "world_process", "id": "process_recycling_inspection", "operator": "==", "value": "latent"},
		{"kind": "relationship", "id": "npc_viktor_koren", "field": "respect", "operator": ">=", "value": 8},
		{"kind": "npc_memory", "id": "memory_worked_well", "npc_id": "npc_viktor_koren", "operator": "==", "value": true},
		{"kind": "polarity", "id": "physical_specialization", "band": "neutral", "side": "center"},
	]:
		_expect(bool(EventConditions.evaluate(context, condition).get("passed", false)), "condition passes: %s" % str(condition))


func _test_session_transaction() -> void:
	var session := _session()
	if session == null:
		return
	var before_minutes := session.run_state.calendar.elapsed_minutes
	var result := SessionTransaction.execute(session, {
		"command_id": "command_combined_1",
		"source_id": "help_recycling_yard",
		"title": "Помочь во дворе",
		"conditions": [],
		"effects": [
			{"type": "advance_time", "minutes": 20, "reason": "Работа во дворе"},
			{"type": "change_state", "id": "energy", "delta": -4},
			{"type": "change_relationship", "npc_id": "npc_viktor_koren", "field": "trust", "delta": 5},
			{"type": "change_reputation", "reputation_id": "rep_recycling_reliability", "delta": 3},
			{"type": "set_world_fact", "id": "fact_recycling_yard_cleared", "value": true},
			{"type": "change_world_metric", "id": "metric_riverside_sanitation", "delta": 2},
			{"type": "replace_stock", "store_id": "store_market_food_row", "snapshot": {"store_id": "store_market_food_row", "schema_version": 1}},
		],
	}, {"world_definitions": _world_definitions})
	_expect(bool(result.get("ok", false)), "combined command succeeds: %s" % result.get("error", ""))
	_expect_equal(session.run_state.calendar.elapsed_minutes, before_minutes + 20, "time committed")
	_expect_equal(session.social_state.relationship("npc_viktor_koren")["trust"], 5, "relationship committed")
	_expect(session.world_state.fact_value("fact_recycling_yard_cleared"), "world fact committed")
	_expect(session.world_state.stock_snapshots.has("store_market_food_row"), "store stock committed")
	_expect(session.applied_command_ids.has("command_combined_1"), "idempotency ledger committed")
	var snapshot := session.to_dict()
	var duplicate := SessionTransaction.execute(session, {
		"command_id": "command_combined_1", "source_id": "different", "conditions": [],
		"effects": [{"type": "advance_time", "minutes": 999}],
	}, {"world_definitions": _world_definitions})
	_expect_equal(duplicate.get("code"), "already_applied", "duplicate is explicit")
	_expect_equal(session.to_dict(), snapshot, "duplicate changes nothing")


func _test_session_atomic_failure() -> void:
	var session := _session()
	if session == null:
		return
	var before := session.to_dict()
	var result := SessionTransaction.execute(session, {
		"command_id": "command_invalid_world",
		"source_id": "invalid_attempt",
		"title": "Неверная попытка",
		"conditions": [],
		"effects": [
			{"type": "advance_time", "minutes": 30},
			{"type": "change_relationship", "npc_id": "npc_viktor_koren", "field": "trust", "delta": 10},
			{"type": "advance_world_process", "id": "process_recycling_inspection", "stage": "approved", "trigger_id": "requirements_met"},
		],
	}, {"world_definitions": _world_definitions})
	_expect(not bool(result.get("ok", true)), "invalid world transition rejects command")
	_expect_equal(session.to_dict(), before, "actor, social, time and world all roll back")


func _test_event_session_command() -> void:
	var session := _session()
	if session == null:
		return
	var context := EventContextScript.build(session.run_state, {
		"kind": "location_action", "id": "event_fixture", "action_id": "answer", "object_id": "yard",
	}, {
		"location_id": "recycling_point", "era_id": "ard_1980", "weather_id": "dry",
		"world": WorldReadModelScript.rules_projection(session.world_state),
		"relationships": session.social_state.relationships,
		"npc_memories": session.social_state.memories,
		"commitments": session.social_state.commitments,
		"reputations": session.social_state.reputations,
	})
	var catalog := {"cards": [{
		"id": "event_session_fixture", "title": "Помощь во дворе", "tone": "positive", "cooldown_minutes": 0,
		"options": [{
			"id": "help", "label": "Помочь", "conditions": [], "outcome": "Двор стал чище.",
			"effects": [
				{"type": "advance_time", "minutes": 5},
				{"type": "change_relationship", "npc_id": "npc_viktor_koren", "field": "respect", "delta": 4},
				{"type": "set_world_fact", "id": "fact_recycling_yard_cleared", "value": true},
			],
		}],
	}]}
	var result := EventCommandScript.execute_session(session, catalog, "event_session_fixture", "help", context)
	_expect(bool(result.get("ok", false)), "event command succeeds: %s" % result.get("error", ""))
	_expect_equal(session.social_state.relationship("npc_viktor_koren")["respect"], 4, "event relationship effect committed")
	_expect(session.world_state.fact_value("fact_recycling_yard_cleared"), "event world effect committed")


func _test_due_requires_time() -> void:
	var session := _session()
	if session == null:
		return
	var scheduled := _world_apply(session.world_state, [{
		"type": "schedule_world_mutation",
		"mutation_id": "mutation_due_now",
		"due": {"elapsed_minutes": 0},
		"operations": [{"type": "change_world_metric", "id": "metric_riverside_sanitation", "delta": 1}],
	}])
	_expect(bool(scheduled.get("ok", false)), "due fixture schedules")
	var before_metric := session.world_state.metric_value("metric_riverside_sanitation")
	var zero_time := SessionTransaction.execute(session, {
		"command_id": "command_zero_time", "source_id": "read_notice", "title": "Осмотреться",
		"conditions": [], "effects": [],
	}, {"world_definitions": _world_definitions})
	_expect(bool(zero_time.get("ok", false)), "zero-time command itself succeeds")
	_expect_equal(session.world_state.metric_value("metric_riverside_sanitation"), before_metric, "zero-time command does not advance world queue")
	_expect_equal(session.world_state.scheduled_mutations.size(), 1, "due entry remains queued")
	var timed := SessionTransaction.execute(session, {
		"command_id": "command_time_passes", "source_id": "wait_one_minute", "title": "Подождать",
		"conditions": [], "effects": [{"type": "advance_time", "minutes": 1}],
	}, {"world_definitions": _world_definitions})
	_expect(bool(timed.get("ok", false)), "timed command succeeds")
	_expect_equal(session.world_state.metric_value("metric_riverside_sanitation"), before_metric + 1, "time passage applies due mutation")


func _test_event_history_limit() -> void:
	var state := _state()
	for option_id: String in ["first", "second"]:
		_expect(state.add_journal_entry(
			"action",
			"Проверка истории",
			{"event_id": "event_limited", "option_id": option_id}
		), "journal fixture appends")
	var facts := EventHistoryScript.facts(state, ["event:event_limited:legacy"])
	_expect_equal(facts.size(), 2, "journal occurrences are not double-counted with legacy snapshot")
	var context := EventContextScript.build(state, {
		"kind": "location_action", "id": "history_test", "action_id": "look", "object_id": "notice",
	}, {
		"location_id": "underpass", "era_id": "ard_1980", "weather_id": "dry",
		"history_facts": facts,
	})
	var analysis := EventDirectorScript.analyze({"cards": [{
		"id": "event_limited",
		"locations": ["underpass"],
		"source_kinds": ["location_action"],
		"conditions": [],
		"base_weight": 10,
		"luck_bias": 0,
		"max_occurrences": 2,
		"tone": "neutral",
	}]}, context)
	_expect(bool(analysis.get("ok", false)), "director accepts reconstructed context")
	var trace: Dictionary = Array(analysis.get("cards", []))[0]
	_expect(not bool(trace.get("included", true)), "card is excluded at its lifetime limit")
	_expect_equal(trace.get("occurrences"), 2, "every journal occurrence is counted")


func _world_apply(state: WorldState, operations: Array) -> Dictionary:
	return WorldMutationScript.apply(state, {
		"schema_version": 1,
		"source_id": "m3f1_test",
		"at": _state().calendar.current_stamp(),
		"operations": operations,
	}, _world_definitions)


func _world_state() -> WorldState:
	if _world_definitions.is_empty():
		_expect(false, "world catalog must load")
		return null
	return WorldFactory.from_catalog(_world_definitions, _state().calendar.current_stamp())


func _session() -> GameSession:
	var world := _world_state()
	if world == null:
		return null
	var session := GameSessionScript.new(_state(), "underpass", {}, world, SocialState.fresh(), {})
	_expect(bool(session.validate().get("ok", false)), "session fixture is valid")
	return session


func _state() -> RunState:
	return RunState.new({"strength": 5, "charisma": 4, "intelligence": 5, "luck": 4}, 1_980_101)


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_expect(false, "%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])
