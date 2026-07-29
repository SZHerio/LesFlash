class_name TopicSessionCommand
extends RefCounted

## Заговорить с человеком о чём-нибудь.
##
## Разговор — обычное занятие: он занимает время суток и стоит рядом со сменой,
## а не живёт в отдельном режиме. Поэтому он и подтверждается как всё остальное,
## одной атомарной командой.
##
## Правило 3.4 здесь работает в полную силу: тема, которую герой не может
## поднять, не показывается вовсе, и он не узнаёт, что она была.

const CatalogScript := preload("res://game/topics/topic_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")

## Сколько занимает разговор. Не мгновение — иначе им можно заполнить весь день
## и ничего не потерять.
const MINUTES := 20


## О чём герой может заговорить с этим человеком прямо сейчас.
static func available(session: Object, npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if session == null:
		return result
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var run_state: RunState = session.get("run_state")
	for entry: Dictionary in CatalogScript.topics_for(Dictionary(loaded["catalog"]), npc_id):
		if not CatalogScript.is_open(entry, run_state):
			continue
		result.append({
			"id": String(entry.get("id", "")),
			"title": String(entry.get("title", "")),
			"prompt": String(entry.get("prompt", "")),
			"minutes": MINUTES,
		})
	return result


## Поднимает тему и возвращает то, что человек ответил. Ответ приходит из
## команды, а не из каталога напрямую: экран не должен знать, где он лежит.
static func raise_topic(
	target: Object,
	npc_id: String,
	topic_id: String,
	command_id: String
) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Разговор должен иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("invalid_catalog", "Список тем недоступен")
	var entry := CatalogScript.find(Dictionary(loaded["catalog"]), topic_id)
	if entry.is_empty():
		return _failure("unknown_topic", "Такой темы нет")
	var opinions: Dictionary = Dictionary(entry.get("opinions", {}))
	if not opinions.has(npc_id):
		return _failure("not_his_subject", "Ему нечего об этом сказать")
	var run_state: RunState = target.get("run_state")
	if not CatalogScript.is_open(entry, run_state):
		return _failure("topic_closed", "Об этом вы заговорить не можете")

	var opinion: Dictionary = opinions[npc_id]
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить разговор")
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "topic:%s:%s" % [npc_id, topic_id],
		"title": String(entry.get("title", "")),
		"journal_message": "Разговор: %s" % String(entry.get("title", "")),
		"journal_payload": {"npc_id": npc_id, "topic_id": topic_id},
		"conditions": [],
		"effects": [{
			"type": "advance_time",
			"minutes": MINUTES,
			"reason": "Разговор",
		}],
	})
	if not bool(committed.get("ok", false)):
		return committed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила разговор")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"stance": String(opinion.get("stance", "")),
		"line": String(opinion.get("line", "")),
		"transaction": committed,
	}


static func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
