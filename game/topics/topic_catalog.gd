class_name TopicCatalog
extends RefCounted

## О чём можно заговорить, и кто вообще станет об этом говорить.
##
## Дерево реплик пишется под одного человека и умирает вместе с ним: чтобы дать
## новому НПС собственную манеру, нужно написать ему дерево целиком. Тема живёт
## иначе — её можно поднять с любым, у кого есть об этом мнение, а мнение зависит
## от того, кто он.
##
## Отсюда правило, ради которого этот каталог и существует: **у каждой темы
## должен быть кто-то, кому она безразлична**. Тема, о которой у всех есть
## мнение, — не тема, а кнопка, и разговор снова становится списком действий.
##
## Сцены (свидание, ссора, прощание) остаются деревом и живут отдельно: у сцены
## есть начало и конец, у темы — нет.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "topic_catalog_v1"
const DEFAULT_PATH := "res://game/topics/data/topic_catalog_v1.json"

## Все, с кем можно заговорить. Тема, называющая кого-то ещё, — обещание,
## которого игра не выполнит.
const KNOWN_NPC_IDS := [
	"npc_viktor_koren", "npc_lidia_maren", "npc_tamara_roven", "npc_stepan_gulev",
]

## Чем тема может быть открыта. Ничего сверх этого списка: возможность, которую
## нельзя проверить, — это тема, которая не откроется никогда.
const GATE_KINDS := ["characteristic", "knowledge", "qualification", "appearance", "skill"]

## Как человек относится к теме. `indifferent` — не «нет реплики», а ответ:
## пожал плечами и заговорил о другом.
const STANCES := ["eager", "willing", "guarded", "indifferent"]


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var entries := Rules.index_entries(catalog.get("topics", null), "topics", "topic_", errors)
	var opinionated: Dictionary = {}
	for topic_id: String in entries:
		var entry: Dictionary = entries[topic_id]
		var path := "topics.%s" % topic_id
		for field: String in ["title", "prompt"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		_validate_gate(entry.get("gate", null), path, errors)
		_validate_opinions(entry, path, errors)
		for raw_npc: Variant in Dictionary(entry.get("opinions", {})):
			opinionated[String(raw_npc)] = true
	# Человек, у которого нет мнения ни об одной теме, молчалив не по замыслу, а
	# по недосмотру: с ним не о чем заговорить вообще.
	for npc_id: String in KNOWN_NPC_IDS:
		if not opinionated.has(npc_id):
			errors.append("%s не имеет мнения ни об одной теме — с ним не о чем говорить" % npc_id)
	return {"ok": errors.is_empty(), "errors": errors}


## Чем тема открыта. Пусто — значит открыта всем, и это законно: без таких тем
## сборка без обаяния осталась бы вовсе без разговоров.
static func _validate_gate(value: Variant, path: String, errors: Array[String]) -> void:
	if value == null:
		return
	if not value is Dictionary:
		errors.append("%s.gate должен быть объектом" % path)
		return
	var gate: Dictionary = value
	if String(gate.get("kind", "")) not in GATE_KINDS:
		errors.append("%s.gate.kind неизвестен" % path)
	if String(gate.get("id", "")).strip_edges().is_empty():
		errors.append("%s.gate.id не задан" % path)
	var value_field: Variant = gate.get("value", 1)
	if typeof(value_field) != TYPE_INT or int(value_field) < 1:
		errors.append("%s.gate.value должен быть целым не меньше единицы" % path)


## Мнения по людям — и то самое правило про равнодушного.
static func _validate_opinions(entry: Dictionary, path: String, errors: Array[String]) -> void:
	var raw: Variant = entry.get("opinions", null)
	if not raw is Dictionary or Dictionary(raw).is_empty():
		errors.append("%s.opinions должен называть хотя бы одного человека" % path)
		return
	var opinions: Dictionary = raw
	var indifferent := false
	for raw_npc: Variant in opinions:
		var npc_id := String(raw_npc)
		var opinion_path := "%s.opinions.%s" % [path, npc_id]
		if npc_id not in KNOWN_NPC_IDS:
			errors.append("%s: такого человека нет" % opinion_path)
			continue
		if not opinions[raw_npc] is Dictionary:
			errors.append("%s должен быть объектом" % opinion_path)
			continue
		var opinion: Dictionary = opinions[raw_npc]
		var stance := String(opinion.get("stance", ""))
		if stance not in STANCES:
			errors.append("%s.stance неизвестен" % opinion_path)
		if stance == "indifferent":
			indifferent = true
		Rules.validate_text(opinion.get("line", null), "%s.line" % opinion_path, errors)
	if not indifferent:
		errors.append(
			"%s: об этом говорят все — тема без равнодушного это не тема, а кнопка" % path
		)


static func find(catalog: Dictionary, topic_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("topics", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == topic_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


## О чём этот человек вообще говорит, вместе с тем, как он к этому относится.
static func topics_for(catalog: Dictionary, npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry: Variant in Array(catalog.get("topics", [])):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var opinions: Dictionary = Dictionary(entry.get("opinions", {}))
		if not opinions.has(npc_id):
			continue
		var opinion: Dictionary = opinions[npc_id]
		result.append({
			"id": String(entry.get("id", "")),
			"title": String(entry.get("title", "")),
			"prompt": String(entry.get("prompt", "")),
			"gate": Dictionary(entry.get("gate", {})).duplicate(true),
			"stance": String(opinion.get("stance", "")),
			"line": String(opinion.get("line", "")),
		})
	return result


## Может ли герой сейчас поднять эту тему. Правило 3.4: если не может — тему
## ему не показывают, и он не узнаёт, что она была.
static func is_open(entry: Dictionary, run_state: RunState) -> bool:
	var gate: Dictionary = Dictionary(entry.get("gate", {}))
	if gate.is_empty() or run_state == null:
		return true
	var id := String(gate.get("id", ""))
	var need := int(gate.get("value", 1))
	match String(gate.get("kind", "")):
		"characteristic":
			return run_state.get_characteristic(id) >= need
		"knowledge":
			return run_state.has_knowledge(id)
		"qualification":
			return run_state.holds_qualification(id)
		"skill":
			return run_state.get_skill_rank(id) >= need
		"appearance":
			return AppearanceRules.at_least(AppearanceRules.band_of(run_state), id)
	return false
