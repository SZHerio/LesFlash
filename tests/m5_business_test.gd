extends SceneTree

## M5 stage 5: a place of his own.
##
## The requirement written down before a line of it was built: it has to work
## without him, or it is just another shift. That is what most of this checks —
## that days pass and the bench earns while nobody is watching, and that the
## same indifference can ruin a man who hires two hands and disappears.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const Catalog = preload("res://game/business/business_catalog.gd")
const StateScript = preload("res://game/business/business_state.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const BENCH := "business_repair_bench"

var _failures: Array[String] = []


func _init() -> void:
	_test_the_catalog_refuses_nonsense()
	_test_buying_costs_money_and_can_be_refused()
	_test_it_earns_while_nobody_watches()
	_test_it_can_ruin_him()
	_test_an_empty_bench_makes_nothing()
	_test_it_survives_a_save()
	_finish()


func _adapter() -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
		return null
	var session = adapter.get("_session")
	session.location = "workshop_row"
	if "base_location" in session:
		session.base_location = "workshop_row"
	session.phase = "map"
	return adapter


## Moves the clock the way a lived week would, without replaying one. The
## survival marker has to move with it: the session refuses to clone when the
## calendar and the body disagree about what day it is, and it is right to.
func _let_days_pass(session: Object, days: int) -> void:
	var minutes := days * 1440
	session.run_state.calendar.advance_minutes(minutes)
	var survival = session.get("survival_state")
	if survival != null:
		survival.processed_elapsed_minutes = int(session.run_state.calendar.elapsed_minutes)


func _entry() -> Dictionary:
	var loaded := Catalog.load_default()
	if not bool(loaded.get("ok", false)):
		_failures.append("the business catalog does not load: %s" % str(loaded.get("errors", [])))
		return {}
	return Catalog.find(Dictionary(loaded["catalog"]), BENCH)


## A venture that cannot fail is an allowance, and one that cannot pay is a
## punishment. The catalog must refuse both.
func _test_the_catalog_refuses_nonsense() -> void:
	var loaded := Catalog.load_default()
	_expect(bool(loaded.get("ok", false)), "the authored bench must validate")
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]

	var unprofitable: Dictionary = catalog.duplicate(true)
	Dictionary(Array(unprofitable["businesses"])[0])["revenue_per_unit_ard"] = 1
	_expect(
		not bool(Catalog.validate(unprofitable).get("ok", true)),
		"a bench whose work is worth less than its material was accepted"
	)

	var riskless: Dictionary = catalog.duplicate(true)
	var entry: Dictionary = Array(riskless["businesses"])[0]
	entry["rent_per_day_ard"] = 1
	entry["wage_per_day_ard"] = 1
	entry["revenue_per_unit_ard"] = 900
	_expect(
		bool(Catalog.validate(riskless).get("ok", false)),
		"a wildly profitable bench is allowed to exist; ruin comes from idleness, not from the rates"
	)


func _test_buying_costs_money_and_can_be_refused() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	var entry := _entry()
	if entry.is_empty():
		return
	session.run_state.money = 10
	_expect(
		not bool(adapter.open_business(BENCH).get("ok", true)),
		"a place was bought without the money for it"
	)
	session.run_state.money = int(entry["price_ard"]) + 500
	var before := int(session.run_state.money)
	var bought: Dictionary = adapter.open_business(BENCH)
	_expect(bool(bought.get("ok", false)), "the bench could not be bought: %s" % str(bought))
	if not bool(bought.get("ok", false)):
		return
	_expect_equal(
		int(session.run_state.money),
		before - int(entry["price_ard"]),
		"the price was not paid"
	)
	_expect(session.business_state.owns_anything(), "the bench was not recorded as his")
	_expect(
		not bool(adapter.open_business(BENCH).get("ok", true)),
		"he bought the same bench twice"
	)


## The whole point. Time passes elsewhere; the bench has been working.
func _test_it_earns_while_nobody_watches() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	var entry := _entry()
	if entry.is_empty():
		return
	session.run_state.money = int(entry["price_ard"]) + 4_000
	adapter.open_business(BENCH)
	adapter.restock_business(30)
	adapter.set_business_hands(2)
	var before := int(session.run_state.money)
	var stock_before := int(session.business_state.stock)

	# Five days spent anywhere else at all.
	_let_days_pass(session, 5)
	var settled: Dictionary = adapter.settle_business()
	_expect(bool(settled.get("ok", false)), "settling failed: %s" % str(settled))
	if not bool(settled.get("ok", false)):
		return
	var reckoning: Dictionary = settled.get("reckoning", {})
	_expect_equal(int(reckoning.get("days", 0)), 5, "five days were not reckoned")
	_expect(int(reckoning.get("units", 0)) > 0, "the bench made nothing in five days")
	_expect(int(session.run_state.money) > before, "five working days left him no better off")
	_expect(int(session.business_state.stock) < stock_before, "work consumed no material")
	# And settling twice for the same days must pay nothing the second time.
	var again: Dictionary = adapter.settle_business()
	_expect_equal(
		String(again.get("code", "")),
		"nothing_to_settle",
		"the same days were paid for twice"
	)


## The same indifference, from the other side.
func _test_it_can_ruin_him() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	var entry := _entry()
	if entry.is_empty():
		return
	session.run_state.money = int(entry["price_ard"]) + 900
	adapter.open_business(BENCH)
	adapter.set_business_hands(2)
	var before := int(session.run_state.money)
	# Six days away, with two people paid to stand at an empty bench. Not a
	# fortnight: the prototype run itself ends at seven days, and a test that
	# reaches past that is testing a game nobody can play yet.
	_let_days_pass(session, 6)
	var settled: Dictionary = adapter.settle_business()
	_expect(bool(settled.get("ok", false)), "settling a debt failed: %s" % str(settled))
	if not bool(settled.get("ok", false)):
		return
	_expect(
		int(Dictionary(settled.get("reckoning", {})).get("net", 0)) < 0,
		"six days of paying two people to do nothing came out positive"
	)
	_expect(int(session.run_state.money) < before, "the wages were never paid")
	_expect(
		int(Dictionary(settled.get("reckoning", {})).get("idle_days", 0)) > 0,
		"the idle days were not counted, so he cannot be told why"
	)


func _test_an_empty_bench_makes_nothing() -> void:
	var entry := _entry()
	if entry.is_empty():
		return
	var idle := Catalog.reckon(entry, 0, 2, 3)
	_expect_equal(int(idle["units"]), 0, "a bench with no material made something")
	_expect_equal(int(idle["idle_days"]), 3, "the idle days were not counted")
	_expect(int(idle["costs"]) > 0, "three days of two wages cost nothing")
	# Nobody on the bench: rent still runs, but nothing else does.
	var alone := Catalog.reckon(entry, 10, 0, 3)
	_expect_equal(int(alone["units"]), 0, "a bench nobody stands at produced work")
	_expect(
		int(alone["costs"]) < int(idle["costs"]),
		"keeping nobody on costs as much as keeping two"
	)


func _test_it_survives_a_save() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	var entry := _entry()
	if entry.is_empty():
		return
	session.run_state.money = int(entry["price_ard"]) + 900
	adapter.open_business(BENCH)
	adapter.restock_business(5)
	var restored = session.clone()
	_expect(restored != null, "a session owning a bench failed to clone")
	if restored == null:
		return
	_expect_equal(String(restored.business_state.business_id), BENCH, "the bench was lost on reload")
	_expect_equal(int(restored.business_state.stock), 5, "the material was lost on reload")

	var saved: Dictionary = session.to_dict()
	saved.erase("business_state")
	var older = session.get_script().from_dict(saved)
	_expect(older != null, "a save written before benches existed no longer opens")
	if older != null:
		_expect(
			not older.business_state.owns_anything(),
			"migration gave a bench to someone who never bought one"
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 BUSINESS TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 BUSINESS: %s" % failure)
	quit(1)
