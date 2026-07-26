class_name LocationActionService
extends RefCounted

## Pure read-models plus one explicit mutation boundary for ordinary actions.
## Reading never consumes time or RNG. A confirmed command is revalidated and
## committed through ActionTransaction, so effects and its journal entry are
## all-or-nothing.

const CatalogScript := preload("res://game/location/location_action_catalog.gd")
const SERVICE_SCRIPT_PATH := "res://game/location/location_action_service.gd"

var _catalog: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _ids_by_location: Dictionary = {}
var _errors: Array[String] = []


static func get_actions(
	session_or_run_state: Object,
	location_id: String,
	options: Dictionary = {}
	) -> Array[Dictionary]:
	var service: Variant = _new_default_service()
	if service == null:
		return []
	return service.read_models(_resolve_run_state(session_or_run_state), location_id, options)


static func execute(
		session_or_run_state: Object,
		location_id: String,
	action_id: String,
	context: Dictionary = {}
	) -> Dictionary:
	var service: Variant = _new_default_service()
	if service == null:
		return {
			"ok": false,
			"code": "service_unavailable",
			"message": "Сервис локальных действий недоступен",
			"outcome": "",
			"blocked_reasons": [],
			"transaction": {},
		}
	return service.perform(
		_resolve_run_state(session_or_run_state),
		location_id,
		action_id,
		context
	)


static func definition_for(action_id: String) -> Dictionary:
	var service: Variant = _new_default_service()
	return service.get_action_definition(action_id) if service != null else {}


static func category_icon_id(category_id: String) -> StringName:
	return CatalogScript.category_icon_id(category_id)


func _init(catalog: Dictionary = {}) -> void:
	var source := catalog.duplicate(true)
	if source.is_empty():
		var loaded := CatalogScript.load_default()
		if not bool(loaded.get("ok", false)):
			_errors = _string_array(loaded.get("errors", []))
			return
		source = Dictionary(loaded.get("catalog", {})).duplicate(true)
	var validation := CatalogScript.validate(source)
	if not bool(validation.get("ok", false)):
		_errors = _string_array(validation.get("errors", []))
		return
	_catalog = source
	_index_catalog()


func is_ready() -> bool:
	return _errors.is_empty() and not _definitions_by_id.is_empty()


func get_errors() -> Array[String]:
	return _errors.duplicate()


func get_schema_version() -> int:
	return int(_catalog.get("schema_version", 0))


func get_action_definition(action_id: String) -> Dictionary:
	var value: Variant = _definitions_by_id.get(action_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func read_models(
		run_state: Object,
		location_id: String,
		options: Dictionary = {}
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_ready() or run_state == null:
		return result
	var include_blocked := bool(options.get("include_blocked", false))
	var raw_ids: Variant = _ids_by_location.get(location_id, [])
	if not raw_ids is Array:
		return result
	for raw_id: Variant in raw_ids:
		var definition := get_action_definition(String(raw_id))
		var evaluation := _evaluate(run_state, definition)
		if not bool(evaluation.get("available", false)) and not include_blocked:
			continue
		result.append(_to_read_model(definition, evaluation))
	return result


func perform(
		run_state: Object,
		location_id: String,
		action_id: String,
		context: Dictionary = {}
	) -> Dictionary:
	if not is_ready():
		return _failure("catalog_unavailable", "Каталог локальных действий недоступен")
	if run_state == null:
		return _failure("missing_state", "Состояние игры отсутствует")
	var definition := get_action_definition(action_id)
	if definition.is_empty():
		return _failure("unknown_action", "Неизвестное действие: %s" % action_id)
	if String(definition.get("location_id", "")) != location_id:
		return _failure("wrong_location", "Это действие недоступно в текущем месте")
	var evaluation := _evaluate(run_state, definition)
	if not bool(evaluation.get("available", false)):
		var blocked := _failure("blocked", "Условия действия не выполнены")
		blocked["blocked_reasons"] = Array(evaluation.get("reasons", [])).duplicate(true)
		return blocked

	var transaction_context := context.duplicate(true)
	transaction_context["source"] = "location_action"
	transaction_context["location_id"] = location_id
	transaction_context["action_id"] = action_id
	var transaction := ActionTransaction.execute(run_state, definition, transaction_context)
	var transaction_data := transaction.to_dict()
	if not transaction.success:
		return {
			"ok": false,
			"code": String(transaction.code),
			"message": transaction.message,
			"outcome": "",
			"blocked_reasons": transaction.blocked_reasons.duplicate(true),
			"transaction": transaction_data,
			"action_id": action_id,
			"location_id": location_id,
		}
	return {
		"ok": true,
		"code": "ok",
		"message": String(definition.get("outcome", "Действие выполнено")),
		"outcome": String(definition.get("outcome", "Действие выполнено")),
		"blocked_reasons": [],
		"transaction": transaction_data,
		"action_id": action_id,
		"location_id": location_id,
		"duration_minutes": int(definition.get("duration_minutes", 0)),
	}


func _evaluate(run_state: Object, definition: Dictionary) -> Dictionary:
	var reasons: Array[Dictionary] = []
	var time_result := _evaluate_time(run_state, definition)
	if not bool(time_result.get("passed", false)):
		reasons.append(time_result)
	var raw_conditions: Variant = definition.get("conditions", [])
	var conditions: Array = raw_conditions if raw_conditions is Array else []
	var checks := CheckResolver.evaluate_all(run_state, conditions, {
		"location_id": String(definition.get("location_id", "")),
		"action_id": String(definition.get("id", "")),
	})
	for raw_reason: Variant in Array(checks.get("reasons", [])):
		if raw_reason is Dictionary:
			reasons.append(raw_reason.duplicate(true))
	return {
		"available": reasons.is_empty(),
		"reasons": reasons,
		"checks": Array(checks.get("checks", [])).duplicate(true),
	}


func _evaluate_time(run_state: Object, definition: Dictionary) -> Dictionary:
	var raw_windows: Variant = definition.get("time_windows", [])
	if not raw_windows is Array or raw_windows.is_empty():
		return {"passed": true, "code": "ok", "message": "Доступно в любое время"}
	var stamp := RuleStateAccess.time_snapshot(run_state)
	var minute := int(stamp.get("minute_of_day", -1))
	if minute < 0 or minute >= 1440:
		return {
			"passed": false,
			"code": "time_unavailable",
			"message": "Не удалось определить игровое время",
			"kind": "time",
		}
	for raw_window: Variant in raw_windows:
		if not raw_window is Dictionary:
			continue
		var start := int(raw_window.get("start_minute", 0))
		var end := int(raw_window.get("end_minute", 1440))
		var inside := minute >= start and minute < end
		if start > end:
			inside = minute >= start or minute < end
		if inside:
			return {"passed": true, "code": "ok", "message": "Время подходит"}
	return {
		"passed": false,
		"code": "time_window_closed",
		"message": "Сейчас действие недоступно. Время: %s" % _format_windows(raw_windows),
		"kind": "time",
		"actual": minute,
		"windows": raw_windows.duplicate(true),
	}


func _to_read_model(definition: Dictionary, evaluation: Dictionary) -> Dictionary:
	var category_id := String(definition.get("category_id", ""))
	return {
		"id": String(definition.get("id", "")),
		"kind": "local",
		"location_id": String(definition.get("location_id", "")),
		"category_id": category_id,
		"category_icon_id": String(category_icon_id(category_id)),
		"title": String(definition.get("title", "")),
		"description": String(definition.get("description", "")),
		"duration_minutes": int(definition.get("duration_minutes", 0)),
		"risk": String(definition.get("risk", "нет")),
		"meta_tokens": _meta_tokens(definition),
		"repeatable": bool(definition.get("repeatable", false)),
		"available": bool(evaluation.get("available", false)),
		"reasons": Array(evaluation.get("reasons", [])).duplicate(true),
		"outcome_preview": String(definition.get("outcome", "")),
	}


func _meta_tokens(definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var minutes := int(definition.get("duration_minutes", 0))
	if minutes > 0:
		var duration_text := "%d мин" % minutes
		result.append({
			"icon_id": &"meta_time",
			"text": duration_text,
			"accessible_text": duration_text,
		})
	var risk := String(definition.get("risk", "нет")).strip_edges().to_lower()
	var risk_text := "Без риска" if risk.is_empty() or risk == "нет" else "Риск: %s" % _sentence_case(risk)
	result.append({
		"icon_id": &"meta_risk",
		"text": risk_text,
		"accessible_text": risk_text,
	})
	return result


func _sentence_case(value: String) -> String:
	return value if value.is_empty() else value.left(1).to_upper() + value.substr(1)


func _index_catalog() -> void:
	for raw_action: Variant in Array(_catalog.get("actions", [])):
		if not raw_action is Dictionary:
			continue
		var definition: Dictionary = raw_action.duplicate(true)
		var action_id := String(definition.get("id", ""))
		var location_id := String(definition.get("location_id", ""))
		_definitions_by_id[action_id] = definition
		if not _ids_by_location.has(location_id):
			_ids_by_location[location_id] = []
		var ids: Array = _ids_by_location[location_id]
		ids.append(action_id)
		_ids_by_location[location_id] = ids


func _format_windows(windows: Array) -> String:
	var labels: PackedStringArray = []
	for raw_window: Variant in windows:
		if not raw_window is Dictionary:
			continue
		labels.append("%s–%s" % [
			_format_minute(int(raw_window.get("start_minute", 0))),
			_format_minute(int(raw_window.get("end_minute", 1440))),
		])
	return ", ".join(labels)


func _format_minute(minute: int) -> String:
	var normalized := minute
	if normalized == 1440:
		return "24:00"
	normalized = posmod(normalized, 1440)
	return "%02d:%02d" % [normalized / 60, normalized % 60]


func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"outcome": "",
		"blocked_reasons": [],
		"transaction": {},
	}


static func _resolve_run_state(session_or_run_state: Object) -> Object:
	if session_or_run_state == null:
		return null
	if RuleStateAccess.has_property(session_or_run_state, &"run_state"):
		var candidate: Variant = session_or_run_state.get(&"run_state")
		if candidate is Object:
			return candidate
	if session_or_run_state.has_method("clone") and session_or_run_state.has_method("to_dict"):
		return session_or_run_state
	return session_or_run_state


static func _new_default_service() -> Variant:
	var service_script: Variant = load(SERVICE_SCRIPT_PATH)
	if service_script == null or not service_script.has_method("new"):
		return null
	return service_script.new()


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(String(item))
	return result
