extends SceneTree

## M5 stage 2: a skill is a name and the things that teach it.
##
## The check this suite exists for is the last one: every skill the save format
## knows must be reachable past rank zero. Before the catalog, six of seven were
## not — the whole game offered fewer than three different ways to practise each,
## and the skill screen showed numbers that could never move.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const CatalogScript = preload("res://game/skills/skill_catalog.gd")
const JobCatalogScript = preload("res://game/jobs/job_shift_catalog.gd")
const ActionCatalogScript = preload("res://game/sandbox/sandbox_action_catalog.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _catalog: Dictionary = {}
var _failures: Array[String] = []


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		_failures.append("the skill catalog does not load: %s" % str(loaded.get("errors", [])))
		_finish()
		return
	_catalog = loaded["catalog"]
	_test_every_skill_is_taught_by_something()
	_test_every_rank_that_exists_is_reachable()
	_test_one_source_teaches_one_skill()
	_test_a_thin_family_is_refused()
	_test_declared_sources_exist_in_content()
	_test_a_location_action_teaches()
	_test_nothing_grants_a_rank_outright()
	_finish()


## Three different sources is the first rank. A family below that is a promise
## the game cannot keep, and the catalog must refuse to make it.
func _test_every_skill_is_taught_by_something() -> void:
	for skill_id: String in GameRules.SKILL_KEYS:
		var entry := CatalogScript.find(_catalog, skill_id)
		_expect(not entry.is_empty(), "%s is not in the catalog: nothing teaches it" % skill_id)
		if entry.is_empty():
			continue
		_expect(
			Array(entry.get("applications", [])).size() >= CatalogScript.MIN_APPLICATIONS,
			"%s has %d applications, below the first rank" % [
				skill_id, Array(entry.get("applications", [])).size(),
			]
		)


func _test_every_rank_that_exists_is_reachable() -> void:
	var reachable := CatalogScript.reachable_ranks(_catalog)
	for skill_id: String in GameRules.SKILL_KEYS:
		_expect(
			int(reachable.get(skill_id, 0)) >= 1,
			"%s can never leave rank zero (reachable=%d)" % [skill_id, int(reachable.get(skill_id, 0))]
		)


## A single confirmed press teaching two skills would let one thing count as two
## different things, which is exactly what variety is supposed to prevent.
func _test_one_source_teaches_one_skill() -> void:
	var owner_of: Dictionary = {}
	for raw_entry: Variant in Array(_catalog.get("skills", [])):
		var entry: Dictionary = raw_entry
		for raw_application: Variant in Array(entry.get("applications", [])):
			var source_id := String(Dictionary(raw_application).get("source_id", ""))
			_expect(
				not owner_of.has(source_id),
				"%s teaches both %s and %s" % [source_id, String(owner_of.get(source_id, "")), String(entry.get("id", ""))]
			)
			owner_of[source_id] = String(entry.get("id", ""))


func _test_a_thin_family_is_refused() -> void:
	var thin: Dictionary = _catalog.duplicate(true)
	Dictionary(Array(thin["skills"])[0])["applications"] = [
		{"kind": "job_task", "source_id": "task_recycling_move_load"},
	]
	_expect(
		not bool(CatalogScript.validate(thin).get("ok", true)),
		"a family with one application was accepted"
	)


## A catalog naming things that do not exist is a wish list. Every job task and
## every location action it claims has to be findable in the content.
func _test_declared_sources_exist_in_content() -> void:
	var jobs := JobCatalogScript.load_default()
	if bool(jobs.get("ok", false)):
		var known: Dictionary = {}
		for raw_task: Variant in Array(Dictionary(jobs["catalog"]).get("tasks", [])):
			known[String(Dictionary(raw_task).get("task_class_id", ""))] = true
		for source_id: String in CatalogScript.sources_of_kind(_catalog, "job_task"):
			_expect(known.has(source_id), "the catalog claims a shift task that does not exist: %s" % source_id)

	var actions := ActionCatalogScript.load_default()
	if bool(actions.get("ok", false)):
		var known_actions: Dictionary = {}
		for raw_action: Variant in Array(Dictionary(actions["catalog"]).get("actions", [])):
			known_actions[String(Dictionary(raw_action).get("action_id", ""))] = true
		# Actions that only open a screen return before any effect is applied, so
		# declaring one as an application promises practice that never arrives.
		# This is how action_underpass_enter_service_yard slipped in.
		const NAVIGATION_INTENTS := ["enter_search", "open_store", "open_shelter", "open_job", "open_recycling_sale"]
		var intent_of: Dictionary = {}
		for raw_action: Variant in Array(Dictionary(actions["catalog"]).get("actions", [])):
			var action: Dictionary = raw_action
			intent_of[String(action.get("action_id", ""))] = String(
				Dictionary(action.get("intent", {})).get("type", "")
			)
		for source_id: String in CatalogScript.sources_of_kind(_catalog, "location_action"):
			_expect(
				known_actions.has(source_id),
				"the catalog claims a location action that does not exist: %s" % source_id
			)
			_expect(
				String(intent_of.get(source_id, "")) not in NAVIGATION_INTENTS,
				"%s only opens a screen — it can never record practice" % source_id
			)


## The claim that matters in play: confirming something in a place records
## practice, which before this stage it never did.
func _test_a_location_action_teaches() -> void:
	var adapter = SandboxAdapter.create(BUILD, 55_401)
	if adapter == null:
		_failures.append("the sandbox refused to start — the practice check was skipped")
		return
	var session = adapter.get("_session")
	# The command reads base_location first; setting only the visible one leaves
	# the hero standing somewhere else as far as the action list is concerned.
	session.location = "underpass"
	if "base_location" in session:
		session.base_location = "underpass"
	session.phase = "map"
	var before := int(session.run_state.practice_sources("city_navigation"))
	var performed: Dictionary = adapter.perform_location_action("action_underpass_read_wayfinding")
	_expect(bool(performed.get("ok", false)), "reading the signs failed: %s" % str(performed))
	if not bool(performed.get("ok", false)):
		return
	_expect(
		int(session.run_state.practice_sources("city_navigation")) > before,
		"doing something in a place taught nothing"
	)
	# Doing the same thing again teaches nothing new: repetition is not variety.
	var after_first := int(session.run_state.practice_sources("city_navigation"))
	adapter.perform_location_action("action_underpass_read_wayfinding")
	_expect_equal(
		int(session.run_state.practice_sources("city_navigation")),
		after_first,
		"repeating one action counted as new practice"
	)


## Nothing in live content may hand a rank over. Ranks are earned by variety, and
## a single card granting one made the thresholds decorative for that skill.
func _test_nothing_grants_a_rank_outright() -> void:
	var content := FileAccess.get_file_as_string("res://game/district/district_content.gd")
	_expect(
		not content.contains("unlock_skill"),
		"the district content still grants a skill rank instead of teaching it"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 SKILL CATALOG TESTS PASSED: 7/7")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 SKILL CATALOG: %s" % failure)
	quit(1)
