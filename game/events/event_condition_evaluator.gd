class_name EventConditionEvaluator
extends RefCounted

## Pure evaluator for conditions stored in contextual event data.
##
## It deliberately consumes EventContext rather than RunState. Preview,
## selection traces and runtime execution therefore see the same immutable
## values and never advance an RNG stream.

const SUPPORTED_KINDS := [
	"source",
	"location",
	"era",
	"weather",
	"calendar",
	"stat",
	"state",
	"polarity",
	"skill",
	"knowledge",
	"item",
	"relationship",
	"reputation",
	"world_fact",
	"world_metric",
	"world_process",
	"npc_memory",
	"commitment",
	"history",
	"cooldown",
	"risk",
]
const SUPPORTED_OPERATORS := [">=", ">", "==", "!=", "<", "<="]
const POLARITY_BANDS := {
	"neutral": 0,
	"weak": 6,
	"noticeable": 26,
	"expressed": 51,
	"extreme": 76,
}


static func evaluate_all(context: Dictionary, conditions: Array) -> Dictionary:
	var checks: Array = []
	var reasons: Array = []
	for index: int in conditions.size():
		var raw_condition: Variant = conditions[index]
		var check := evaluate(context, raw_condition)
		check["index"] = index
		checks.append(check)
		if not bool(check.get("passed", false)):
			reasons.append(check.duplicate(true))
	return {
		"allowed": reasons.is_empty(),
		"checks": checks,
		"reasons": reasons,
	}


static func evaluate(context: Dictionary, raw_condition: Variant) -> Dictionary:
	if not raw_condition is Dictionary:
		return _invalid({}, "invalid_condition", "Условие должно быть объектом")
	var condition: Dictionary = raw_condition
	var kind := String(condition.get("kind", "")).strip_edges().to_lower()
	var identifier := String(condition.get("id", "")).strip_edges()
	var operator := String(condition.get("operator", "==")).strip_edges()
	if kind not in SUPPORTED_KINDS:
		return _invalid(condition, "unknown_condition", "Неизвестный тип условия: %s" % kind)
	if kind == "polarity" and condition.has("band"):
		return _evaluate_polarity_band(context, condition, identifier)
	if operator not in SUPPORTED_OPERATORS:
		return _invalid(condition, "invalid_operator", "Неизвестный оператор: %s" % operator)
	var lookup := _lookup(context, kind, identifier, condition)
	if not bool(lookup.get("found", false)):
		return _result(
			condition,
			false,
			"missing_value",
			lookup.get("value", 0),
			condition.get("value", true),
			String(lookup.get("message", "Контекст не содержит нужного значения"))
		)
	var required: Variant = condition.get("value", true)
	var actual: Variant = lookup.get("value")
	var comparison := _compare(actual, required, operator)
	if not bool(comparison.get("valid", false)):
		return _invalid(condition, "invalid_comparison", String(comparison.get("message", "")))
	var passed := bool(comparison.get("passed", false))
	var message := "Условие выполнено"
	if not passed:
		message = String(condition.get("blocked_reason", "")).strip_edges()
		if message.is_empty():
			message = "%s: требуется %s %s, сейчас %s" % [
				_label(kind, identifier),
				operator,
				str(required),
				str(actual),
			]
	return _result(
		condition,
		passed,
		"ok" if passed else "condition_not_met",
		actual,
		required,
		message
	)


static func _lookup(
	context: Dictionary,
	kind: String,
	identifier: String,
	condition: Dictionary = {}
) -> Dictionary:
	match kind:
		"source":
			return _dictionary_value(context.get("source", {}), identifier)
		"location":
			return _scalar(context, "location_id")
		"era":
			return _scalar(context, "era_id")
		"weather":
			return _scalar(context, "weather_id")
		"calendar":
			return _dictionary_value(context.get("calendar", {}), identifier)
		"stat":
			return _actor_value(context, "characteristics", identifier)
		"state":
			return _actor_value(context, "meters", identifier)
		"polarity":
			var stored := _actor_value(context, "stored_polarities", identifier)
			return stored if bool(stored.get("found", false)) else _actor_value(
				context,
				"computed_profiles",
				identifier
			)
		"skill":
			return _actor_value(context, "skills", identifier)
		"knowledge":
			return _actor_value(context, "knowledge", identifier)
		"item":
			return _dictionary_value(
				Dictionary(context.get("actor", {})).get("items", {}),
				identifier,
				0
			)
		"relationship":
			var relationship: Variant = Dictionary(context.get("relationships", {})).get(identifier)
			var relationship_field := String(condition.get("field", ""))
			if not relationship is Dictionary or relationship_field not in ["trust", "respect", "affinity", "fear"]:
				return {"found": false, "value": 0, "message": "Не указано поле отношения NPC"}
			return _dictionary_value(relationship, relationship_field)
		"reputation":
			return _dictionary_value(context.get("reputations", {}), identifier, 0)
		"world_fact":
			return _dictionary_value(Dictionary(context.get("world", {})).get("facts", {}), identifier, false)
		"world_metric":
			return _dictionary_value(Dictionary(context.get("world", {})).get("metrics", {}), identifier)
		"world_process":
			return _dictionary_value(Dictionary(context.get("world", {})).get("processes", {}), identifier)
		"npc_memory":
			return {"found": true, "value": _has_memory(context, identifier, String(condition.get("npc_id", "")))}
		"commitment":
			var commitment: Variant = Dictionary(context.get("commitments", {})).get(identifier)
			var commitment_field := String(condition.get("field", ""))
			if commitment_field.is_empty():
				return {"found": true, "value": commitment is Dictionary}
			if not commitment is Dictionary:
				return {"found": false, "value": null, "message": "Обязательство не найдено"}
			return _dictionary_value(commitment, commitment_field)
		"history":
			return {
				"found": true,
				"value": identifier in Array(context.get("history_facts", [])),
			}
		"cooldown":
			var ready_at := int(Dictionary(context.get("cooldowns", {})).get(identifier, 0))
			var elapsed := int(Dictionary(context.get("calendar", {})).get("elapsed_minutes", 0))
			return {"found": true, "value": elapsed >= ready_at}
		"risk":
			return _dictionary_value(context.get("risk", {}), identifier, 0)
	return {"found": false, "value": null, "message": "Неизвестный источник значения"}


static func _has_memory(context: Dictionary, memory_id: String, npc_id: String) -> bool:
	var memories: Dictionary = context.get("npc_memories", {})
	var npc_ids: Array = [npc_id] if not npc_id.is_empty() else memories.keys()
	for raw_npc_id: Variant in npc_ids:
		for raw_memory: Variant in Array(memories.get(raw_npc_id, [])):
			if raw_memory is Dictionary and String(raw_memory.get("memory_id", "")) == memory_id:
				return true
	return false


static func _evaluate_polarity_band(
	context: Dictionary,
	condition: Dictionary,
	identifier: String
) -> Dictionary:
	var band := String(condition.get("band", ""))
	var side := String(condition.get("side", ""))
	if band not in POLARITY_BANDS or side not in ["left", "right", "center"]:
		return _invalid(condition, "invalid_polarity_band", "Неизвестный диапазон полярности")
	var lookup := _lookup(context, "polarity", identifier, condition)
	if not bool(lookup.get("found", false)):
		return _invalid(condition, "missing_value", "Полярность отсутствует в контексте")
	var actual := int(lookup.get("value", 0))
	var threshold := int(POLARITY_BANDS[band])
	var passed := false
	if band == "neutral":
		passed = absi(actual) <= 5 and side == "center"
	elif side == "left":
		passed = actual <= -threshold
	elif side == "right":
		passed = actual >= threshold
	var message := "Условие выполнено" if passed else String(condition.get("blocked_reason", "Недостаточно выражен нужный способ действия"))
	var result := _result(
		condition,
		passed,
		"ok" if passed else "condition_not_met",
		actual,
		{"band": band, "side": side},
		message
	)
	result["band"] = band
	result["side"] = side
	return result


static func _actor_value(context: Dictionary, group: String, identifier: String) -> Dictionary:
	return _dictionary_value(Dictionary(context.get("actor", {})).get(group, {}), identifier)


static func _dictionary_value(
	raw_dictionary: Variant,
	identifier: String,
	fallback: Variant = null
) -> Dictionary:
	if not raw_dictionary is Dictionary or identifier.is_empty():
		return {"found": false, "value": fallback, "message": "Не указан параметр контекста"}
	var dictionary: Dictionary = raw_dictionary
	if dictionary.has(identifier):
		return {"found": true, "value": dictionary[identifier]}
	if fallback != null:
		return {"found": true, "value": fallback}
	return {
		"found": false,
		"value": null,
		"message": "В контексте отсутствует «%s»" % identifier,
	}


static func _scalar(context: Dictionary, field: String) -> Dictionary:
	if not context.has(field):
		return {"found": false, "value": null, "message": "В контексте отсутствует %s" % field}
	return {"found": true, "value": context[field]}


static func _compare(actual: Variant, required: Variant, operator: String) -> Dictionary:
	var numeric := (actual is int or actual is float) and (required is int or required is float)
	if numeric:
		var left := float(actual)
		var right := float(required)
		match operator:
			">=": return {"valid": true, "passed": left >= right}
			">": return {"valid": true, "passed": left > right}
			"==": return {"valid": true, "passed": is_equal_approx(left, right)}
			"!=": return {"valid": true, "passed": not is_equal_approx(left, right)}
			"<": return {"valid": true, "passed": left < right}
			"<=": return {"valid": true, "passed": left <= right}
	if operator not in ["==", "!="]:
		return {
			"valid": false,
			"passed": false,
			"message": "Строки и флаги поддерживают только == и !=",
		}
	var equal: bool = typeof(actual) == typeof(required) and actual == required
	return {"valid": true, "passed": equal if operator == "==" else not equal}


static func _result(
	condition: Dictionary,
	passed: bool,
	code: String,
	actual: Variant,
	required: Variant,
	message: String
) -> Dictionary:
	return {
		"passed": passed,
		"code": code,
		"message": message,
		"kind": String(condition.get("kind", "")),
		"id": String(condition.get("id", "")),
		"operator": String(condition.get("operator", "==")),
		"actual": actual,
		"required": required,
		"condition": condition.duplicate(true),
	}


static func _invalid(condition: Dictionary, code: String, message: String) -> Dictionary:
	return _result(condition, false, code, null, condition.get("value"), message)


static func _label(kind: String, identifier: String) -> String:
	var titles := {
		"source": "Источник",
		"location": "Локация",
		"era": "Эпоха",
		"weather": "Погода",
		"calendar": "Время",
		"stat": "Характеристика",
		"state": "Состояние",
		"polarity": "Полярность",
		"skill": "Навык",
		"knowledge": "Знание",
		"item": "Предмет",
		"relationship": "Отношение",
		"reputation": "Репутация",
		"world_fact": "Факт мира",
		"world_metric": "Показатель мира",
		"world_process": "Процесс мира",
		"npc_memory": "Память NPC",
		"commitment": "Обязательство",
		"history": "История",
		"cooldown": "Повтор",
		"risk": "Риск",
	}
	return "%s «%s»" % [String(titles.get(kind, kind)), identifier]
