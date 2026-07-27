class_name EventDirector
extends RefCounted

## Deterministic contextual event selector with an auditable trace.
##
## `analyze` and `preview` are pure. Only `select` advances the caller-owned
## event RNG clone returned in the result.

const ContextScript := preload("res://game/events/event_context.gd")
const ConditionEvaluator := preload("res://game/events/event_condition_evaluator.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")


static func analyze(catalog: Dictionary, context: Dictionary) -> Dictionary:
	var context_validation := ContextScript.validate(context)
	if not bool(context_validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_context",
			"cards": [],
			"errors": Array(context_validation.get("errors", [])).duplicate(),
		}
	var traces: Array = []
	for raw_card: Variant in Array(catalog.get("cards", [])):
		if raw_card is Dictionary:
			traces.append(_analyze_card(Dictionary(raw_card), context))
	return {"ok": true, "code": "ok", "cards": traces, "errors": []}


static func select(
	catalog: Dictionary,
	context: Dictionary,
	rng_snapshot: Dictionary
) -> Dictionary:
	var analysis := analyze(catalog, context)
	if not bool(analysis.get("ok", false)):
		return analysis
	var rng: DeterministicRng = RngScript.from_dict(rng_snapshot)
	if rng == null:
		return {
			"ok": false,
			"code": "invalid_rng",
			"card": {},
			"trace": analysis,
			"rng": rng_snapshot.duplicate(true),
			"errors": ["Event RNG повреждён"],
		}
	var candidates: Array = []
	var weights: Array = []
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if not raw_trace is Dictionary or not bool(raw_trace.get("included", false)):
			continue
		var trace: Dictionary = raw_trace
		candidates.append(String(trace.get("card_id", "")))
		weights.append(float(trace.get("adjusted_weight", 0.0)))
	if candidates.is_empty():
		return {
			"ok": true,
			"code": "empty_pool",
			"card": {},
			"card_id": "",
			"trace": analysis,
			"rng": rng.to_dict(),
			"errors": [],
		}
	var selected_index := rng.weighted_index(weights)
	if selected_index < 0:
		return {
			"ok": false,
			"code": "invalid_weights",
			"card": {},
			"trace": analysis,
			"rng": rng_snapshot.duplicate(true),
			"errors": ["Пул событий имеет нулевой вес"],
		}
	var card_id := String(candidates[selected_index])
	return {
		"ok": true,
		"code": "selected",
		"card_id": card_id,
		"card": _find_card(catalog, card_id),
		"preview": preview(catalog, card_id, context),
		"trace": analysis,
		"rng": rng.to_dict(),
		"errors": [],
	}


static func preview(
	catalog: Dictionary,
	card_id: String,
	context: Dictionary
) -> Dictionary:
	var card := _find_card(catalog, card_id)
	if card.is_empty():
		return {"ok": false, "code": "unknown_card", "card_id": card_id, "options": []}
	var options: Array = []
	for raw_option: Variant in Array(card.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var checks := ConditionEvaluator.evaluate_all(
			context,
			Array(option.get("conditions", []))
		)
		options.append({
			"id": String(option.get("id", "")),
			"label": String(option.get("label", "")),
			"available": bool(checks.get("allowed", false)),
			"blocked_reasons": Array(checks.get("reasons", [])).duplicate(true),
			"effects": Array(option.get("effects", [])).duplicate(true),
			"outcome": String(option.get("outcome", "")),
		})
	return {
		"ok": true,
		"code": "ok",
		"card_id": card_id,
		"title": String(card.get("title", "")),
		"body": String(card.get("body", "")),
		"tone": String(card.get("tone", "neutral")),
		"options": options,
	}


static func _analyze_card(card: Dictionary, context: Dictionary) -> Dictionary:
	var reasons: Array = []
	var location_id := String(context.get("location_id", ""))
	var locations: Array = Array(card.get("locations", []))
	if location_id not in locations:
		reasons.append({
			"code": "location_mismatch",
			"message": "Локация «%s» не входит в %s" % [location_id, str(locations)],
		})
	var source_kind := String(Dictionary(context.get("source", {})).get("kind", ""))
	var source_kinds: Array = Array(card.get("source_kinds", []))
	if source_kind not in source_kinds:
		reasons.append({
			"code": "source_mismatch",
			"message": "Источник «%s» не входит в %s" % [source_kind, str(source_kinds)],
		})
	var cooldowns: Dictionary = context.get("cooldowns", {})
	var ready_at := int(cooldowns.get(String(card.get("id", "")), 0))
	var elapsed := int(Dictionary(context.get("calendar", {})).get("elapsed_minutes", 0))
	if ready_at > elapsed:
		reasons.append({
			"code": "cooldown_active",
			"message": "Повтор станет возможен через %d мин." % (ready_at - elapsed),
			"ready_at": ready_at,
		})
	var occurrences := 0
	var history_prefix := "event:%s:" % String(card.get("id", ""))
	for raw_fact: Variant in Array(context.get("history_facts", [])):
		if String(raw_fact).begins_with(history_prefix):
			occurrences += 1
	var max_occurrences := int(card.get("max_occurrences", 1))
	if occurrences >= max_occurrences:
		reasons.append({
			"code": "max_occurrences_reached",
			"message": "Ситуация уже исчерпана в этой жизни",
			"occurrences": occurrences,
			"max_occurrences": max_occurrences,
		})
	var conditions := ConditionEvaluator.evaluate_all(
		context,
		Array(card.get("conditions", []))
	)
	for raw_reason: Variant in Array(conditions.get("reasons", [])):
		reasons.append(raw_reason)
	var luck := int(
		Dictionary(Dictionary(context.get("actor", {})).get(
			"characteristics",
			{}
		)).get("luck", 5)
	)
	var base_weight := int(card.get("base_weight", 1))
	var luck_bias := int(card.get("luck_bias", 0))
	var luck_delta := luck - 5
	var adjusted_weight := maxi(base_weight + luck_bias * luck_delta, 0)
	if adjusted_weight <= 0:
		reasons.append({
			"code": "zero_weight",
			"message": "Удача уменьшила вес до нуля",
		})
	return {
		"card_id": String(card.get("id", "")),
		"included": reasons.is_empty(),
		"reasons": reasons,
		"condition_checks": Array(conditions.get("checks", [])).duplicate(true),
		"tone": String(card.get("tone", "neutral")),
		"base_weight": base_weight,
		"luck": luck,
		"luck_bias": luck_bias,
		"luck_delta": luck_delta,
		"luck_adjustment": luck_bias * luck_delta,
		"adjusted_weight": adjusted_weight,
		"family_id": String(card.get("family_id", "")),
		"occurrences": occurrences,
		"max_occurrences": max_occurrences,
	}


static func _find_card(catalog: Dictionary, card_id: String) -> Dictionary:
	for raw_card: Variant in Array(catalog.get("cards", [])):
		if raw_card is Dictionary and String(raw_card.get("id", "")) == card_id:
			return Dictionary(raw_card).duplicate(true)
	return {}
