class_name JobLadder
extends RefCounted

## How a person stops being whoever showed up at the gate.
##
## Until now every shift paid the same and every supervisor spoke to the hero
## the same way on his hundredth day as on his first. The work had depth — you
## could be dismissed, you could earn the shortcut — but no *standing*: nothing
## that said this is a man they know.
##
## A grade is never stored. It is derived from what the hero has actually done —
## shifts behind him, kinds of task he has practised, the paper in his pocket,
## and what the supervisor thinks of him — so it cannot drift out of step with
## the record, and no save needs migrating when the ladder changes.

const MasteryScript := preload("res://game/jobs/job_mastery.gd")
const AgingRulesScript := preload("res://game/aging/aging_rules.gd")

const CASUAL := "casual"
const REGULAR := "regular"
const CERTIFIED := "certified"
const MASTER := "master"

const ORDER := [CASUAL, REGULAR, CERTIFIED, MASTER]

## What each rung asks for, and what it is worth. `pay_basis_points` multiplies
## the shift's pay: a casual hand is paid what the job is worth and no more,
## while the man they ask for by name is worth half again as much.
##
## The paper is deliberately not the top rung. Holding a certificate makes you
## certified; being the one they call is something else, and it is earned by the
## work, not at a counter.
const GRADES := {
	CASUAL: {
		"title": "подённый",
		"address": "Эй, ты — на сортировку.",
		"shifts": 0,
		"classes": 0,
		"standing": -99,
		"qualification_id": "",
		"pay_basis_points": 10_000,
	},
	REGULAR: {
		"title": "постоянный",
		"address": "Опять ты. Ладно, вставай на своё место.",
		"shifts": 4,
		"classes": 3,
		"standing": 0,
		"qualification_id": "",
		"pay_basis_points": 11_500,
	},
	CERTIFIED: {
		"title": "слесарь",
		"address": "С бумагой — значит, на весы и пресс тоже.",
		"shifts": 8,
		"classes": 4,
		"standing": 1,
		"qualification_id": "qual_repair_certificate",
		"pay_basis_points": 13_500,
	},
	MASTER: {
		"title": "мастер",
		"address": "Пришёл — хорошо. Сам знаешь, с чего начинать.",
		"shifts": 14,
		"classes": 5,
		"standing": 2,
		"qualification_id": "qual_repair_certificate",
		"pay_basis_points": 15_500,
	},
}


## The rung the hero stands on with this employer right now.
static func grade_of(run_state: RunState, work_state: JobWorkState, job_id: String) -> String:
	if run_state == null or work_state == null:
		return CASUAL
	var mastery: Dictionary = work_state.mastery_for(job_id)
	var shifts := Array(mastery.get("completed_shifts", [])).size()
	var classes := Array(mastery.get("practiced_task_class_ids", [])).size()
	var record: Dictionary = work_state.record_for(job_id)
	var raw_standing: Variant = record.get("standing", 0)
	var standing := int(raw_standing) if typeof(raw_standing) in [TYPE_INT, TYPE_FLOAT] else 0
	# Years count for something at the gate. An older man is taken at his word
	# sooner than a young one with the same shifts behind him — which is the half
	# of ageing that is not loss, and the only reason getting older is playable.
	standing += AgingRulesScript.regard(run_state)
	var reached := CASUAL
	for grade_id: String in ORDER:
		var grade: Dictionary = GRADES[grade_id]
		if shifts < int(grade["shifts"]) or classes < int(grade["classes"]):
			continue
		if standing < int(grade["standing"]):
			continue
		var paper := String(grade["qualification_id"])
		if not paper.is_empty() and not run_state.holds_qualification(paper):
			continue
		reached = grade_id
	return reached


static func title_of(grade_id: String) -> String:
	return String(Dictionary(GRADES.get(grade_id, {})).get("title", ""))


## How the supervisor greets someone at this rung. Rule 3.4: this is where the
## player learns he has moved up — from being spoken to differently, not from a
## number going up on a screen.
static func address_at(grade_id: String) -> String:
	return String(Dictionary(GRADES.get(grade_id, {})).get("address", ""))


static func pay_basis_points(grade_id: String) -> int:
	return int(Dictionary(GRADES.get(grade_id, {})).get("pay_basis_points", 10_000))


## What still stands between the hero and the next rung, in the words he would
## use. Empty when he is at the top, or when the next rung is already his.
static func next_step(run_state: RunState, work_state: JobWorkState, job_id: String) -> Dictionary:
	var current := grade_of(run_state, work_state, job_id)
	var index := ORDER.find(current)
	if index < 0 or index + 1 >= ORDER.size():
		return {}
	var next_id := String(ORDER[index + 1])
	var grade: Dictionary = GRADES[next_id]
	var mastery: Dictionary = work_state.mastery_for(job_id)
	var missing: Array[String] = []
	if Array(mastery.get("completed_shifts", [])).size() < int(grade["shifts"]):
		missing.append("отработать больше смен")
	if Array(mastery.get("practiced_task_class_ids", [])).size() < int(grade["classes"]):
		missing.append("взяться за то, чего ещё не делал")
	var record: Dictionary = work_state.record_for(job_id)
	var raw_standing: Variant = record.get("standing", 0)
	var standing := int(raw_standing) if typeof(raw_standing) in [TYPE_INT, TYPE_FLOAT] else 0
	if standing < int(grade["standing"]):
		missing.append("работать так, чтобы не переделывали")
	var paper := String(grade["qualification_id"])
	if not paper.is_empty() and not run_state.holds_qualification(paper):
		missing.append("получить бумагу")
	return {
		"grade_id": next_id,
		"title": String(grade["title"]),
		"missing": missing,
	}
