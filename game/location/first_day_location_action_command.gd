class_name FirstDayLocationActionCommand
extends RefCounted

const ActionService := preload("res://game/location/location_action_service.gd")


static func execute(session: FirstDaySession, action_id: String) -> Dictionary:
	if session == null:
		return _failure("missing_session", "Игровая попытка отсутствует")
	if session.day_completed or session.phase != "map":
		return _failure("invalid_phase", "Сейчас нельзя выполнить действие места")

	var model := _find_model(ActionService.get_actions(
		session,
		session.location,
		{"include_blocked": true}
	), action_id)
	if model.is_empty():
		return _failure("unknown_action", "Действие не найдено в текущем месте")
	if not bool(model.get("available", false)):
		var blocked := _failure("blocked", "Условия действия не выполнены")
		blocked["blocked_reasons"] = Array(model.get("reasons", [])).duplicate(true)
		return blocked

	var definition: Dictionary = ActionService.definition_for(action_id)
	if definition.is_empty():
		return _failure("invalid_action", "Описание действия повреждено")
	var transaction := session.call(
		"_execute_action_with_due",
		definition,
		{
			"phase": session.phase,
			"location": session.location,
			"source": "location_action",
			"action_id": action_id,
		}
	) as ActionResult
	if transaction == null:
		return _failure("transaction_missing", "Действие не вернуло результат")
	if not transaction.success:
		return {
			"ok": false,
			"code": String(transaction.code),
			"message": transaction.message,
			"error": transaction.message,
			"outcome": "",
			"blocked_reasons": transaction.blocked_reasons.duplicate(true),
			"transaction": transaction.to_dict(),
		}
	session.call("_touch")
	return {
		"ok": true,
		"code": "ok",
		"message": String(definition.get("outcome", "Действие выполнено")),
		"outcome": String(definition.get("outcome", "Действие выполнено")),
		"action_id": action_id,
		"location_id": session.location,
		"duration_minutes": int(definition.get("duration_minutes", 0)),
		"transaction": transaction.to_dict(),
	}


static func _find_model(models: Array, action_id: String) -> Dictionary:
	for raw_model in models:
		if raw_model is Dictionary and String(raw_model.get("id", "")) == action_id:
			return Dictionary(raw_model)
	return {}


static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"error": message,
		"outcome": "",
		"blocked_reasons": [],
		"transaction": {},
	}
