class_name RunWeightedChoice
extends RefCounted

## Choosing one option out of several, the same way every time for the same run.
##
## Nothing here rolls dice. Every pick is a pure function of the run's seed and a
## tag naming the decision, so a reloaded save offers the same card it offered
## before — the guarantee the whole save format rests on.
##
## Cards also carry weight by how much they hurt: an unlucky hero meets the
## harsher ones more often, and a lucky one meets them less, without either
## outcome ever becoming certain.

static func start_situation(starts: Array, state: RunState) -> Dictionary:
	var weights: Array = []
	var luck := state.get_characteristic("luck")
	for situation in starts:
		var weight := float(situation.get("weight", 1.0))
		var by_luck: Variant = situation.get("weights_by_luck", situation.get("weight_by_luck", null))
		if by_luck is Dictionary:
			weight = float(by_luck.get(str(luck), by_luck.get(luck, weight)))
		elif by_luck is Array:
			if by_luck.size() == 11:
				weight = float(by_luck[luck])
			elif by_luck.size() >= 10:
				weight = float(by_luck[luck - 1])
		var bands := ContentShape.dictionary_array(situation.get("luck_bands", []))
		for band in bands:
			if luck >= int(band.get("min", 1)) and luck <= int(band.get("max", 10)):
				weight = float(band.get("weight", weight))
				break
		weights.append(maxf(weight, 0.0))
	return _pick_with_weights(starts, weights, "start:%s" % String(state.rng.to_dict().get("seed", "0")), state)


static func event_card(values: Array, tag: String, state: RunState) -> Dictionary:
	var weights: Array = []
	var luck_ratio := clampf(
		float(state.get_characteristic("luck") - GameRules.CHARACTERISTIC_MIN) /
		float(GameRules.CHARACTERISTIC_MAX - GameRules.CHARACTERISTIC_MIN),
		0.0,
		1.0
	)
	for value in values:
		var base_weight := maxf(float(value.get("weight", 1.0)), 0.0)
		var adversity_ratio := clampf(_event_adversity(value) / 8.0, 0.0, 1.0)
		var unlucky_multiplier := 1.0 + adversity_ratio
		var lucky_multiplier := 1.0 - 0.75 * adversity_ratio
		weights.append(base_weight * lerpf(unlucky_multiplier, lucky_multiplier, luck_ratio))
	return _pick_with_weights(values, weights, tag, state)


static func _event_adversity(card: Dictionary) -> float:
	if card.has("adversity"):
		return maxf(float(card.get("adversity", 0.0)), 0.0)
	var choices := ContentShape.choices_of(card)
	if choices.is_empty():
		return 0.0
	var total := 0.0
	for choice in choices:
		for effect in ContentShape.array_copy(choice.get("effects", [])):
			total += _effect_adversity(effect)
	return total / float(choices.size())


static func _effect_adversity(effect: Variant) -> float:
	if not effect is Dictionary:
		return 0.0
	var effect_type := ContentShape.effect_type(effect)
	match effect_type:
		"change_state":
			var identifier := String(effect.get("id", effect.get("key", "")))
			var delta := float(effect.get("delta", effect.get("amount", 0)))
			if identifier in ["hunger", "tension"]:
				return maxf(delta, 0.0)
			return maxf(-delta, 0.0)
		"change_money":
			return maxf(-float(effect.get("delta", effect.get("amount", 0))) / 10.0, 0.0)
		"remove_item":
			return maxf(float(effect.get("quantity", effect.get("amount", 1))) * 3.0, 0.0)
		"deferred":
			var payload: Variant = effect.get("payload", {})
			if not payload is Dictionary:
				return 0.0
			var result := 0.0
			for key_value in payload:
				var key := String(key_value)
				var delta_value: Variant = payload[key_value]
				if not (delta_value is int or delta_value is float):
					continue
				var delta := float(delta_value)
				if key in ["hunger", "tension"]:
					result += maxf(delta, 0.0)
				elif key == "money":
					result += maxf(-delta / 10.0, 0.0)
				elif GameRules.is_known_meter(key):
					result += maxf(-delta, 0.0)
			return result
	return 0.0


static func _pick_with_weights(values: Array, weights: Array, tag: String, state: RunState) -> Dictionary:
	if values.is_empty() or values.size() != weights.size():
		return {}
	var total := 0.0
	for weight in weights:
		total += float(weight)
	if total <= 0.0:
		return values[0]
	var cursor := _stable_unit(tag, state) * total
	for index in range(values.size()):
		cursor -= float(weights[index])
		if cursor < 0.0:
			return values[index]
	return values.back()


static func _stable_unit(tag: String, state: RunState) -> float:
	var seed_text := "0"
	if state != null and state.rng != null:
		seed_text = String(state.rng.to_dict().get("seed", "0"))
	var text := "%s|%s" % [seed_text, tag]
	var hash_value: int = 2_166_136_261
	for index in range(text.length()):
		hash_value = ((hash_value ^ text.unicode_at(index)) * 16_777_619) & 0x7fffffff
	return float(hash_value % 1_000_000) / 1_000_000.0
