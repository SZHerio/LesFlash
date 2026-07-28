extends SceneTree

## M5: documents, clearances, courses and licences.
##
## A skill answers "what can he do", a qualification answers "is he allowed to".
## Keeping them apart is the point: knowing how to fix a scale is not the same
## as holding the paper that lets you be paid for it.

const RunStateScript = preload("res://core/state/run_state.gd")
const Catalog = preload("res://game/content/catalogs/qualification_catalog.gd")

const BUILD := {"strength": 6, "charisma": 3, "intelligence": 5, "luck": 4}

var _catalog: Dictionary = {}
var _failures: Array[String] = []


func _init() -> void:
	var loaded := Catalog.load_default()
	if not bool(loaded.get("ok", false)):
		_fail("catalog: %s" % str(loaded.get("errors", [])))
		_finish()
		return
	_catalog = loaded["catalog"]
	_test_catalog_shape()
	_test_prerequisites_terminate()
	_test_blockers_speak_plainly()
	_test_granting_is_recorded_once()
	_test_survives_save_and_migration()
	_finish()


func _state() -> RunState:
	return RunStateScript.new(BUILD, 4242)


func _test_catalog_shape() -> void:
	var entries: Array = _catalog.get("qualifications", [])
	_expect(entries.size() >= 5, "the catalog must carry the first five papers")
	var kinds: Dictionary = {}
	for raw: Variant in entries:
		var entry: Dictionary = raw
		kinds[String(entry.get("kind", ""))] = true
		_expect(
			String(entry.get("id", "")).begins_with("qual_"),
			"%s does not use the qual_ prefix" % String(entry.get("id", ""))
		)
	for kind: String in ["document", "clearance", "course", "licence"]:
		_expect(kinds.has(kind), "no qualification of kind %s exists" % kind)


## A paper that requires itself, directly or round a loop, can never be earned.
func _test_prerequisites_terminate() -> void:
	var looped: Dictionary = _catalog.duplicate(true)
	var entries: Array = looped["qualifications"]
	Dictionary(entries[0])["required_qualification_ids"] = [String(Dictionary(entries[1])["id"])]
	Dictionary(entries[1])["required_qualification_ids"] = [String(Dictionary(entries[0])["id"])]
	var validation := Catalog.validate(looped)
	_expect(
		not bool(validation.get("ok", true)),
		"a circular requirement chain was accepted"
	)


func _test_blockers_speak_plainly() -> void:
	var state := _state()
	var licence := Catalog.find(_catalog, "qual_trade_licence")
	_expect(not licence.is_empty(), "the trade licence is missing from the catalog")
	if licence.is_empty():
		return
	var blocked := Catalog.blockers(licence, state, state.qualifications)
	_expect(not blocked.is_empty(), "a penniless, unskilled hero was offered the licence")
	for reason: String in blocked:
		# Rule 3.4: the counter says what is missing, never which number.
		for character: String in reason:
			_expect(
				not character.is_valid_int(),
				"a blocker exposed a raw requirement: %s" % reason
			)

	# Everything satisfied at once clears the counter.
	var ready := _state()
	ready.money = 500
	ready.set_skill_rank("trade", 2)
	ready.knowledge["market_schedule"] = 1
	ready.grant_qualification("qual_residence_slip")
	ready.grant_qualification("qual_sanitary_book")
	_expect(
		Catalog.blockers(licence, ready, ready.qualifications).is_empty(),
		"a hero who met every requirement was still refused: %s"
			% str(Catalog.blockers(licence, ready, ready.qualifications))
	)


func _test_granting_is_recorded_once() -> void:
	var state := _state()
	_expect(state.grant_qualification("qual_residence_slip"), "the first grant was refused")
	_expect(state.holds_qualification("qual_residence_slip"), "the paper was not recorded")
	_expect(
		not state.grant_qualification("qual_residence_slip"),
		"the same paper was granted twice"
	)
	_expect(not state.grant_qualification(""), "an unnamed qualification was granted")


func _test_survives_save_and_migration() -> void:
	var state := _state()
	state.grant_qualification("qual_residence_slip")
	var restored: RunState = RunStateScript.from_dict(state.to_dict())
	_expect(restored != null, "a state holding papers failed to reload")
	if restored != null:
		_expect(
			restored.holds_qualification("qual_residence_slip"),
			"the paper was lost on reload"
		)
	var broken: Dictionary = state.to_dict()
	broken["qualifications"] = {"not_a_qualification": 0}
	_expect(
		RunStateScript.from_dict(broken) == null,
		"a save naming something that is not a qualification was accepted"
	)

	var legacy: Dictionary = state.to_dict()
	legacy.erase("qualifications")
	legacy["save_version"] = GameRules.RUN_STATE_VERSION_V5
	var migrated: RunState = RunStateScript.from_dict(legacy)
	_expect(migrated != null, "a version 5 run state no longer loads")
	if migrated != null:
		_expect(
			migrated.qualifications.is_empty(),
			"migration invented papers nobody was issued"
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M5 QUALIFICATION TESTS PASSED: 5/5")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 QUALIFICATION: %s" % failure)
	quit(1)
