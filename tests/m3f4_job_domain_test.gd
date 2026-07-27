extends SceneTree

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const CatalogScript := preload("res://game/jobs/job_shift_catalog.gd")
const Generator := preload("res://game/jobs/job_shift_generator.gd")
const SnapshotScript := preload("res://game/jobs/job_shift_snapshot.gd")
const ProgressScript := preload("res://game/jobs/job_shift_progress.gd")
const Service := preload("res://game/jobs/job_shift_service.gd")
const Mastery := preload("res://game/jobs/job_mastery.gd")
const WorkState := preload("res://game/jobs/job_work_state.gd")

const RUN_SEED := 19_803_001
const JOB_ID := "job_recycling_sorter"
const TASK_CLASSES := [
	"task_recycling_identify_material",
	"task_recycling_move_load",
	"task_recycling_prepare_scale",
	"task_recycling_clear_press",
	"task_recycling_handle_customer",
	"task_recycling_safety_check",
]

var _catalog: Dictionary = {}
var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_bootstrap()
	_run("versioned catalog validates all six reachable task classes", _test_catalog_schema)
	_run("same run job sequence and version always build the same immutable shift", _test_determinism)
	_run("generated shifts contain two or three tasks and one meaningful decision", _test_shift_shape_and_reachability)
	_run("snapshot and progress are JSON-safe round-trip contracts", _test_json_contracts)
	_run("preview and step resolution are pure no-op reads and repeatable candidates", _test_pure_service)
	_run("weak balanced and specialist builds produce coherent distinct results", _test_builds)
	_run("varied practice unlocks quick resolve while repetition cannot farm mastery", _test_variety_and_antifarm)
	_run("malformed catalog snapshot progress and history fail closed", _test_validation_failures)
	_run("polarity affinity makes the shift personal", _test_polarity_affinity_makes_the_shift_personal)
	_run("repeated bad shifts cost the job", _test_repeated_bad_shifts_cost_the_job)
	_finish()


func _bootstrap() -> void:
	var loaded := CatalogScript.load_default()
	if bool(loaded.get("ok", false)):
		_catalog = Dictionary(loaded["catalog"])
	else:
		_failures.append("bootstrap — %s" % str(loaded.get("errors", [])))


func _test_catalog_schema() -> void:
	_expect_equal(_catalog.get("schema_version"), 1, "catalog schema")
	_expect_equal(_catalog.get("catalog_id"), "job_shift_catalog_v1", "catalog ID")
	_expect_equal(Array(_catalog.get("jobs", [])).size(), 1, "one canonical job")
	_expect_equal(Array(_catalog.get("tasks", [])).size(), 6, "one authored task per canonical class")
	var classes: Array = []
	for raw: Variant in Array(_catalog.get("tasks", [])):
		classes.append(String(Dictionary(raw).get("task_class_id", "")))
	classes.sort()
	var expected := TASK_CLASSES.duplicate()
	expected.sort()
	_expect_equal(classes, expected, "all canonical task classes are reachable")
	_expect(bool(CatalogScript.validate(_catalog).get("ok", false)), "catalog passes validator")


func _test_determinism() -> void:
	var before := _catalog.duplicate(true)
	var first := Generator.generate(_catalog, JOB_ID, RUN_SEED, 4)
	var second := Generator.generate(_catalog, JOB_ID, RUN_SEED, 4)
	_expect(bool(first.get("ok", false)), "first generation succeeds")
	_expect_equal(second, first, "generation is byte-structure deterministic")
	_expect_equal(_catalog, before, "generation does not mutate catalog")
	var changed := Generator.generate(_catalog, JOB_ID, RUN_SEED, 5)
	_expect(first.get("snapshot") != changed.get("snapshot"), "sequence changes the persisted snapshot")
	_expect(String(Dictionary(first.get("snapshot", {})).get("seed", {}).get("stream_id", "")).contains("sequence:4"), "stream identifies sequence")


func _test_shift_shape_and_reachability() -> void:
	var reached: Dictionary = {}
	var decisions: Dictionary = {}
	for sequence: int in range(1, 13):
		var generated := Generator.generate(_catalog, JOB_ID, RUN_SEED, sequence)
		_expect(bool(generated.get("ok", false)), "sequence %d builds" % sequence)
		var snapshot: Dictionary = generated.get("snapshot", {})
		var steps: Array = snapshot.get("steps", [])
		_expect(steps.size() in [3, 4], "sequence %d has 3–4 total steps" % sequence)
		var task_count := 0
		var decision_count := 0
		for raw: Variant in steps:
			var step: Dictionary = raw
			if step.get("kind") == "task":
				task_count += 1
				reached[String(step.get("task_class_id", ""))] = true
			else:
				decision_count += 1
				decisions[String(step.get("content_id", ""))] = true
		_expect(task_count in [2, 3], "sequence %d has 2–3 tasks" % sequence)
		_expect_equal(decision_count, 1, "sequence %d has one decision" % sequence)
		_expect_equal(String(Dictionary(steps.back()).get("kind", "")), "decision", "decision closes sequence %d" % sequence)
	_expect_equal(reached.size(), 6, "all six classes appear across deterministic sequences")
	_expect(decisions.size() >= 2, "both meaningful decisions are reachable")


func _test_json_contracts() -> void:
	var snapshot := _snapshot(2)
	if snapshot.is_empty():
		return
	var start := Service.start(snapshot)
	_expect(bool(start.get("ok", false)), "progress starts")
	var progress: Dictionary = start.get("progress", {})
	var snapshot_round_trip: Variant = JsonValidator.normalize_numbers(JSON.parse_string(JSON.stringify(snapshot)))
	var progress_round_trip: Variant = JsonValidator.normalize_numbers(JSON.parse_string(JSON.stringify(progress)))
	_expect(bool(SnapshotScript.validate(snapshot_round_trip).get("ok", false)), "snapshot survives JSON")
	_expect(bool(ProgressScript.validate(progress_round_trip, snapshot_round_trip).get("ok", false)), "progress survives JSON")
	_expect_equal(snapshot_round_trip, snapshot, "snapshot round trip is lossless")
	_expect_equal(progress_round_trip, progress, "progress round trip is lossless")


func _test_pure_service() -> void:
	var snapshot := _snapshot(1)
	if snapshot.is_empty():
		return
	var progress: Dictionary = Service.start(snapshot).get("progress", {})
	var snapshot_before := snapshot.duplicate(true)
	var progress_before := progress.duplicate(true)
	var first_preview := Service.preview(snapshot, progress, _balanced_build())
	var second_preview := Service.preview(snapshot, progress, _balanced_build())
	_expect_equal(second_preview, first_preview, "preview is stable")
	_expect_equal(snapshot, snapshot_before, "preview leaves snapshot untouched")
	_expect_equal(progress, progress_before, "preview leaves progress untouched")
	var choice_id := String(Array(first_preview.get("choices", []))[1].get("id", ""))
	var first_resolution := Service.resolve_step(snapshot, progress, choice_id, _balanced_build())
	var repeated_candidate := Service.resolve_step(snapshot, progress, choice_id, _balanced_build())
	_expect_equal(repeated_candidate, first_resolution, "same pure request returns same candidate")
	_expect_equal(progress, progress_before, "resolution leaves source progress untouched")
	_expect(bool(ProgressScript.validate(first_resolution.get("progress", {}), snapshot).get("ok", false)), "candidate validates")


func _test_builds() -> void:
	var snapshot := _snapshot(5)
	if snapshot.is_empty():
		return
	var weak := _complete(snapshot, _weak_build(), 1)
	var balanced := _complete(snapshot, _balanced_build(), 1)
	var specialist := _complete(snapshot, _specialist_build(), 1)
	for pair: Array in [["weak", weak], ["balanced", balanced], ["specialist", specialist]]:
		_expect(bool(pair[1].get("ok", false)), "%s build completes" % pair[0])
		_expect(bool(ProgressScript.validate(pair[1].get("progress", {}), snapshot).get("ok", false)), "%s result validates" % pair[0])
	var weak_overall := int(Dictionary(weak.get("result", {})).get("overall", -1))
	var balanced_overall := int(Dictionary(balanced.get("result", {})).get("overall", -1))
	var specialist_overall := int(Dictionary(specialist.get("result", {})).get("overall", -1))
	_expect(weak_overall < balanced_overall, "balanced build outperforms weak build on same choices")
	_expect(balanced_overall <= specialist_overall, "relevant specialist is not penalized")
	_expect_equal(Dictionary(specialist.get("result", {})).get("job_id"), JOB_ID, "result keeps canonical job")


func _test_variety_and_antifarm() -> void:
	var history := Mastery.fresh()
	var total_awarded := 0
	for sequence: int in [1, 3, 5]:
		var completed := _complete(_snapshot(sequence), _specialist_build(), 1)
		var recorded := Mastery.record_completed_shift(history, completed.get("progress", {}), 1)
		_expect(bool(recorded.get("ok", false)), "shift %d records" % sequence)
		total_awarded += int(recorded.get("mastery_awarded", 0))
		history = Dictionary(recorded.get("history", {}))
	_expect_equal(int(history.get("mastery_points", -1)), Array(history.get("practiced_task_class_ids", [])).size(), "mastery equals varied classes only")
	_expect_equal(int(history.get("mastery_points", -1)), total_awarded, "only first practice awards mastery")
	_expect(Array(history.get("practiced_task_class_ids", [])).size() >= 4, "three varied shifts cover at least four classes")
	_expect(not Mastery.quick_resolve_eligible(history, 0), "cargo rank zero blocks quick resolve")
	_expect(Mastery.quick_resolve_eligible(history, 1), "three shifts four classes and cargo rank one unlock quick resolve")
	var duplicate_progress: Dictionary = _complete(_snapshot(5), _specialist_build(), 1).get("progress", {})
	var duplicate := Mastery.record_completed_shift(history, duplicate_progress, 1)
	_expect_equal(duplicate.get("code"), "already_recorded", "same shift cannot be recorded twice")
	_expect_equal(duplicate.get("mastery_awarded"), 0, "duplicate awards no mastery")
	_expect_equal(duplicate.get("history"), history, "duplicate leaves history untouched")
	var repeat_progress: Dictionary = _complete(_snapshot(7), _specialist_build(), 1).get("progress", {})
	var repeat_record := Mastery.record_completed_shift(history, repeat_progress, 1)
	var new_classes: Array = Array(repeat_record.get("history", {}).get("practiced_task_class_ids", []))
	var old_classes: Array = Array(history.get("practiced_task_class_ids", []))
	_expect(int(repeat_record.get("mastery_awarded", -1)) <= new_classes.size() - old_classes.size(), "repeat never awards for old classes")


func _test_validation_failures() -> void:
	var broken_catalog := _catalog.duplicate(true)
	broken_catalog["tasks"][0]["choices"][0]["scores"]["safety"] = 999
	_expect(not bool(CatalogScript.validate(broken_catalog).get("ok", true)), "out-of-range authored score fails")
	var missing_class := _catalog.duplicate(true)
	missing_class["tasks"].remove_at(0)
	_expect(not bool(CatalogScript.validate(missing_class).get("ok", true)), "unreachable class fails")
	var executable_catalog := _catalog.duplicate(true)
	executable_catalog["tasks"][0]["run_script"] = "res://bad.gd"
	_expect(not bool(CatalogScript.validate(executable_catalog).get("ok", true)), "unknown executable content field fails")
	var snapshot := _snapshot(1)
	var broken_snapshot := snapshot.duplicate(true)
	broken_snapshot["steps"][0]["task_class_id"] = ""
	_expect(not bool(SnapshotScript.validate(broken_snapshot).get("ok", true)), "broken snapshot fails")
	var rerolled_snapshot := snapshot.duplicate(true)
	rerolled_snapshot["seed"]["derived_seed"] = "7"
	_expect(not bool(SnapshotScript.validate(rerolled_snapshot).get("ok", true)), "rerolled seed fails integrity")
	var progress: Dictionary = Service.start(snapshot).get("progress", {})
	var broken_progress := progress.duplicate(true)
	broken_progress["scores"]["quality"] = NAN
	_expect(not bool(ProgressScript.validate(broken_progress, snapshot).get("ok", true)), "non-JSON progress fails")
	var broken_history := Mastery.fresh()
	broken_history["mastery_points"] = 1
	_expect(not bool(Mastery.validate(broken_history).get("ok", true)), "unearned mastery fails")


func _snapshot(sequence: int) -> Dictionary:
	var generated := Generator.generate(_catalog, JOB_ID, RUN_SEED, sequence)
	_expect(bool(generated.get("ok", false)), "snapshot %d generates: %s" % [sequence, str(generated.get("errors", []))])
	return Dictionary(generated.get("snapshot", {}))


func _complete(snapshot: Dictionary, build: Dictionary, choice_index: int) -> Dictionary:
	var start := Service.start(snapshot)
	if not bool(start.get("ok", false)):
		return start
	var progress: Dictionary = start["progress"]
	var latest := {"ok": true, "progress": progress, "result": {}}
	while String(progress.get("status", "")) == "active":
		var preview := Service.preview(snapshot, progress, build)
		if not bool(preview.get("ok", false)):
			return preview
		var choices: Array = preview["choices"]
		var index := mini(choice_index, choices.size() - 1)
		latest = Service.resolve_step(snapshot, progress, String(Dictionary(choices[index])["id"]), build)
		if not bool(latest.get("ok", false)):
			return latest
		progress = Dictionary(latest["progress"])
	return latest


## The point of the stage: the same shift has to be a different shift for a
## different hero, not one optimal button pressed by everyone.
func _test_polarity_affinity_makes_the_shift_personal() -> void:
	var snapshot := _snapshot(3)
	var careful := _balanced_build()
	careful["polarities"] = {"execution_style": 80, "decision_priority": 70}
	var hasty := _balanced_build()
	hasty["polarities"] = {"execution_style": -80, "decision_priority": -70}
	var centred := _balanced_build()
	centred["polarities"] = {}

	# Index 0 is the careful approach of every step.
	var careful_result: Dictionary = Dictionary(_complete(snapshot, careful, 0).get("result", {}))
	var hasty_result: Dictionary = Dictionary(_complete(snapshot, hasty, 0).get("result", {}))
	var centred_result: Dictionary = Dictionary(_complete(snapshot, centred, 0).get("result", {}))
	_expect(
		int(careful_result.get("overall", 0)) > int(centred_result.get("overall", 0)),
		"a hero who works the way the approach wants gained nothing: %d against %d"
			% [int(careful_result.get("overall", 0)), int(centred_result.get("overall", 0))]
	)
	_expect(
		int(hasty_result.get("overall", 0)) < int(centred_result.get("overall", 0)),
		"leaning the opposite way to the approach cost nothing: %d against %d"
			% [int(hasty_result.get("overall", 0)), int(centred_result.get("overall", 0))]
	)

	# A hero in the middle of every axis must be untouched, not merely average:
	# the middle option of a step carries no affinity at all.
	var start := Service.start(snapshot)
	var progress: Dictionary = start["progress"]
	var preview := Service.preview(snapshot, progress, centred)
	var middle_id := String(Dictionary(Array(preview["choices"])[1])["id"])
	var resolved := Service.resolve_step(snapshot, progress, middle_id, centred)
	var step_record: Dictionary = Array(Dictionary(resolved["progress"])["completed_steps"]).back()
	_expect(
		int(step_record.get("affinity_modifier", 99)) == 0,
		"the middle approach applied an affinity of %d" % int(step_record.get("affinity_modifier", 99))
	)

	# Determinism: the same hero on the same seed must land on the same number.
	_expect(
		int(Dictionary(_complete(snapshot, careful, 0).get("result", {})).get("overall", -1))
			== int(careful_result.get("overall", 0)),
		"the same hero and seed produced two different shifts"
	)


## Work badly enough for long enough and Viktor stops keeping you on. A good
## shift repairs standing, so it is a slope rather than a trapdoor.
func _test_repeated_bad_shifts_cost_the_job() -> void:
	var state: JobWorkState = WorkState.fresh()
	_expect(not state.is_dismissed(), "a fresh sorter is already dismissed")

	state._record_standing("weak")
	state._record_standing("weak")
	_expect(not state.is_dismissed(), "two weak shifts already cost the job")
	state._record_standing("solid")
	_expect(
		int(state.standing["strikes"]) == 1,
		"a good shift repaired nothing: %d strikes" % int(state.standing["strikes"])
	)

	state._record_standing("unsafe")
	_expect(
		state.is_dismissed(),
		"an unsafe shift on top of a warning did not end the job: %d strikes"
			% int(state.standing["strikes"])
	)
	state._record_standing("excellent")
	_expect(state.is_dismissed(), "a dismissal was undone by working well afterwards")

	# A save written before standing existed starts clean: inventing strikes from
	# a history the game never judged would punish the player retroactively.
	var legacy: Dictionary = WorkState.fresh().to_dict()
	legacy["schema_version"] = 1
	legacy.erase("standing")
	var migrated: JobWorkState = WorkState.from_dict(legacy)
	_expect(migrated != null, "a version 1 work state no longer loads")
	if migrated != null:
		_expect(not migrated.is_dismissed(), "migration invented a dismissal")
		_expect(int(migrated.standing["strikes"]) == 0, "migration invented strikes")
		_expect(
			int(migrated.to_dict()["schema_version"]) == WorkState.SCHEMA_VERSION,
			"migration did not raise the schema version"
		)


func _weak_build() -> Dictionary:
	return {"characteristics": {"strength": 1, "charisma": 1, "intelligence": 1, "luck": 1}, "skills": {}}


func _balanced_build() -> Dictionary:
	return {"characteristics": {"strength": 5, "charisma": 5, "intelligence": 5, "luck": 3}, "skills": {"cargo_handling": 1, "search": 1, "repair": 1, "trade": 1}}


func _specialist_build() -> Dictionary:
	return {"characteristics": {"strength": 8, "charisma": 7, "intelligence": 8, "luck": 3}, "skills": {"cargo_handling": 3, "search": 3, "repair": 3, "trade": 3}}


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
		print("M3F.4 JOB DOMAIN TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
