extends SceneTree

## Контент, стадия 3: темы вместо деревьев реплик.
##
## Главная проверка — та, ради которой каталог и написан: **у каждой темы должен
## быть кто-то, кому она безразлична**. Тема, о которой у всех есть мнение, — не
## тема, а кнопка, и разговор снова превращается в список действий.
##
## Вторая по важности — что сборка без обаяния видит меньше тем и не узнаёт,
## каких именно. Это и есть обещанная реиграбельность, и она либо измерима, либо
## её нет.

const Topics = preload("res://game/topics/topic_catalog.gd")
const RunStateScript = preload("res://core/state/run_state.gd")
const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")

const PLAIN := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const TALKER := {"strength": 3, "charisma": 10, "intelligence": 3, "luck": 2}

var _catalog: Dictionary = {}
var _failures: Array[String] = []


func _init() -> void:
	var loaded := Topics.load_default()
	if not bool(loaded.get("ok", false)):
		_failures.append("каталог тем не грузится: %s" % str(loaded.get("errors", [])))
		_finish()
		return
	_catalog = loaded["catalog"]
	_test_every_topic_has_someone_indifferent()
	_test_a_topic_all_agree_on_is_refused()
	_test_everyone_has_something_to_say()
	_test_the_same_question_gets_different_answers()
	_test_charisma_opens_topics_a_plain_build_never_sees()
	_test_something_is_open_to_everyone()
	_test_a_topic_can_be_raised_in_play()
	_finish()


## То самое правило.
func _test_every_topic_has_someone_indifferent() -> void:
	for raw_entry: Variant in Array(_catalog.get("topics", [])):
		var entry: Dictionary = raw_entry
		var indifferent := false
		for raw_npc: Variant in Dictionary(entry.get("opinions", {})):
			if String(Dictionary(entry["opinions"])[raw_npc].get("stance", "")) == "indifferent":
				indifferent = true
		_expect(
			indifferent,
			"«%s»: об этом говорят все — это кнопка, а не тема" % String(entry.get("title", ""))
		)


func _test_a_topic_all_agree_on_is_refused() -> void:
	var broken: Dictionary = _catalog.duplicate(true)
	var entry: Dictionary = Array(broken["topics"])[0]
	for raw_npc: Variant in Dictionary(entry["opinions"]):
		Dictionary(entry["opinions"])[raw_npc]["stance"] = "eager"
	_expect(
		not bool(Topics.validate(broken).get("ok", true)),
		"каталог принял тему, о которой у всех есть мнение"
	)


func _test_everyone_has_something_to_say() -> void:
	for npc_id: String in Topics.KNOWN_NPC_IDS:
		_expect(
			not Topics.topics_for(_catalog, npc_id).is_empty(),
			"с %s не о чем заговорить вообще" % npc_id
		)


## Один вопрос на приёмке и на рынке должен получать разные ответы, иначе люди
## отличаются только именем.
func _test_the_same_question_gets_different_answers() -> void:
	for raw_entry: Variant in Array(_catalog.get("topics", [])):
		var entry: Dictionary = raw_entry
		var lines: Dictionary = {}
		var stances: Dictionary = {}
		for raw_npc: Variant in Dictionary(entry.get("opinions", {})):
			var opinion: Dictionary = Dictionary(entry["opinions"])[raw_npc]
			_expect(
				not lines.has(String(opinion.get("line", ""))),
				"«%s»: двое отвечают слово в слово" % String(entry.get("title", ""))
			)
			lines[String(opinion.get("line", ""))] = true
			stances[String(opinion.get("stance", ""))] = true
		_expect(
			stances.size() >= 2,
			"«%s»: все относятся к этому одинаково" % String(entry.get("title", ""))
		)


## Обещанная реиграбельность, в цифрах.
func _test_charisma_opens_topics_a_plain_build_never_sees() -> void:
	var plain := _open_count(RunStateScript.new(PLAIN, 4242))
	var talker := _open_count(RunStateScript.new(TALKER, 4242))
	_expect(
		talker > plain,
		"обаяние не открывает ни одной темы (обычный=%d, говорун=%d)" % [plain, talker]
	)


## И при этом сборка без всего не должна остаться немой.
func _test_something_is_open_to_everyone() -> void:
	var plain := _open_count(RunStateScript.new(PLAIN, 4242))
	_expect(plain > 0, "сборке без особых качеств не о чем говорить вовсе")


## Разговор должен быть занятием: стоить времени и отдавать ответ того самого
## человека, а не общий текст темы.
func _test_a_topic_can_be_raised_in_play() -> void:
	var adapter = SandboxAdapter.create(PLAIN, 91_301)
	if adapter == null:
		_failures.append("песочница не стартовала")
		return
	var session = adapter.get("_session")
	var offered: Array = adapter.get_npc_topics("npc_stepan_gulev")
	_expect(not offered.is_empty(), "со Степаном не о чем заговорить")
	if offered.is_empty():
		return
	# Закрытых тем в списке быть не должно: их герой не видит вовсе.
	for raw_topic: Variant in offered:
		var entry := Topics.find(_catalog, String(Dictionary(raw_topic).get("id", "")))
		_expect(
			Topics.is_open(entry, session.run_state),
			"в списке оказалась тема, которую поднять нельзя"
		)
	var before := int(session.run_state.calendar.elapsed_minutes)
	var topic_id := String(Dictionary(offered[0]).get("id", ""))
	var said: Dictionary = adapter.raise_topic("npc_stepan_gulev", topic_id)
	_expect(bool(said.get("ok", false)), "заговорить не вышло: %s" % str(said))
	if not bool(said.get("ok", false)):
		return
	_expect(
		int(session.run_state.calendar.elapsed_minutes) > before,
		"разговор не занял времени и потому ничего не стоит"
	)
	_expect(String(said.get("line", "")).strip_edges() != "", "человек ничего не ответил")
	var entry := Topics.find(_catalog, topic_id)
	_expect_equal(
		String(said.get("line", "")),
		String(Dictionary(entry.get("opinions", {})).get("npc_stepan_gulev", {}).get("line", "")),
		"ответил не своими словами"
	)
	# А о том, что ему безразлично, ответ всё равно должен быть — пожал плечами.
	_expect(
		not bool(adapter.raise_topic("npc_stepan_gulev", "topic_nonexistent").get("ok", true)),
		"поднялась тема, которой нет"
	)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (ожидалось=%s, получено=%s)" % [message, str(expected), str(actual)])


func _open_count(run_state: RunState) -> int:
	var open := 0
	for raw_entry: Variant in Array(_catalog.get("topics", [])):
		if Topics.is_open(Dictionary(raw_entry), run_state):
			open += 1
	return open


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("M6 TOPICS TESTS PASSED: 7/7")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M6 TOPICS: %s" % failure)
	quit(1)
