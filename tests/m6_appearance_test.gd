extends SceneTree

## Контент, стадия 2: как героя читают, не спрашивая.
##
## Проверяется не то, что полоса вычисляется. Проверяется, что вид **портится
## сам** — единственная ось, которую нельзя купить один раз, — что он на
## что-то влияет, и что за него не заперто ничего необходимого.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const Appearance = preload("res://game/appearance/appearance_rules.gd")
const ActionCatalog = preload("res://game/sandbox/sandbox_action_catalog.gd")
const RunStateScript = preload("res://core/state/run_state.gd")

## Ровно восемнадцать очков, иначе песочница не стартует и всё ниже проходит,
## ни разу не выполнившись.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_the_scale_is_described()
	_test_a_week_without_washing_shows()
	_test_washing_is_recorded_and_helps()
	_test_clothes_are_read()
	_test_appearance_gates_something()
	_test_nothing_necessary_hides_behind_appearance()
	_test_an_older_save_starts_clean()
	_finish()


func _adapter(location_id: String) -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("песочница не стартовала — все проверки ниже пропущены")
		return null
	var session = adapter.get("_session")
	session.location = location_id
	if "base_location" in session:
		session.base_location = location_id
	session.phase = "map"
	return adapter


func _test_the_scale_is_described() -> void:
	var validation := Appearance.validate()
	_expect(
		bool(validation.get("ok", false)),
		"шкала вида не сходится: %s" % str(validation.get("errors", []))
	)
	_expect(
		Appearance.at_least(Appearance.RESPECTABLE, Appearance.ROUGH),
		"«прилично» оказалось хуже «обношенного»"
	)
	_expect(
		not Appearance.at_least(Appearance.DERELICT, Appearance.ORDINARY),
		"«как есть» прошло за «обыкновенного»"
	)


## То, ради чего вид вообще отдельная ось: он портится сам.
func _test_a_week_without_washing_shows() -> void:
	var run_state: RunState = RunStateScript.new(BUILD, 4242)
	var fresh := Appearance.score_of(run_state)
	run_state.calendar.advance_minutes(Appearance.NOTICEABLE_DAYS * 1440)
	var noticed := Appearance.score_of(run_state)
	run_state.calendar.advance_minutes(Appearance.UNMISTAKABLE_DAYS * 1440)
	var unmistakable := Appearance.score_of(run_state)
	_expect(noticed < fresh, "три дня без мытья ничего не изменили")
	_expect(unmistakable < noticed, "полторы недели не хуже трёх дней")


func _test_washing_is_recorded_and_helps() -> void:
	var adapter: SandboxSessionAdapter = _adapter("clinic_yard")
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.calendar.advance_minutes(Appearance.UNMISTAKABLE_DAYS * 1440)
	session.survival_state.processed_elapsed_minutes = int(session.run_state.calendar.elapsed_minutes)
	var before := Appearance.score_of(session.run_state)
	_expect(
		session.run_state.days_unwashed() >= Appearance.UNMISTAKABLE_DAYS,
		"счёт дней без мытья не идёт"
	)
	var washed: Dictionary = adapter.perform_location_action("action_clinic_wash_properly")
	_expect(bool(washed.get("ok", false)), "вымыться не вышло: %s" % str(washed))
	if not bool(washed.get("ok", false)):
		return
	_expect_equal(session.run_state.days_unwashed(), 0, "мытьё не записалось")
	_expect(
		Appearance.score_of(session.run_state) > before,
		"вымылся, и это ничего не изменило"
	)


func _test_clothes_are_read() -> void:
	var run_state: RunState = RunStateScript.new(BUILD, 4242)
	var bare := Appearance.score_of(run_state)
	var with_roof := Appearance.score_of(run_state, true)
	_expect(with_roof > bare, "крыша над головой никак не читается")


## Вид должен на что-то влиять, иначе он украшение.
func _test_appearance_gates_something() -> void:
	var loaded := ActionCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		_failures.append("каталог действий не грузится")
		return
	var gated := 0
	for raw_action: Variant in Array(Dictionary(loaded["catalog"]).get("actions", [])):
		for raw_requirement: Variant in Array(Dictionary(raw_action).get("requirements", [])):
			if String(Dictionary(raw_requirement).get("type", "")) == "appearance_min":
				gated += 1
	_expect(gated > 0, "вид не закрывает ничего и потому ничего не значит")

	# И это должно быть видно в игре, а не только в файле.
	var adapter: SandboxSessionAdapter = _adapter("station_square")
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.calendar.advance_minutes(Appearance.UNMISTAKABLE_DAYS * 1440)
	session.survival_state.processed_elapsed_minutes = int(session.run_state.calendar.elapsed_minutes)
	_expect(
		not _offers(adapter, "action_station_waiting_hall"),
		"в зал ожидания пустили того, на кого оглядываются"
	)
	session.run_state.record_wash()
	_expect(
		not _offers(adapter, "action_station_waiting_hall"),
		"чистого, но в том же тряпье, приняли за пассажира"
	)
	# Вымыться мало: в зал пускают тех, кто похож на пассажира, а это ещё и одежда,
	# и одной вещи не хватает — «обыкновенный» это две из трёх.
	#
	# Куртка не влезает в карманы, её несут в руках. Первая попытка молча не
	# клала её никуда, и тест сообщал, что вид не читается.
	for item_id: String in ["warm_jacket", "sturdy_boots"]:
		_expect(session.run_state.add_item(item_id, 1, "hands"), "%s некуда деть" % item_id)
		var stack_id := _stack_of(adapter, item_id)
		if stack_id != "":
			adapter.perform_inventory_action(stack_id, "equip")
	_expect(
		_offers(adapter, "action_station_waiting_hall"),
		"вымылся, оделся — и всё равно не пускают"
	)


## `CONTENT_PRINCIPLES.md`: ничто необходимое не прячется за возможностью. Вид
## портится сам, поэтому за ним особенно опасно запирать еду и ночлег.
func _test_nothing_necessary_hides_behind_appearance() -> void:
	var loaded := ActionCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return
	var gated: Dictionary = {}
	var total: Dictionary = {}
	for raw_action: Variant in Array(Dictionary(loaded["catalog"]).get("actions", [])):
		var action: Dictionary = raw_action
		var category := String(action.get("category_id", ""))
		total[category] = int(total.get(category, 0)) + 1
		for raw_requirement: Variant in Array(action.get("requirements", [])):
			if String(Dictionary(raw_requirement).get("type", "")) == "appearance_min":
				gated[category] = int(gated.get(category, 0)) + 1
	for category: String in ["food", "shelter", "work"]:
		if not total.has(category):
			continue
		_expect(
			int(gated.get(category, 0)) < int(total[category]),
			"всё, что относится к %s, заперто за внешним видом" % category
		)


func _test_an_older_save_starts_clean() -> void:
	var run_state: RunState = RunStateScript.new(BUILD, 4242)
	var saved: Dictionary = run_state.to_dict()
	saved.erase("washed_at_minute")
	saved["save_version"] = GameRules.RUN_STATE_VERSION_V6
	var restored: RunState = RunStateScript.from_dict(saved)
	_expect(restored != null, "сохранение шестой версии перестало открываться")
	if restored != null:
		_expect_equal(
			restored.days_unwashed(),
			0,
			"старое сохранение открылось грязным, хотя об этом ничего не записано"
		)


func _stack_of(adapter: Object, item_id: String) -> String:
	var inventory: Dictionary = Dictionary(adapter.get_inventory_model()).get("inventory", {})
	var containers: Variant = inventory.get("containers", {})
	var groups: Array = []
	if containers is Array:
		groups = containers
	elif containers is Dictionary:
		for key: Variant in Dictionary(containers):
			groups.append(Dictionary(containers)[key])
	for raw_container: Variant in groups:
		if not raw_container is Dictionary:
			continue
		for raw_stack: Variant in Array(Dictionary(raw_container).get("stacks", [])):
			if String(Dictionary(raw_stack).get("item_id", "")) == item_id:
				return String(Dictionary(raw_stack).get("stack_id", ""))
	return ""


func _offers(adapter: Object, action_id: String) -> bool:
	for raw_action: Variant in Array(Dictionary(adapter.get_location_model()).get("actions", [])):
		var action: Dictionary = raw_action
		if String(action.get("id", "")) == action_id and bool(action.get("available", false)):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (ожидалось=%s, получено=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M6 APPEARANCE TESTS PASSED: 7/7")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M6 APPEARANCE: %s" % failure)
	quit(1)
