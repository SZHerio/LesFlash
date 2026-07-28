class_name ContentShape
extends RefCounted

## Reading the shape of an authored card without trusting it.
##
## Content is written by hand, and hands are inconsistent: choices arrive as a
## list or as a map keyed by id, an effect calls itself "type" or "kind", the
## same effect is spelled "change_meter" in one card and "meter" in the next.
## These helpers accept every spelling that was ever authored and hand back one
## shape, so the rest of the game never has to ask which dialect a card is in.

static func choices_of(card: Dictionary) -> Array:
	return dictionary_array(card.get("choices", card.get("options", [])))


static func dictionary_array(raw: Variant) -> Array:
	var result: Array = []
	if raw is Dictionary:
		for key in raw:
			var value: Variant = raw[key]
			if value is Dictionary:
				result.append(value.duplicate(true))
	elif raw is Array:
		for value in raw:
			if value is Dictionary:
				result.append(value.duplicate(true))
	return result


static func array_copy(raw: Variant) -> Array:
	return raw.duplicate(true) if raw is Array else []


static func effect_type(effect: Variant) -> String:
	if not effect is Dictionary:
		return ""
	var result := String(effect.get("type", effect.get("kind", ""))).strip_edges().to_lower().replace("-", "_")
	match result:
		"time", "advance_clock":
			return "advance_time"
		"change_meter", "meter":
			return "change_state"
		"money":
			return "change_money"
		"mastery_points":
			return "mastery"
	return result
