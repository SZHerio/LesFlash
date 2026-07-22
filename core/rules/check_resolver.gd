class_name CheckResolver
extends RefCounted

## Resolves data-driven conditions without mutating RunState.

const SUPPORTED_OPERATORS := [">=", ">", "==", "!=", "<", "<="]


static func evaluate_all(
		run_state: Object,
		conditions: Array,
		_context: Dictionary = {}
	) -> Dictionary:
	var checks: Array[Dictionary] = []
	var reasons: Array[Dictionary] = []
	for index: int in conditions.size():
		var raw_condition: Variant = conditions[index]
		if not raw_condition is Dictionary:
			var invalid := _invalid_result(
				{},
				"invalid_condition",
				"Условие должно быть словарём"
			)
			invalid["index"] = index
			checks.append(invalid)
			reasons.append(invalid.duplicate(true))
			continue
		var check := evaluate(run_state, raw_condition)
		check["index"] = index
		checks.append(check)
		if not bool(check["passed"]):
			reasons.append(check.duplicate(true))
	return {
		"allowed": reasons.is_empty(),
		"reasons": reasons,
		"checks": checks,
	}


static func evaluate(
		run_state: Object,
		condition: Dictionary,
		_context: Dictionary = {}
	) -> Dictionary:
	if run_state == null:
		return _invalid_result(condition, "missing_state", "Состояние игры отсутствует")

	var kind := _normalized_kind(condition)
	if kind.is_empty():
		return _invalid_result(condition, "invalid_condition", "Не указан тип условия")
	var operator := _normalized_operator(condition)
	if operator not in SUPPORTED_OPERATORS:
		return _invalid_result(
			condition,
			"invalid_operator",
			"Неизвестный оператор условия: %s" % operator
		)

	var required_result := _required_value(condition)
	if not bool(required_result["valid"]):
		return _invalid_result(condition, "invalid_value", String(required_result["message"]))
	var required: float = required_result["value"]
	var identifier := _identifier(condition)
	var actual_result: Dictionary

	match kind:
		"stat":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.stat_value(run_state, identifier)
		"state":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.meter_value(run_state, identifier)
		"money":
			actual_result = RuleStateAccess.money_value(run_state)
		"item":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.item_value(run_state, identifier)
		"polarity":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.polarity_value(run_state, identifier)
			if bool(actual_result.get("found", false)) and not bool(actual_result.get("formed", true)):
				return _blocked_result(
					condition,
					kind,
					identifier,
					operator,
					0.0,
					required,
					"profile_not_formed",
					"Профиль «%s» ещё не сформирован" % identifier
				)
		"skill":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.skill_value(run_state, identifier)
		"knowledge":
			if identifier.is_empty():
				return _missing_identifier(condition, kind)
			actual_result = RuleStateAccess.knowledge_value(run_state, identifier)
		_:
			return _invalid_result(
				condition,
				"unknown_condition",
				"Неизвестный тип условия: %s" % kind
			)

	if not bool(actual_result.get("found", false)):
		return _blocked_result(
			condition,
			kind,
			identifier,
			operator,
			0.0,
			required,
			"unknown_requirement",
			"Не найден параметр «%s» для условия %s" % [identifier, kind]
		)

	var actual := float(actual_result.get("value", 0.0))
	var passed := _compare(actual, required, operator)
	var custom_reason := String(condition.get("blocked_reason", ""))
	var message := ""
	if passed:
		message = "Условие выполнено"
	elif not custom_reason.is_empty():
		message = custom_reason
	else:
		message = _default_blocked_message(kind, identifier, operator, required, actual)
	return {
		"passed": passed,
		"code": "ok" if passed else _failure_code(kind, operator, required, actual),
		"message": message,
		"kind": kind,
		"id": identifier,
		"operator": operator,
		"required": required,
		"actual": actual,
		"condition": condition.duplicate(true),
	}


static func can_execute(run_state: Object, conditions: Array, context: Dictionary = {}) -> bool:
	return bool(evaluate_all(run_state, conditions, context)["allowed"])


static func blocked_reasons(
		run_state: Object,
		conditions: Array,
		context: Dictionary = {}
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_reasons: Variant = evaluate_all(run_state, conditions, context)["reasons"]
	if raw_reasons is Array:
		for reason: Variant in raw_reasons:
			if reason is Dictionary:
				result.append(reason)
	return result


static func _normalized_kind(condition: Dictionary) -> String:
	var kind := String(condition.get("kind", condition.get("type", ""))).strip_edges().to_lower()
	return kind.replace("-", "_")


static func _identifier(condition: Dictionary) -> String:
	return String(condition.get("id", condition.get("key", condition.get("name", "")))).strip_edges()


static func _normalized_operator(condition: Dictionary) -> String:
	var operator := String(condition.get("operator", condition.get("op", ">="))).strip_edges().to_lower()
	match operator:
		"gte", "at_least", "min":
			return ">="
		"gt":
			return ">"
		"eq", "equals":
			return "=="
		"ne", "not_equals":
			return "!="
		"lt":
			return "<"
		"lte", "at_most", "max":
			return "<="
		_:
			return operator


static func _required_value(condition: Dictionary) -> Dictionary:
	var value: Variant = condition.get(
		"value",
		condition.get("amount", condition.get("quantity", condition.get("rank", condition.get("level"))))
	)
	if value is int or value is float:
		return {"valid": true, "value": float(value), "message": ""}
	return {"valid": false, "value": 0.0, "message": "Требуемое значение должно быть числом"}


static func _compare(actual: float, required: float, operator: String) -> bool:
	match operator:
		">=":
			return actual >= required
		">":
			return actual > required
		"==":
			return is_equal_approx(actual, required)
		"!=":
			return not is_equal_approx(actual, required)
		"<":
			return actual < required
		"<=":
			return actual <= required
	return false


static func _default_blocked_message(
		kind: String,
		identifier: String,
		operator: String,
		required: float,
		actual: float
	) -> String:
	var label := identifier if not identifier.is_empty() else _kind_label(kind)
	return "%s: требуется %s %s, сейчас %s" % [
		label,
		operator,
		_format_number(required),
		_format_number(actual),
	]


static func _kind_label(kind: String) -> String:
	match kind:
		"money":
			return "Деньги"
		"item":
			return "Предмет"
		"skill":
			return "Навык"
		"knowledge":
			return "Знание"
		"polarity":
			return "Полярность"
		"state":
			return "Состояние"
		"stat":
			return "Характеристика"
	return "Условие"


static func _failure_code(kind: String, operator: String, required: float, actual: float) -> String:
	if operator in [">=", ">"] and actual < required:
		return "%s_too_low" % kind
	if operator in ["<=", "<"] and actual > required:
		return "%s_too_high" % kind
	return "%s_mismatch" % kind


static func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(value))
	return "%.2f" % value


static func _missing_identifier(condition: Dictionary, kind: String) -> Dictionary:
	return _invalid_result(
		condition,
		"missing_identifier",
		"Для условия %s не указан идентификатор" % kind
	)


static func _invalid_result(condition: Dictionary, code: String, message: String) -> Dictionary:
	return {
		"passed": false,
		"code": code,
		"message": message,
		"kind": _normalized_kind(condition),
		"id": _identifier(condition),
		"operator": _normalized_operator(condition),
		"required": null,
		"actual": null,
		"condition": condition.duplicate(true),
	}


static func _blocked_result(
		condition: Dictionary,
		kind: String,
		identifier: String,
		operator: String,
		actual: float,
		required: float,
		code: String,
		message: String
	) -> Dictionary:
	return {
		"passed": false,
		"code": code,
		"message": message,
		"kind": kind,
		"id": identifier,
		"operator": operator,
		"required": required,
		"actual": actual,
		"condition": condition.duplicate(true),
	}
