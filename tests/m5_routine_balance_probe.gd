extends SceneTree

## Balance probe for M5 stage 1, run as its own pass after the mechanics were
## built. It asserts almost nothing; it measures, and prints what it measured.
##
## The question a routine has to answer is not "does it work" but "does it carry
## enough of the week to be worth writing". A routine interrupted at every
## stretch is a worse way of playing by hand. A routine that carries everything
## has taken the game away from the player. Somewhere in between is the point.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const RunnerScript = preload("res://app/routine/routine_runner.gd")

const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
## Long enough for a week and a half at four stretches a day.
const SLOTS := 40

var _failures: Array[String] = []


func _init() -> void:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		print("ROUTINE BALANCE PROBE: the sandbox refused to start")
		quit(1)
		return
	var session = adapter.get("_session")
	_plan_an_ordinary_week(adapter)
	adapter.set_routine_following(true)

	var carried := 0
	var unattended := 0
	var stops: Dictionary = {}
	var slots_run := 0
	for _attempt: int in SLOTS:
		if String(adapter.get_phase()) == "completed":
			break
		var before := int(session.run_state.calendar.elapsed_minutes)
		var report: Dictionary = adapter.follow_routine(1)
		slots_run += 1
		for raw_entry: Variant in Array(report.get("carried", [])):
			carried += 1
			if bool(Dictionary(raw_entry).get("unattended", false)):
				unattended += 1
		var stopped := String(report.get("stopped", ""))
		stops[stopped] = int(stops.get(stopped, 0)) + 1
		print("    slot %d at %s: %s — %s" % [slots_run, adapter.get_location_id(), stopped, String(report.get("reason", ""))])
		if stopped in [RunnerScript.STOP_TERMINAL]:
			break
		# The player's part: answer what the routine handed back. A probe that
		# never answers measures a player who walked away from the phone.
		if stopped == RunnerScript.STOP_EVENT:
			_answer_what_is_waiting(adapter)
		# A stop that costs no time would spin here forever; the probe would
		# rather report that than hang.
		if int(session.run_state.calendar.elapsed_minutes) == before and stopped != RunnerScript.STOP_DONE:
			stops["no_progress"] = int(stops.get("no_progress", 0)) + 1
			if int(stops["no_progress"]) > 3:
				break

	var elapsed := int(session.run_state.calendar.elapsed_minutes)
	@warning_ignore("integer_division")
	var days := elapsed / 1440
	print("ROUTINE BALANCE PROBE")
	print("  slots attempted:  %d" % slots_run)
	print("  activities lived: %d (%d of them unattended)" % [carried, unattended])
	print("  game time:        %d days %d hours" % [days, (elapsed % 1440) / 60])
	print("  meters:           hunger=%d energy=%d health=%d money=%d" % [
		int(session.run_state.get_meter("hunger")),
		int(session.run_state.get_meter("energy")),
		int(session.run_state.get_meter("health")),
		int(session.run_state.money),
	])
	print("  stopped because:  %s" % str(stops))
	print("ROUTINE BALANCE PROBE WRITTEN")
	quit(0)


## Answers whatever is standing in front of the hero, the way a player would:
## the first option offered, without deliberating.
func _answer_what_is_waiting(adapter: Object) -> void:
	if bool(adapter.is_job_shift_active()):
		var step: Dictionary = Dictionary(adapter.get_job_shift_model().get("current_step", {}))
		var choices: Array = Array(step.get("choices", []))
		if not choices.is_empty():
			adapter.resolve_job_shift_step(String(Dictionary(choices[0]).get("id", "")))
			return
	var event: Dictionary = adapter.get_current_event_model()
	var options: Array = Array(event.get("choices", []))
	if not options.is_empty():
		adapter.resolve_choice(String(Dictionary(options[0]).get("id", "")))


## A week a person might actually keep: earn in the mornings, spend the day on
## whatever the earning needs — hand in what was found, or lay in food — eat in
## the evening, sleep at night. Not optimal; plausible, and it has to supply
## itself, because a plan that assumes food appears is not a plan.
func _plan_an_ordinary_week(adapter: Object) -> void:
	# A shift takes the morning and the day both; the afternoon entry is left
	# empty on working days because the day is already spent.
	const WEEK := {
		1: ["routine_shift_yard", ""],
		2: ["routine_shift_yard", ""],
		3: ["routine_search_underpass", "routine_stock_food"],
		4: ["routine_shift_yard", ""],
		5: ["routine_search_underpass", "routine_recycle"],
		6: ["routine_search_yard", "routine_recycle"],
		7: ["routine_rest", "routine_stock_food"],
	}
	for day: int in WEEK:
		adapter.set_routine_block(day, "morning", String(Array(WEEK[day])[0]))
		var afternoon := String(Array(WEEK[day])[1])
		if not afternoon.is_empty():
			adapter.set_routine_block(day, "day", afternoon)
		adapter.set_routine_block(day, "evening", "routine_eat")
		adapter.set_routine_block(day, "night", "routine_sleep")
