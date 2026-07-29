class_name Effect
extends RefCounted

## Data-only constructors for state mutations.
##
## EffectApplier is the only M1 component that interprets these dictionaries.
## Event content must never mutate RunState directly.

const ADVANCE_TIME: StringName = &"advance_time"
const CHANGE_STATE: StringName = &"change_state"
const CHANGE_MONEY: StringName = &"change_money"
const ADD_ITEM: StringName = &"add_item"
const REMOVE_ITEM: StringName = &"remove_item"
const SHIFT_POLARITY: StringName = &"shift_polarity"
const UNLOCK_SKILL: StringName = &"unlock_skill"
const ADVANCE_SKILL: StringName = &"advance_skill"
const PRACTICE_SKILL: StringName = &"practice_skill"
const WASH: StringName = &"wash"
const MASTERY: StringName = &"mastery"
const DEFERRED: StringName = &"deferred"
const KNOWLEDGE: StringName = &"knowledge"


static func advance_time(minutes: int, reason: String = "", payload: Dictionary = {}) -> Dictionary:
	return {
		"type": String(ADVANCE_TIME),
		"minutes": minutes,
		"reason": reason,
		"payload": payload.duplicate(true),
	}


static func change_state(state_id: StringName, delta: int) -> Dictionary:
	return {
		"type": String(CHANGE_STATE),
		"id": String(state_id),
		"delta": delta,
	}


static func change_money(delta: int, allow_negative: bool = false) -> Dictionary:
	return {
		"type": String(CHANGE_MONEY),
		"delta": delta,
		"allow_negative": allow_negative,
	}


static func add_item(item_id: StringName, quantity: int = 1) -> Dictionary:
	return {
		"type": String(ADD_ITEM),
		"id": String(item_id),
		"quantity": quantity,
	}


static func remove_item(item_id: StringName, quantity: int = 1) -> Dictionary:
	return {
		"type": String(REMOVE_ITEM),
		"id": String(item_id),
		"quantity": quantity,
	}


static func shift_polarity(polarity_id: StringName, delta: int) -> Dictionary:
	return {
		"type": String(SHIFT_POLARITY),
		"id": String(polarity_id),
		"delta": delta,
	}


static func unlock_skill(skill_id: StringName, initial_rank: int = 1) -> Dictionary:
	return {
		"type": String(UNLOCK_SKILL),
		"id": String(skill_id),
		"rank": initial_rank,
	}


## One confirmed use of a skill, tagged by what it was. Ranks are derived from
## how many different sources have been recorded, so content declares practice
## and never a rank.
## Stringified like its neighbours: a StringName reaching the journal makes the
## save payload non-JSON, and the packet is rejected as an unwritable entry —
## an error that names the journal and says nothing about the skill.
## Мытьё. Не показатель — отметка о времени, из которой потом выводится то, как
## героя читают. Отдельным эффектом, потому что записать это может только то,
## что действительно было сделано.
static func wash() -> Dictionary:
	return {"type": String(WASH)}


static func practice_skill(skill_id: StringName, source_id: StringName) -> Dictionary:
	return {
		"type": String(PRACTICE_SKILL),
		"id": String(skill_id),
		"source_id": String(source_id),
	}


static func advance_skill(skill_id: StringName, ranks: int = 1, max_rank: int = 3) -> Dictionary:
	return {
		"type": String(ADVANCE_SKILL),
		"id": String(skill_id),
		"ranks": ranks,
		"max_rank": max_rank,
	}


static func mastery(delta: int) -> Dictionary:
	return {
		"type": String(MASTERY),
		"delta": delta,
	}


static func deferred(
		effect_id: StringName,
		delay_minutes: int,
		payload: Dictionary = {},
		deferred_id: StringName = &"",
		source_id: StringName = &""
	) -> Dictionary:
	return {
		"type": String(DEFERRED),
		"effect_id": String(effect_id),
		"delay_minutes": delay_minutes,
		"payload": payload.duplicate(true),
		"deferred_id": String(deferred_id),
		"source_id": String(source_id),
	}


static func deferred_at(
		effect_id: StringName,
		due: Dictionary,
		payload: Dictionary = {},
		deferred_id: StringName = &"",
		source_id: StringName = &""
	) -> Dictionary:
	return {
		"type": String(DEFERRED),
		"effect_id": String(effect_id),
		"due": due.duplicate(true),
		"payload": payload.duplicate(true),
		"deferred_id": String(deferred_id),
		"source_id": String(source_id),
	}


static func knowledge(
		knowledge_id: StringName,
		amount: int = 1,
		mode: StringName = &"add"
	) -> Dictionary:
	return {
		"type": String(KNOWLEDGE),
		"id": String(knowledge_id),
		"amount": amount,
		"mode": String(mode),
	}
