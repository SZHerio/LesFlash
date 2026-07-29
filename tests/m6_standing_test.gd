extends SceneTree

## Контент, стадия 4: надёжность, опасность и слух.
##
## Две репутации, а не одна шкала морали. Главное, что здесь проверяется: их
## **нельзя растить одновременно**, слава **не забывается**, и слух доходит не
## мгновенно — иначе город знает всё обо всех, и знать нечего.

const Standing = preload("res://game/standing/standing_state.gd")
const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")

const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_the_two_cannot_grow_together()
	_test_nothing_is_forgotten()
	_test_a_rumour_takes_people_to_travel()
	_test_the_louder_one_is_what_he_is_called()
	_test_it_survives_a_save()
	_test_the_manner_of_a_search_is_recorded()
	_finish()


## То, ради чего это две оси, а не одна.
func _test_the_two_cannot_grow_together() -> void:
	var state := Standing.fresh()
	for _index: int in 10:
		state.record("reliable")
	var reliable_peak := state.reliable
	_expect(reliable_peak > 0, "надёжность не выросла")
	_expect_equal(state.feared, 0, "надёжные поступки нарастили страх")
	for _index: int in 5:
		state.record("feared")
	_expect(state.feared > 0, "опасность не выросла")
	_expect(
		state.reliable < reliable_peak,
		"опасные поступки не сбили надёжность — растут обе сразу"
	)
	_expect(not bool(state.record("saintly")), "принята несуществующая сторона")
	_expect(not bool(state.record("reliable", 0)), "принят поступок, который ничего не значит")


## Бумагу можно получить заново, славу — нет.
func _test_nothing_is_forgotten() -> void:
	var state := Standing.fresh()
	for _index: int in 12:
		state.record("feared")
	_expect(state.is_known_for("feared"), "двенадцать поступков не сделали его известным")
	# Даже стараясь, он не обнуляет то, что о нём знают.
	for _index: int in 30:
		state.record("reliable")
	_expect(
		state.feared > 0 or state.reliable > 0,
		"репутация обнулилась целиком — славу забыли"
	)
	_expect(state.is_known_for("reliable"), "тридцать надёжных поступков ничего не дали")


## Слух — это люди, а не мгновенное знание. Сделанное на паперти доходит до
## приёмки, когда там окажется кто-то, кто знает.
func _test_a_rumour_takes_people_to_travel() -> void:
	var state := Standing.fresh()
	state.record("feared", 4)
	_expect(not state.has_heard("npc_viktor_koren"), "о поступке узнали, ещё не услышав")
	_expect(state.spread_to("npc_viktor_koren"), "слух не дошёл ни до кого")
	_expect(state.has_heard("npc_viktor_koren"), "услышавший не запомнил")
	_expect(not state.spread_to("npc_viktor_koren"), "один и тот же услышал дважды")
	# Новый поступок — и всё заново: знают о прошлом, не о сегодняшнем.
	state.record("reliable")
	_expect(
		not state.has_heard("npc_viktor_koren"),
		"о новом поступке узнали все разом, без слуха"
	)


func _test_the_louder_one_is_what_he_is_called() -> void:
	var state := Standing.fresh()
	_expect_equal(state.label(), "", "о человеке без поступков уже что-то говорят")
	state.record("reliable", Standing.NOTICED)
	_expect_equal(state.label(), "reliable", "надёжного не считают надёжным")
	state.record("feared", Standing.NOTICED * 3)
	_expect_equal(state.label(), "feared", "опасного всё ещё считают надёжным")


func _test_it_survives_a_save() -> void:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("песочница не стартовала")
		return
	var session = adapter.get("_session")
	session.standing_state.record("feared", 5)
	session.standing_state.spread_to("npc_tamara_roven")
	var restored = session.clone()
	_expect(restored != null, "сессия с репутацией не клонируется")
	if restored != null:
		_expect_equal(restored.standing_state.feared, 5, "репутация потерялась при перезагрузке")
		_expect(restored.standing_state.has_heard("npc_tamara_roven"), "забылось, кто слышал")
	var saved: Dictionary = session.to_dict()
	saved.erase("standing_state")
	var older = session.get_script().from_dict(saved)
	_expect(older != null, "сохранение, написанное раньше, перестало открываться")
	if older != null:
		_expect_equal(older.standing_state.label(), "", "о старом герое придумали репутацию")


## Семя было посеяно в зонах поиска давно и ничего не копило.
func _test_the_manner_of_a_search_is_recorded() -> void:
	var source := FileAccess.get_file_as_string(
		"res://game/search/search_interaction_transaction.gd"
	)
	_expect(
		source.contains('"type": "standing"'),
		"способ обыска по-прежнему ничего не значит для репутации"
	)
	_expect(
		source.contains("ask_permission") and source.contains("force_hinge"),
		"попросить разрешения и отжать петлю считаются одинаково"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (ожидалось=%s, получено=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M6 STANDING TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M6 STANDING: %s" % failure)
	quit(1)
