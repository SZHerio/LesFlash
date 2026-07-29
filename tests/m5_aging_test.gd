extends SceneTree

## M5 stage 7: what the years do, and the ceiling they had to break first.
##
## Two claims. A run is no longer seven days long — that number was scaffolding
## and became a wall the moment anything reached past a week. And ageing is not
## pure decline: every band takes something the body does and gives something
## the body cannot, because a game where each birthday is a loss teaches the
## player to stop living the life it is about.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const SurvivalStateScript = preload("res://game/survival/survival_state.gd")
const Aging = preload("res://game/aging/aging_rules.gd")
const Ladder = preload("res://game/jobs/job_ladder.gd")
const WorkStateScript = preload("res://game/jobs/job_work_state.gd")
const RunStateScript = preload("res://core/state/run_state.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_a_run_outlasts_a_week()
	_test_an_old_save_keeps_its_seven_days()
	_test_every_band_trades_rather_than_takes()
	_test_the_body_slows_with_the_years()
	_test_the_years_count_with_people()
	_finish()


## The ceiling that stopped a bench from ever paying for itself and a rent from
## ever falling due twice.
func _test_a_run_outlasts_a_week() -> void:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
		return
	var session = adapter.get("_session")
	var horizon := int(session.survival_state.horizon_minutes)
	_expect(
		horizon > SurvivalStateScript.WEEK_MINUTES,
		"a new run still ends at the old seven-day wall (horizon=%d)" % horizon
	)
	# A month has to be reachable, and the session has to still be valid there.
	session.run_state.calendar.advance_minutes(30 * 1440)
	session.survival_state.processed_elapsed_minutes = int(session.run_state.calendar.elapsed_minutes)
	var validation: Dictionary = session.validate()
	_expect(
		bool(validation.get("ok", false)),
		"a month into the run the session no longer validates: %s" % str(validation.get("errors", []))
	)
	_expect(session.clone() != null, "a month-old run cannot be cloned")


## A save written under seven days was played under seven days, and lengthening
## it after the fact would extend a run somebody already finished.
func _test_an_old_save_keeps_its_seven_days() -> void:
	var state := SurvivalStateScript.fresh(0, SurvivalStateScript.WEEK_MINUTES)
	var saved: Dictionary = state.to_dict()
	saved.erase("horizon_minutes")
	var restored := SurvivalStateScript.from_dict(saved)
	_expect(restored != null, "a save from before the horizon existed no longer opens")
	if restored != null:
		_expect_equal(
			int(restored.horizon_minutes),
			SurvivalStateScript.WEEK_MINUTES,
			"an old save was quietly given a longer life than it was played with"
		)


## The requirement written down before any of it: not pure decline.
func _test_every_band_trades_rather_than_takes() -> void:
	var validation := Aging.validate()
	_expect(
		bool(validation.get("ok", false)),
		"the bands do not balance: %s" % str(validation.get("errors", []))
	)
	var previous_stamina := 0
	var previous_regard := -1
	for index: int in Aging.BANDS.size():
		var band: Dictionary = Aging.BANDS[index]
		if index > 0:
			_expect(
				int(band["stamina_basis_points"]) < previous_stamina,
				"%s takes nothing from the body" % String(band["id"])
			)
			_expect(
				int(band["regard"]) > previous_regard,
				"%s gives nothing back for it" % String(band["id"])
			)
		previous_stamina = int(band["stamina_basis_points"])
		previous_regard = int(band["regard"])


func _test_the_body_slows_with_the_years() -> void:
	var young := Aging.band_for(20)
	var old := Aging.band_for(65)
	_expect(
		int(young["stamina_basis_points"]) > int(old["stamina_basis_points"]),
		"sixty-five is as strong as twenty"
	)
	_expect(
		int(old["exertion_extra"]) > int(young["exertion_extra"]),
		"a hard day costs the old no more than the young"
	)
	# And the band has to be read from the hero rather than guessed.
	var run_state: RunState = RunStateScript.new(BUILD, 4242)
	_expect(
		Aging.stamina_basis_points(run_state) > 0,
		"a real run state has no age band at all"
	)


## The half of ageing that is not loss: the gate takes an older man at his word
## sooner than a young one with the same shifts behind him.
func _test_the_years_count_with_people() -> void:
	_expect(
		Aging.regard(null) == 0,
		"a missing state was granted regard out of nowhere"
	)
	var young_band := Aging.band_for(20)
	var old_band := Aging.band_for(65)
	_expect(
		int(old_band["regard"]) > int(young_band["regard"]),
		"the years buy nothing with people"
	)
	# The ladder must actually read it, not merely have it available.
	var source := FileAccess.get_file_as_string("res://game/jobs/job_ladder.gd")
	_expect(
		source.contains("AgingRulesScript.regard"),
		"the work ladder does not take the years into account at all"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 AGING TESTS PASSED: 5/5")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 AGING: %s" % failure)
	quit(1)
