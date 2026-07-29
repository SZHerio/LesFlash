class_name WeekActionService
extends RefCounted

## Pure location-first read models for the 21-action free-week catalog.

const CatalogScript := preload("res://game/sandbox/sandbox_action_catalog.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")


static func actions(session: Object, include_blocked: bool = false) -> Array[Dictionary]:
	if session == null or not _has_property(session, "run_state"):
		return []
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return []
	var result: Array[Dictionary] = []
	for definition: Dictionary in CatalogScript.actions_for_location(
		loaded["catalog"],
		_location_id(session)
	):
		var evaluation := evaluate(session.get("run_state"), definition)
		if bool(evaluation.get("available", false)) or include_blocked:
			result.append(_model(definition, evaluation))
	return result


static func definition(action_id: String) -> Dictionary:
	var loaded := CatalogScript.load_default()
	return CatalogScript.find_action(loaded.get("catalog", {}), action_id) if bool(loaded.get("ok", false)) else {}


static func evaluate(run_state: RunState, definition: Dictionary) -> Dictionary:
	var reasons: Array[Dictionary] = []
	if run_state == null:
		return {"available": false, "reasons": [{"code": "missing_state", "message": "Состояние героя недоступно"}]}
	for raw: Variant in Array(definition.get("requirements", [])):
		if not raw is Dictionary:
			continue
		var requirement: Dictionary = raw
		var passed := _requirement_passed(run_state, requirement)
		if not passed:
			reasons.append({
				"code": String(requirement.get("type", "requirement")),
				"message": String(requirement.get("blocked_reason", "Условие не выполнено")),
			})
	return {"available": reasons.is_empty(), "reasons": reasons}


static func _requirement_passed(run_state: RunState, requirement: Dictionary) -> bool:
	match String(requirement.get("type", "")):
		"characteristic_min":
			return run_state.get_characteristic(String(requirement.get("characteristic_id", ""))) >= int(requirement.get("value", 0))
		"meter_min":
			return run_state.get_meter(String(requirement.get("meter_id", ""))) >= int(requirement.get("value", 0))
		"meter_max":
			return run_state.get_meter(String(requirement.get("meter_id", ""))) <= int(requirement.get("value", 0))
		"inventory_item_min":
			return InventoryStateScript.item_count(run_state.inventory, String(requirement.get("item_id", ""))) >= int(requirement.get("quantity", 0))
		"season":
			return Season.of_calendar(run_state.calendar) in Array(requirement.get("season_ids", []))
		"time_window":
			var minute := run_state.calendar.minute_of_day
			var start := int(requirement.get("start_minute", 0))
			var finish := int(requirement.get("end_minute", 1440))
			return minute >= start and minute < finish if start <= finish else minute >= start or minute < finish
	return false


static func _model(definition: Dictionary, evaluation: Dictionary) -> Dictionary:
	var intent: Dictionary = Dictionary(definition.get("intent", {})).duplicate(true)
	var duration: Dictionary = Dictionary(definition.get("duration", {}))
	var minutes := int(duration.get("minutes", 0))
	var result := {
		"id": String(definition.get("action_id", "")),
		"kind": _ui_kind(String(intent.get("type", ""))),
		"category_id": String(definition.get("category_id", "observe")),
		"category_icon_id": String(definition.get("icon_id", "")),
		"title": String(definition.get("title", "")),
		"description": String(definition.get("description", "")),
		"available": bool(evaluation.get("available", false)),
		"reasons": Array(evaluation.get("reasons", [])).duplicate(true),
		"intent": intent,
		"confirmation_required": String(definition.get("confirmation", "none")) == "required",
		"minutes": minutes,
		"duration_minutes": minutes,
		"risk": "нет",
		"meta_tokens": [],
	}
	if minutes > 0:
		result["meta_tokens"] = [{"icon_id": &"meta_time", "text": "%d мин" % minutes, "accessible_text": "%d минут" % minutes}]
	return result


static func _ui_kind(intent_type: String) -> String:
	return {
		"enter_search": "search",
		"open_store": "store",
		"open_shelter": "shelter",
		"open_job": "job",
		"open_recycling_sale": "recycling",
	}.get(intent_type, "local")


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
