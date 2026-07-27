extends SceneTree

const Bundle := preload("res://game/content/catalogs/content_catalog_bundle.gd")
const KnowledgeCatalog := preload("res://game/content/catalogs/knowledge_catalog.gd")
const NpcCatalog := preload("res://game/content/catalogs/npc_catalog.gd")
const ReputationCatalog := preload("res://game/content/catalogs/reputation_catalog.gd")
const WorldCatalog := preload("res://game/content/catalogs/world_definition_catalog.gd")

const KNOWLEDGE_IDS := [
	"underpass_layout",
	"underpass_services",
	"underpass_dry_corner",
	"station_layout",
	"embankment_routines",
	"embankment_shelter",
	"market_schedule",
	"station_schedule",
	"district_services",
	"clinic_hours",
	"clinic_support",
	"recycling_rates",
	"recycling_basics",
	"recycling_scale",
	"metal_grades",
	"recycling_safety",
	"recycling_shift_routine",
	"recycling_inspection_rules",
]
const CANONICAL_NPC_IDS := [
	"npc_viktor_koren", "npc_lidia_maren", "npc_tamara_roven",
]
const REPUTATION_IDS := [
	"rep_recycling_reliability", "rep_recycling_work_quality", "rep_market_fair_dealing",
]
const TASK_IDS := [
	"task_recycling_identify_material",
	"task_recycling_move_load",
	"task_recycling_prepare_scale",
	"task_recycling_clear_press",
	"task_recycling_handle_customer",
	"task_recycling_safety_check",
]
const METRIC_IDS := [
	"metric_riverside_goods_supply",
	"metric_riverside_job_availability",
	"metric_riverside_sanitation",
	"metric_riverside_safety",
	"metric_riverside_institution_pressure",
]
const FACT_IDS := [
	"fact_recycling_scale_calibrated",
	"fact_recycling_yard_cleared",
	"fact_recycling_press_safe",
]
const PROCESS_STAGE_IDS := [
	"latent", "warning", "preparation", "inspection",
	"approved", "restricted", "closed_temporarily",
]

var _catalogs: Dictionary = {}
var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	var loaded := Bundle.load_default()
	if bool(loaded.get("ok", false)):
		_catalogs = Dictionary(loaded.get("catalogs", {}))
	else:
		_failures.append("catalog setup — %s" % str(loaded.get("errors", [])))
	_run("versioned bundle loads", _test_versioned_bundle)
	_run("knowledge keeps fact and topic semantics", _test_knowledge)
	_run("three canonical NPC definitions are connected", _test_npcs)
	_run("reputations are audience-scoped", _test_reputations)
	_run("recycling job contains six task classes", _test_job)
	_run("world definitions contain metrics, facts and process graph", _test_world)
	_run("local validators reject malformed definitions", _test_local_failures)
	_run("bundle rejects broken cross-catalog references", _test_cross_reference_failures)
	_run("loaded catalogs are independent deep copies", _test_deep_copy)
	if _failures.is_empty():
		print("M3F.1 CONTENT CATALOG TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.1 CONTENT CATALOG TESTS FAILED: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


func _test_versioned_bundle() -> void:
	_expect(_catalogs.size() == 5, "bundle must contain exactly five definition catalogs")
	var expected_ids := {
		"knowledge": "knowledge_catalog_v1",
		"npcs": "npc_catalog_v1",
		"reputations": "reputation_catalog_v1",
		"jobs": "job_catalog_v1",
		"world": "world_definition_catalog_v1",
	}
	for key: String in expected_ids:
		var catalog: Dictionary = _catalogs.get(key, {})
		_expect_equal(catalog.get("schema_version"), 1, "%s schema version" % key)
		_expect_equal(catalog.get("catalog_id"), expected_ids[key], "%s catalog ID" % key)
	var validation := Bundle.validate(_catalogs)
	_expect(
		bool(validation.get("ok", false)),
		"bundle must validate: %s" % [validation.get("errors", [])]
	)


func _test_knowledge() -> void:
	var definitions: Array = Dictionary(_catalogs.get("knowledge", {})).get("knowledge", [])
	_expect_equal(definitions.size(), 18, "knowledge definition count")
	var ids := _id_set(definitions)
	_expect_equal(_sorted(ids.keys()), _sorted(KNOWLEDGE_IDS), "knowledge IDs")
	for knowledge_id: String in [
		"recycling_safety", "recycling_shift_routine", "recycling_inspection_rules",
	]:
		_expect(ids.has(knowledge_id), "missing recycling knowledge %s" % knowledge_id)
	for raw_definition: Variant in definitions:
		var definition: Dictionary = raw_definition
		var kind := String(definition.get("kind", ""))
		var expected_max := 1 if kind == "fact" else 3
		_expect_equal(
			definition.get("max_level"),
			expected_max,
			"%s must use %s level semantics" % [definition.get("id", ""), kind]
		)


func _test_npcs() -> void:
	var catalog: Dictionary = _catalogs.get("npcs", {})
	var npcs: Array = catalog.get("npcs", [])
	var schedules := _id_set(catalog.get("schedules", []))
	var profiles := _id_set(catalog.get("speech_profiles", []))
	_expect_equal(_sorted_ids(npcs), _sorted(CANONICAL_NPC_IDS), "canonical NPC IDs")
	for raw_npc: Variant in npcs:
		var npc: Dictionary = raw_npc
		_expect(schedules.has(npc.get("schedule_id")), "%s schedule ref" % npc.get("id", ""))
		_expect(profiles.has(npc.get("speech_profile_id")), "%s speech profile ref" % npc.get("id", ""))
		_expect(
			Array(npc.get("appearance_refs", [])).size() >= 3,
			"%s must have at least three appearances" % npc.get("id", "")
		)
	for raw_profile: Variant in catalog.get("speech_profiles", []):
		var profile: Dictionary = raw_profile
		_expect(not profile.has("dialect_text"), "speech profiles must not encode dialect text")
		_expect(not profile.has("phonetic_accent"), "speech profiles must not encode accents")


func _test_reputations() -> void:
	var catalog: Dictionary = _catalogs.get("reputations", {})
	var audiences := _id_set(catalog.get("audiences", []))
	var reputations: Array = catalog.get("reputations", [])
	_expect_equal(_sorted_ids(reputations), _sorted(REPUTATION_IDS), "reputation IDs")
	for raw_reputation: Variant in reputations:
		var reputation: Dictionary = raw_reputation
		_expect(audiences.has(reputation.get("audience_id")), "%s audience ref" % reputation.get("id", ""))
		_expect_equal(reputation.get("minimum"), -100, "reputation minimum")
		_expect_equal(reputation.get("maximum"), 100, "reputation maximum")
		_expect_equal(reputation.get("requires_observed_source"), true, "observed source rule")


func _test_job() -> void:
	var catalog: Dictionary = _catalogs.get("jobs", {})
	var jobs: Array = catalog.get("jobs", [])
	var tasks: Array = catalog.get("task_classes", [])
	_expect_equal(jobs.size(), 1, "job count")
	_expect_equal(_sorted_ids(tasks), _sorted(TASK_IDS), "task class IDs")
	if jobs.is_empty():
		return
	var job: Dictionary = jobs[0]
	_expect_equal(job.get("id"), "job_recycling_sorter", "first job ID")
	_expect_equal(_sorted(Array(job.get("task_class_ids", []))), _sorted(TASK_IDS), "job task refs")
	_expect_equal(job.get("tasks_per_shift_min"), 2, "minimum tasks per shift")
	_expect_equal(job.get("tasks_per_shift_max"), 3, "maximum tasks per shift")
	_expect_equal(job.get("decisions_per_shift"), 1, "decisions per shift")


func _test_world() -> void:
	var catalog: Dictionary = _catalogs.get("world", {})
	var metrics: Array = catalog.get("metrics", [])
	var facts: Array = catalog.get("facts", [])
	var processes: Array = catalog.get("processes", [])
	_expect_equal(_sorted_ids(metrics), _sorted(METRIC_IDS), "world metric IDs")
	_expect_equal(_sorted_ids(facts), _sorted(FACT_IDS), "world fact IDs")
	for raw_metric: Variant in metrics:
		var metric: Dictionary = raw_metric
		_expect(int(metric.get("default", -1)) in range(0, 101), "%s default range" % metric.get("id", ""))
	for raw_fact: Variant in facts:
		_expect_equal(Dictionary(raw_fact).get("default"), false, "world facts start false")
	_expect_equal(processes.size(), 1, "world process count")
	if processes.is_empty():
		return
	var process: Dictionary = processes[0]
	_expect_equal(process.get("id"), "process_recycling_inspection", "world process ID")
	_expect_equal(_sorted_ids(process.get("stages", [])), _sorted(PROCESS_STAGE_IDS), "process stages")
	_expect_equal(Array(process.get("transitions", [])).size(), 6, "process transition count")
	_expect_equal(
		_sorted(_transition_edges(process.get("transitions", []))),
		_sorted([
			"latent>warning",
			"warning>preparation",
			"preparation>inspection",
			"inspection>approved",
			"inspection>restricted",
			"inspection>closed_temporarily",
		]),
		"process transition graph"
	)
	_expect_equal(process.get("initial_stage_id"), "latent", "initial process stage")
	_expect_equal(
		_sorted(Array(process.get("terminal_stage_ids", []))),
		_sorted(["approved", "restricted", "closed_temporarily"]),
		"terminal process stages"
	)


func _test_local_failures() -> void:
	var knowledge: Dictionary = _catalogs["knowledge"].duplicate(true)
	var knowledge_entries: Array = knowledge["knowledge"]
	var bad_knowledge: Dictionary = knowledge_entries[0]
	bad_knowledge["id"] = "Bad-ID"
	knowledge_entries[0] = bad_knowledge
	knowledge["knowledge"] = knowledge_entries
	_expect(not bool(KnowledgeCatalog.validate(knowledge).get("ok", true)), "invalid knowledge ID must fail")

	var npcs: Dictionary = _catalogs["npcs"].duplicate(true)
	var npc_entries: Array = npcs["npcs"]
	var bad_npc: Dictionary = npc_entries[0]
	bad_npc["schedule_id"] = "schedule_missing"
	npc_entries[0] = bad_npc
	npcs["npcs"] = npc_entries
	_expect(not bool(NpcCatalog.validate(npcs).get("ok", true)), "unknown schedule must fail")

	var reputations: Dictionary = _catalogs["reputations"].duplicate(true)
	var reputation_entries: Array = reputations["reputations"]
	var bad_reputation: Dictionary = reputation_entries[0]
	bad_reputation["audience_id"] = "org_missing"
	reputation_entries[0] = bad_reputation
	reputations["reputations"] = reputation_entries
	_expect(
		not bool(ReputationCatalog.validate(reputations).get("ok", true)),
		"unknown reputation audience must fail"
	)

	var world: Dictionary = _catalogs["world"].duplicate(true)
	var processes: Array = world["processes"]
	var process: Dictionary = processes[0]
	var transitions: Array = process["transitions"]
	transitions.remove_at(0)
	process["transitions"] = transitions
	processes[0] = process
	world["processes"] = processes
	_expect(not bool(WorldCatalog.validate(world).get("ok", true)), "unreachable process graph must fail")


func _test_cross_reference_failures() -> void:
	var missing_supervisor := _catalogs.duplicate(true)
	var job_catalog: Dictionary = missing_supervisor["jobs"]
	var jobs: Array = job_catalog["jobs"]
	var job: Dictionary = jobs[0]
	job["supervisor_npc_id"] = "npc_missing"
	jobs[0] = job
	job_catalog["jobs"] = jobs
	missing_supervisor["jobs"] = job_catalog
	_expect(
		not bool(Bundle.validate(missing_supervisor).get("ok", true)),
		"unknown job supervisor must fail bundle validation"
	)

	var missing_knowledge := _catalogs.duplicate(true)
	job_catalog = missing_knowledge["jobs"]
	var tasks: Array = job_catalog["task_classes"]
	var task: Dictionary = tasks[0]
	task["knowledge_ids"] = ["unknown_recycling_topic"]
	tasks[0] = task
	job_catalog["task_classes"] = tasks
	missing_knowledge["jobs"] = job_catalog
	_expect(
		not bool(Bundle.validate(missing_knowledge).get("ok", true)),
		"unknown task knowledge must fail bundle validation"
	)


func _test_deep_copy() -> void:
	var modified := _catalogs.duplicate(true)
	var knowledge: Dictionary = modified["knowledge"]
	var entries: Array = knowledge["knowledge"]
	var entry: Dictionary = entries[0]
	entry["title"] = "changed by test"
	entries[0] = entry
	knowledge["knowledge"] = entries
	modified["knowledge"] = knowledge
	var loaded_again := Bundle.load_default()
	_expect(bool(loaded_again.get("ok", false)), "second bundle load must succeed")
	var fresh_catalogs: Dictionary = loaded_again.get("catalogs", {})
	var fresh_knowledge: Dictionary = fresh_catalogs.get("knowledge", {})
	var fresh_entries: Array = fresh_knowledge.get("knowledge", [])
	_expect(not fresh_entries.is_empty(), "fresh knowledge must exist")
	if not fresh_entries.is_empty():
		_expect(
			Dictionary(fresh_entries[0]).get("title") != "changed by test",
			"a caller mutation must not leak into a later load"
		)


func _id_set(raw_entries: Variant) -> Dictionary:
	var result: Dictionary = {}
	for raw_entry: Variant in raw_entries:
		if raw_entry is Dictionary:
			result[String(raw_entry.get("id", ""))] = true
	return result


func _sorted_ids(raw_entries: Variant) -> Array:
	return _sorted(_id_set(raw_entries).keys())


func _transition_edges(raw_transitions: Variant) -> Array:
	var result: Array = []
	for raw_transition: Variant in raw_transitions:
		if raw_transition is Dictionary:
			result.append("%s>%s" % [
				raw_transition.get("from_stage_id", ""),
				raw_transition.get("to_stage_id", ""),
			])
	return result


func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort()
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])
