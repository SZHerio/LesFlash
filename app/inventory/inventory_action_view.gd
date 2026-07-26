class_name InventoryActionView
extends RefCounted

const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const CurrencyTextScript := preload("res://app/presentation/currency_text.gd")

const METER_TITLES := {
	"health": "Здоровье",
	"energy": "Энергия",
	"hunger": "Голод",
	"tension": "Напряжение",
	"morale": "Настроение",
}
const REQUIREMENT_TITLES := {
	"stat": "Характеристика",
	"state": "Состояние",
	"money": "Деньги",
	"item": "Предмет",
	"skill": "Навык",
	"knowledge": "Знание",
	"polarity": "Полярность",
}


static func build(
	action_id: String,
	title: String,
	raw_action: Dictionary,
	stack_quantity: int,
	kind: String = "normal"
) -> Dictionary:
	var duration := maxi(int(raw_action.get("duration_minutes", 0)), 0)
	var effects: Array = Array(raw_action.get("effects", [])).duplicate(true)
	var outputs: Array = Array(raw_action.get("outputs", [])).duplicate(true)
	var conditions: Array = Array(raw_action.get("conditions", [])).duplicate(true)
	return {
		"id": action_id,
		"title": title,
		"kind": kind,
		"duration_minutes": duration,
		"duration_text": "Время не изменится" if duration == 0 else "Время: %d мин." % duration,
		"effects": effects,
		"effect_lines": _effect_lines(effects),
		"outputs": outputs,
		"output_lines": _output_lines(outputs),
		"conditions": conditions,
		"condition_lines": _condition_lines(conditions),
		"quantity_adjustable": action_id in ["move", "drop", "pick_up"] and stack_quantity > 1,
		"max_quantity": maxi(stack_quantity, 1),
	}


static func _effect_lines(effects: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_effect in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := String(effect.get("type", effect.get("kind", "")))
		match effect_type:
			"change_state":
				var meter_id := String(effect.get("id", ""))
				result.append("%s: %s" % [
					String(METER_TITLES.get(meter_id, meter_id)),
					_signed(int(effect.get("delta", 0))),
				])
			"change_money":
				result.append(
					"Деньги: %s" % CurrencyTextScript.signed_compact(int(effect.get("delta", 0)))
				)
			"mastery":
				result.append("Опыт навыка: %s" % _signed(int(effect.get("amount", 0))))
			"shift_polarity":
				result.append("Полярность «%s»: %s" % [
					String(effect.get("id", "")),
					_signed(int(effect.get("delta", 0))),
				])
			_:
				result.append("Эффект: %s" % effect_type)
	return result


static func _output_lines(outputs: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_output in outputs:
		if not raw_output is Dictionary:
			continue
		var output: Dictionary = raw_output
		var definition: Variant = ItemCatalog.definition(String(output.get("item_id", "")))
		result.append("%s ×%d" % [definition.title(), maxi(int(output.get("quantity", 1)), 1)])
	return result


static func _condition_lines(conditions: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_condition in conditions:
		if not raw_condition is Dictionary:
			continue
		var condition: Dictionary = raw_condition
		var kind := String(condition.get("kind", condition.get("type", "")))
		var identifier := String(condition.get("id", condition.get("key", "")))
		var operator := String(condition.get("operator", condition.get("op", ">=")))
		var required: Variant = condition.get(
			"value",
			condition.get("amount", condition.get("quantity", condition.get("rank", "?")))
		)
		result.append("%s «%s»: %s %s" % [
			String(REQUIREMENT_TITLES.get(kind, kind.capitalize())),
			identifier,
			operator,
			str(required),
		])
	return result


static func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
