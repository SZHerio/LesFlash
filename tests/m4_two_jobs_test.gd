extends SceneTree

## M4 asks for two professions. This proves the second one is a real job and not
## a catalog entry: it generates its own shift, keeps its own practice, and its
## standing at one employer says nothing about the other.

const CatalogScript = preload("res://game/jobs/job_shift_catalog.gd")
const Generator = preload("res://game/jobs/job_shift_generator.gd")
const WorkState = preload("res://game/jobs/job_work_state.gd")
const Mastery = preload("res://game/jobs/job_mastery.gd")
const CommandScript = preload("res://game/jobs/job_session_command.gd")

const SORTER := "job_recycling_sorter"
const PORTER := "job_market_porter"

var _failures: Array[String] = []


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		_fail("catalog: %s" % str(loaded.get("errors", [])))
		_finish()
		return
	var catalog: Dictionary = loaded["catalog"]
	_test_both_jobs_generate(catalog)
	_test_shifts_differ(catalog)
	_test_standing_is_per_employer()
	_test_each_place_offers_its_own_job()
	_finish()


func _test_both_jobs_generate(catalog: Dictionary) -> void:
	for job_id: String in [SORTER, PORTER]:
		var generated := Generator.generate(catalog, job_id, 4_242, 1)
		_expect(
			bool(generated.get("ok", false)),
			"%s must generate a shift: %s" % [job_id, str(generated.get("errors", []))]
		)
		if not bool(generated.get("ok", false)):
			continue
		var snapshot: Dictionary = generated["snapshot"]
		_expect(
			String(snapshot.get("job_id", "")) == job_id,
			"%s produced a snapshot for %s" % [job_id, String(snapshot.get("job_id", ""))]
		)
		_expect(
			Array(snapshot.get("steps", [])).size() >= 3,
			"%s must run at least three steps" % job_id
		)


## The two shifts must not be the same work wearing a different name.
func _test_shifts_differ(catalog: Dictionary) -> void:
	var sorter := Generator.generate(catalog, SORTER, 4_242, 1)
	var porter := Generator.generate(catalog, PORTER, 4_242, 1)
	if not bool(sorter.get("ok", false)) or not bool(porter.get("ok", false)):
		return
	_expect(
		_class_ids(sorter["snapshot"]) != _class_ids(porter["snapshot"]),
		"both professions drew on the same task classes"
	)
	_expect(
		String(Dictionary(sorter["snapshot"]).get("briefing", {}).get("title", ""))
			!= String(Dictionary(porter["snapshot"]).get("briefing", {}).get("title", "")),
		"both professions share one briefing"
	)


## Being let go from the yard must not cost the market job.
func _test_standing_is_per_employer() -> void:
	var state: JobWorkState = WorkState.fresh()
	for _strike: int in 3:
		state._record_standing(SORTER, "unsafe")
	_expect(state.is_dismissed(SORTER), "three unsafe shifts must end the yard job")
	_expect(not state.is_dismissed(PORTER), "the market job was ended by the yard's record")
	_expect(
		int(state.sequence_for(PORTER)) == 1,
		"the market shift counter moved because of the yard"
	)
	_expect(
		String(state.mastery_for(PORTER).get("job_id", "")) == PORTER,
		"the market keeps its own practice"
	)
	# A save round-trip must not merge the two records.
	var restored: JobWorkState = WorkState.from_dict(state.to_dict())
	_expect(restored != null, "a two-employer state must survive save and load")
	if restored != null:
		_expect(restored.is_dismissed(SORTER), "dismissal was lost on reload")
		_expect(not restored.is_dismissed(PORTER), "dismissal leaked onto the other employer")


func _test_each_place_offers_its_own_job() -> void:
	var yard := CommandScript.job_at("recycling_point")
	var market := CommandScript.job_at("market")
	_expect(String(yard.get("job_id", "")) == SORTER, "the yard must offer sorting")
	_expect(String(market.get("job_id", "")) == PORTER, "the market must offer loading")
	_expect(
		String(yard.get("supervisor", "")) != String(market.get("supervisor", "")),
		"both postings are run by the same person"
	)
	_expect(CommandScript.job_at("embankment").is_empty(), "the embankment hires nobody")


func _class_ids(snapshot: Dictionary) -> Array:
	var result: Array = []
	for raw_step: Variant in Array(snapshot.get("steps", [])):
		var step: Dictionary = raw_step
		if String(step.get("kind", "")) == "task":
			result.append(String(step.get("task_class_id", "")))
	result.sort()
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M4 TWO JOBS TEST PASSED: sorter and porter are separate professions")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M4 TWO JOBS: %s" % failure)
	quit(1)
