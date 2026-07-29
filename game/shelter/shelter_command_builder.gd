class_name ShelterCommandBuilder
extends RefCounted

## Builds a data-only, optimistic command for the shared session transaction.
##
## Confirmation is explicit. Preparing a command never mutates RunState,
## GameSession, WorldState or the input snapshots.

const Resolver := preload("res://game/shelter/shelter_resolver.gd")
const ConditionScript := preload("res://core/rules/condition.gd")
const EffectScript := preload("res://core/rules/effect.gd")
const COMMAND_SCHEMA_VERSION := 1

## Sleep costs no energy — it is what the shelter's own restorative effects are
## measured against. Hunger keeps running: a person does get hungry asleep.
const SLEEP_SURVIVAL_PROFILE := {"energy_drain_units_per_minute": 0}


static func prepare(
	catalog: Dictionary,
	shelter_id: String,
	context: Dictionary,
	command_id: String,
	confirmed: bool
) -> Dictionary:
	var resolved := Resolver.resolve_one(catalog, shelter_id, context)
	if not bool(resolved.get("ok", false)):
		return resolved
	var option: Dictionary = resolved["option"]
	if not confirmed:
		return {
			"ok": false,
			"code": "confirmation_required",
			"error": "Подтвердите выбор ночлега.",
			"preview": option.duplicate(true),
		}
	var normalized_command_id := command_id.strip_edges()
	if normalized_command_id.is_empty() or normalized_command_id.length() > 160:
		return _failure("invalid_command_id", "Команда ночлега должна иметь стабильный command_id.")
	if not bool(option.get("available", false)):
		return {
			"ok": false,
			"code": "shelter_blocked",
			"error": "Этот ночлег сейчас недоступен.",
			"blocked_reasons": Array(option.get("blocked_reasons", [])).duplicate(true),
		}
	var conditions: Array = []
	var effects: Array = []
	var price := int(option["price_arden"])
	if String(option.get("shelter_id", "")) in Array(context.get("rent_paid_shelter_ids", [])):
		price = 0
	if price > 0:
		conditions.append(ConditionScript.with_reason(
			ConditionScript.money(price),
			"Нужно не менее %d арденов." % price
		))
	effects.append(EffectScript.advance_time(
		int(option["duration_minutes"]),
		"Сон: %s" % String(option["title"]),
		{
			"activity_kind": "sleep",
			"shelter_id": shelter_id,
			"wake_at": Dictionary(option["wake_at"]).duplicate(true),
		}
	))
	if price > 0:
		effects.append(EffectScript.change_money(-price))
	for meter_id: String in GameRules.METER_KEYS:
		if Dictionary(option["meter_effects"]).has(meter_id):
			effects.append(EffectScript.change_state(
				StringName(meter_id),
				int(option["meter_effects"][meter_id])
			))
	var calendar_data: Dictionary = context["calendar"]
	return {
		"ok": true,
		"code": "ok",
		"command": {
			"schema_version": COMMAND_SCHEMA_VERSION,
			"command_id": normalized_command_id,
			"command_kind": "sleep",
			# A night is not twelve hours of standing about. Without this the
			# passage burned energy all night and only handed the rest back at
			# the end, so going to bed tired was punished as if the hero had
			# stayed awake — and the deprivation it caused could kill him.
			"survival_profile": SLEEP_SURVIVAL_PROFILE.duplicate(true),
			"source_id": shelter_id,
			"id": "sleep_at_shelter",
			"option_id": shelter_id,
			"title": "Ночлег",
			"option_title": String(option["title"]),
			"conditions": conditions,
			"effects": effects,
			"expected": {
				"catalog_version": int(resolved["catalog_version"]),
				"location_id": String(context["location_id"]),
				"calendar_stamp": Dictionary(calendar_data["stamp"]).duplicate(true),
			},
			"result_preview": {
				"price_arden": price,
				"duration_minutes": int(option["duration_minutes"]),
				"wake_at": Dictionary(option["wake_at"]).duplicate(true),
				"meter_effects": Dictionary(option["meter_effects"]).duplicate(true),
			},
		},
	}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
