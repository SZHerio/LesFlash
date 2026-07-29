class_name WeekActionCommand
extends RefCounted

## Executes confirmed week actions through the common atomic session boundary.

const ActionService := preload("res://game/week/week_action_service.gd")
const ActivityCatalog := preload("res://game/week/week_activity_catalog.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const WorldCatalogScript := preload("res://game/content/catalogs/world_definition_catalog.gd")
const SkillCatalogScript := preload("res://game/skills/skill_catalog.gd")


static func execute(target: Object, action_id: String, command_id: String) -> Dictionary:
	if target == null or not target.has_method("clone") or not target.has_method("replace_from"):
		return _failure("invalid_session", "Игровая сессия не поддерживает действия недели")
	var definition := ActionService.definition(action_id)
	if definition.is_empty() or String(definition.get("location_id", "")) != _location_id(target):
		return _failure("unknown_action", "Действие недоступно в этом месте")
	var evaluation := ActionService.evaluate(target.get("run_state"), definition)
	if not bool(evaluation.get("available", false)):
		return _failure("blocked", "Условия действия не выполнены", {"blocked_reasons": evaluation.get("reasons", [])})
	var intent: Dictionary = definition.get("intent", {})
	var intent_type := String(intent.get("type", ""))
	if intent_type in ["enter_search", "open_store", "open_shelter", "open_job", "open_recycling_sale"]:
		return {
			"ok": true, "code": "navigation", "error": "", "action_id": action_id,
			"intent": intent.duplicate(true), "mutated": false,
		}
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Действие должно иметь идентификатор команды")
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить действие")
	var effects_result := _effects(candidate, definition, intent_type)
	if not bool(effects_result.get("ok", false)):
		return effects_result
	_teach(effects_result, action_id)
	var world_loaded := WorldCatalogScript.load_default()
	if not bool(world_loaded.get("ok", false)):
		return _failure("world_catalog_failed", "Каталог состояния мира недоступен")
	var transaction := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": action_id,
		"title": String(definition.get("title", action_id)),
		"journal_message": String(definition.get("title", action_id)),
		"journal_payload": Dictionary(effects_result.get("journal_payload", {})).duplicate(true),
		"conditions": [],
		"effects": Array(effects_result.get("effects", [])).duplicate(true),
	}, {"world_definitions": Dictionary(world_loaded.get("catalog", {})).duplicate(true)})
	if not bool(transaction.get("ok", false)):
		return transaction
	if intent_type == "travel":
		var payload: Dictionary = intent.get("payload", {})
		if not _set_location(candidate, String(payload.get("destination_location_id", ""))):
			return _failure("travel_failed", "Не удалось изменить текущее место")
	if not bool(candidate.call("validate").get("ok", false)) or not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила действие")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"message": String(definition.get("outcome", "Действие выполнено")),
		"outcome": String(definition.get("outcome", "Действие выполнено")),
		"action_id": action_id,
		"intent": intent.duplicate(true),
		"mutated": true,
		"transaction": transaction,
		"lifecycle": target.get("survival_state").to_dict(),
	}


## Doing something in a place is one of the ways a skill grows, and until the
## skill catalog existed it was not one of them: only a work shift taught
## anything, which is why six of seven skills could never leave rank zero. The
## catalog decides — this only asks it.
static func _teach(effects_result: Dictionary, action_id: String) -> void:
	var loaded := SkillCatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return
	var skill_id := SkillCatalogScript.skill_taught_by(Dictionary(loaded["catalog"]), action_id)
	if skill_id.is_empty():
		return
	var effects: Array = Array(effects_result.get("effects", []))
	effects.append({"type": "practice_skill", "id": skill_id, "source_id": action_id})
	effects_result["effects"] = effects


static func _effects(candidate: Object, definition: Dictionary, intent_type: String) -> Dictionary:
	var intent: Dictionary = definition.get("intent", {})
	var payload: Dictionary = intent.get("payload", {})
	var minutes := int(Dictionary(definition.get("duration", {})).get("minutes", 0))
	match intent_type:
		"inspect":
			return {
				"ok": true,
				"effects": [{"type": "knowledge", "id": String(payload.get("knowledge_id", "")), "amount": 1, "mode": "unlock"}],
				"journal_payload": {"knowledge_id": String(payload.get("knowledge_id", ""))},
			}
		"perform_activity":
			var loaded := ActivityCatalog.load_default()
			var profile := ActivityCatalog.find(loaded.get("catalog", {}), String(payload.get("activity_id", ""))) if bool(loaded.get("ok", false)) else {}
			if profile.is_empty():
				return _failure("activity_missing", "Профиль занятия не найден")
			var effects: Array = [{"type": "advance_time", "minutes": minutes, "reason": String(definition.get("title", "Занятие"))}]
			effects.append_array(Array(profile.get("effects", [])).duplicate(true))
			return {"ok": true, "effects": effects, "journal_payload": {"activity_id": String(payload.get("activity_id", ""))}}
		"consume_item":
			return _consume_effects(candidate, definition, payload, minutes)
		"travel":
			return {
				"ok": true,
				"effects": [{"type": "advance_time", "minutes": minutes, "reason": "Путь пешком"}],
				"journal_payload": payload.duplicate(true),
			}
	return _failure("unsupported_intent", "Действие пока не поддерживается")


static func _consume_effects(candidate: Object, definition: Dictionary, payload: Dictionary, minutes: int) -> Dictionary:
	var state: RunState = candidate.get("run_state")
	var item_id := String(payload.get("item_id", ""))
	var quantity := int(payload.get("quantity", 1))
	var removal := InventoryStateScript.remove_item(state.inventory, item_id, quantity)
	if not bool(removal.get("ok", false)):
		return _failure("missing_food", "Еда больше не находится в вещах")
	state.inventory = Dictionary(removal["inventory"]).duplicate(true)
	var item_action: Dictionary = ItemCatalogScript.definition(item_id).action("use")
	var effects: Array = [{"type": "advance_time", "minutes": minutes, "reason": String(definition.get("title", "Приём пищи"))}]
	for raw_effect: Variant in Array(item_action.get("effects", [])):
		effects.append(Dictionary(raw_effect).duplicate(true))
	return {"ok": true, "effects": effects, "journal_payload": {"item_id": item_id, "quantity": quantity}}


static func _set_location(session: Object, location_id: String) -> bool:
	if location_id.is_empty():
		return false
	if session.has_method("set_base_location"):
		return bool(session.call("set_base_location", location_id))
	for raw_property: Variant in session.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == "location":
			session.set("location", location_id)
			if _has_property(session, "phase"):
				session.set("phase", "map")
			return true
	return false


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		if _has_property(session, field):
			return String(session.get(field))
	return ""


static func _has_property(value: Object, name: String) -> bool:
	for raw_property: Variant in value.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == name:
			return true
	return false


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(extra, true)
	return result
