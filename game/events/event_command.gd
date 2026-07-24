class_name ContextualEventCommand
extends RefCounted

const Director := preload("res://game/events/event_director.gd")
const Transaction := preload("res://core/rules/action_transaction.gd")


static func execute(
	run_state: RunState,
	catalog: Dictionary,
	card_id: String,
	option_id: String,
	context: Dictionary
) -> Dictionary:
	if run_state == null:
		return _failure("missing_state", "Состояние попытки отсутствует")
	var preview := Director.preview(catalog, card_id, context)
	if not bool(preview.get("ok", false)):
		return _failure("unknown_card", "Карточка события не найдена")
	var option := _find_option(preview, option_id)
	if option.is_empty():
		return _failure("unknown_option", "Вариант ответа не найден")
	if not bool(option.get("available", false)):
		return {
			"ok": false,
			"code": "option_blocked",
			"error": "Этот вариант сейчас недоступен",
			"blocked_reasons": Array(option.get("blocked_reasons", [])).duplicate(true),
		}
	var card := _find_card(catalog, card_id)
	var action := {
		"id": "context_event:%s" % card_id,
		"option_id": option_id,
		"title": String(card.get("title", card_id)),
		"option_title": String(option.get("label", option_id)),
		"journal_message": "%s — %s" % [
			String(card.get("title", card_id)),
			String(option.get("label", option_id)),
		],
		"journal_payload": {
			"event_id": card_id,
			"event_tone": String(card.get("tone", "neutral")),
			"source": Dictionary(context.get("source", {})).duplicate(true),
			"location_id": String(context.get("location_id", "")),
		},
		"conditions": [],
		"effects": Array(option.get("effects", [])).duplicate(true),
	}
	var result: ActionResult = Transaction.execute(
		run_state,
		action,
		{"event_id": card_id, "option_id": option_id}
	)
	if not result.success:
		var failure := result.to_dict()
		failure["ok"] = false
		failure["error"] = result.message
		return failure
	var elapsed := int(Dictionary(context.get("calendar", {})).get("elapsed_minutes", 0))
	return {
		"ok": true,
		"code": "ok",
		"card_id": card_id,
		"option_id": option_id,
		"outcome": String(option.get("outcome", "")),
		"history_fact": "event:%s:%s" % [card_id, option_id],
		"cooldown_ready_at": elapsed + int(card.get("cooldown_minutes", 0)),
		"transaction": result.to_dict(),
		"queued_consequences": _queued_consequences(result),
	}


static func _find_option(preview: Dictionary, option_id: String) -> Dictionary:
	for raw_option: Variant in Array(preview.get("options", [])):
		if raw_option is Dictionary and String(raw_option.get("id", "")) == option_id:
			return Dictionary(raw_option).duplicate(true)
	return {}


static func _find_card(catalog: Dictionary, card_id: String) -> Dictionary:
	for raw_card: Variant in Array(catalog.get("cards", [])):
		if raw_card is Dictionary and String(raw_card.get("id", "")) == card_id:
			return Dictionary(raw_card).duplicate(true)
	return {}


static func _queued_consequences(result: ActionResult) -> Array:
	var queued: Array = []
	for raw_change: Variant in result.changes:
		if not raw_change is Dictionary:
			continue
		var change: Dictionary = raw_change
		if String(change.get("effect_type", "")) == "deferred":
			queued.append(change.duplicate(true))
	return queued


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
