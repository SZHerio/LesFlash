extends SceneTree

## M5 stage 4, second half: one profession carried to its end.
##
## Until now every shift paid the same and the foreman spoke to a man on his
## hundredth day exactly as on his first. The work could dismiss you and could
## be mastered, but it could not *know* you.
##
## The checks that matter: the ladder starts at the bottom, every rung above it
## is reachable, none of them can be skipped, the paper is not the top, and the
## climb is worth making.

const RunStateScript = preload("res://core/state/run_state.gd")
const WorkStateScript = preload("res://game/jobs/job_work_state.gd")
const MasteryScript = preload("res://game/jobs/job_mastery.gd")
const Ladder = preload("res://game/jobs/job_ladder.gd")

const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const JOB := "job_recycling_sorter"

var _failures: Array[String] = []


func _init() -> void:
	_test_a_stranger_starts_at_the_bottom()
	_test_every_rung_is_reachable()
	_test_no_rung_can_be_skipped()
	_test_the_paper_is_not_the_top()
	_test_the_climb_is_worth_making()
	_test_the_greeting_changes()
	_finish()


## Builds a work state that has lived through `shifts` shifts covering `classes`
## different kinds of task, with the given standing.
func _worked(shifts: int, classes: int, standing: int) -> JobWorkState:
	var state: JobWorkState = WorkStateScript.fresh()
	var record: Dictionary = state.call("_ensure_record", JOB) if state.has_method("_ensure_record") else {}
	var mastery: Dictionary = MasteryScript.fresh(JOB)
	var class_ids: Array = []
	for index: int in classes:
		class_ids.append("task_fixture_%d" % index)
	for index: int in shifts:
		var worked: Array = class_ids if index == 0 else []
		mastery["completed_shifts"].append({
			"shift_id": "shift_fixture_%d" % index,
			"task_class_ids": class_ids.duplicate() if index == 0 else [],
			"new_task_class_ids": worked.duplicate(),
			"overall": 60,
		})
	mastery["practiced_task_class_ids"] = class_ids.duplicate()
	mastery["mastery_points"] = class_ids.size()
	if record.is_empty():
		record = state.employment.get(JOB, {})
	if record.is_empty():
		state.employment[JOB] = {
			"mastery": mastery,
			"standing": standing,
			"next_shift_sequence": shifts + 1,
			"last_completed_day_index": -1,
		}
	else:
		record["mastery"] = mastery
		record["standing"] = standing
	return state


func _state(papers: Array = []) -> RunState:
	var run_state: RunState = RunStateScript.new(BUILD, 4242)
	for paper: String in papers:
		run_state.grant_qualification(paper)
	return run_state


func _test_a_stranger_starts_at_the_bottom() -> void:
	_expect_equal(
		Ladder.grade_of(_state(), WorkStateScript.fresh(), JOB),
		Ladder.CASUAL,
		"a man who has never worked here is not on the books"
	)
	_expect_equal(
		Ladder.grade_of(null, null, JOB),
		Ladder.CASUAL,
		"a missing state must read as the bottom rung, not crash"
	)


## The failure this whole stage exists to prevent: a rung nobody can reach,
## which is what happened to the quick shift shortcut when skills changed.
func _test_every_rung_is_reachable() -> void:
	for grade_id: String in Ladder.ORDER:
		var grade: Dictionary = Ladder.GRADES[grade_id]
		var papers: Array = []
		var paper := String(grade["qualification_id"])
		if not paper.is_empty():
			papers.append(paper)
		var reached := Ladder.grade_of(
			_state(papers),
			_worked(int(grade["shifts"]), int(grade["classes"]), int(grade["standing"])),
			JOB
		)
		_expect_equal(
			reached,
			grade_id,
			"meeting everything %s asks for did not reach it" % grade_id
		)


func _test_no_rung_can_be_skipped() -> void:
	# Every paper in the world, but no work behind him.
	var papered := Ladder.grade_of(_state(["qual_repair_certificate"]), WorkStateScript.fresh(), JOB)
	_expect_equal(papered, Ladder.CASUAL, "a certificate alone made him a tradesman")
	# All the work, no paper.
	var master_grade: Dictionary = Ladder.GRADES[Ladder.MASTER]
	var unpapered := Ladder.grade_of(
		_state(),
		_worked(int(master_grade["shifts"]), int(master_grade["classes"]), int(master_grade["standing"])),
		JOB
	)
	_expect_equal(unpapered, Ladder.REGULAR, "years of work made him a master with no paper at all")
	# Work and paper, but the foreman has had to redo his work.
	var in_bad_standing := Ladder.grade_of(
		_state(["qual_repair_certificate"]),
		_worked(int(master_grade["shifts"]), int(master_grade["classes"]), -1),
		JOB
	)
	_expect(
		in_bad_standing != Ladder.MASTER,
		"a man they keep correcting was called a master"
	)


## Being certified and being the one they ask for are different things, and the
## second is not sold at a counter.
func _test_the_paper_is_not_the_top() -> void:
	var certified: Dictionary = Ladder.GRADES[Ladder.CERTIFIED]
	var master: Dictionary = Ladder.GRADES[Ladder.MASTER]
	_expect(
		int(master["shifts"]) > int(certified["shifts"]),
		"the top rung asks for no more work than the paper does"
	)
	_expect_equal(
		String(master["qualification_id"]),
		String(certified["qualification_id"]),
		"the top rung must be earned by work, not by a second paper"
	)


func _test_the_climb_is_worth_making() -> void:
	var previous := 0
	for grade_id: String in Ladder.ORDER:
		var pay := Ladder.pay_basis_points(grade_id)
		_expect(
			pay > previous,
			"%s pays no better than the rung below it" % grade_id
		)
		previous = pay
	# And the top must be worth the road: half again a casual day, or the arc is
	# a long walk to the same wage.
	_expect(
		Ladder.pay_basis_points(Ladder.MASTER) >= Ladder.pay_basis_points(Ladder.CASUAL) * 15 / 10,
		"the master's day is worth less than half again a casual one"
	)


## Rule 3.4: the player is never told he was promoted. The foreman simply speaks
## to him differently, and every rung has to have its own words.
func _test_the_greeting_changes() -> void:
	var seen: Dictionary = {}
	for grade_id: String in Ladder.ORDER:
		var line := Ladder.address_at(grade_id)
		_expect(line.strip_edges() != "", "%s has nothing to say" % grade_id)
		_expect(not seen.has(line), "%s is greeted exactly like another rung" % grade_id)
		seen[line] = true
		# And the greeting must not name the rung: that would be the interface
		# explaining its own mechanics.
		_expect(
			not line.to_lower().contains(Ladder.title_of(grade_id)),
			"%s is greeted by being told his own grade" % grade_id
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 JOB LADDER TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 JOB LADDER: %s" % failure)
	quit(1)
