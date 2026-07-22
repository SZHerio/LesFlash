class_name Condition
extends RefCounted

## Data-only constructors for requirements used by events and actions.
##
## Every constructor returns a plain Dictionary so content can be loaded from
## JSON without instantiating scripts. CheckResolver accepts both `kind` and
## `type`, and normalizes common spelling variants.

const STAT: StringName = &"stat"
const STATE: StringName = &"state"
const MONEY: StringName = &"money"
const ITEM: StringName = &"item"
const POLARITY: StringName = &"polarity"
const SKILL: StringName = &"skill"
const KNOWLEDGE: StringName = &"knowledge"

const GREATER_OR_EQUAL: StringName = &">="
const GREATER: StringName = &">"
const EQUAL: StringName = &"=="
const NOT_EQUAL: StringName = &"!="
const LESS: StringName = &"<"
const LESS_OR_EQUAL: StringName = &"<="


static func stat(
		stat_id: StringName,
		value: float,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(STAT, stat_id, value, operator)


static func state(
		state_id: StringName,
		value: float,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(STATE, state_id, value, operator)


static func money(
		amount: int,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return {
		"kind": String(MONEY),
		"value": amount,
		"operator": String(operator),
	}


static func item(
		item_id: StringName,
		quantity: int = 1,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(ITEM, item_id, quantity, operator)


static func polarity(
		polarity_id: StringName,
		value: float,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(POLARITY, polarity_id, value, operator)


static func skill(
		skill_id: StringName,
		rank: int = 1,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(SKILL, skill_id, rank, operator)


static func knowledge(
		knowledge_id: StringName,
		level: int = 1,
		operator: StringName = GREATER_OR_EQUAL
	) -> Dictionary:
	return _make(KNOWLEDGE, knowledge_id, level, operator)


static func with_reason(condition: Dictionary, blocked_reason: String) -> Dictionary:
	var result := condition.duplicate(true)
	result["blocked_reason"] = blocked_reason
	return result


static func _make(
		kind: StringName,
		identifier: StringName,
		value: Variant,
		operator: StringName
	) -> Dictionary:
	return {
		"kind": String(kind),
		"id": String(identifier),
		"value": value,
		"operator": String(operator),
	}
