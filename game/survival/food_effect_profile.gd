class_name FoodEffectProfile
extends RefCounted

## Validates and previews authored food effects. The profile compiles to the
## same data-only effects used by other domain transactions; it does not know
## about inventory, shops, screens or a particular item catalog.

const SCHEMA_VERSION := 1
const METER_LABELS := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"mental_state": "Психика",
}


static func validate(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if typeof(profile.get("schema_version", null)) != TYPE_INT or int(profile.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("schema_version профиля еды должен быть равен 1")
	for key: String in ["profile_id", "title"]:
		if typeof(profile.get(key, null)) != TYPE_STRING or String(profile.get(key, "")).strip_edges().is_empty():
			errors.append("%s обязателен" % key)
	if typeof(profile.get("consumption_minutes", null)) != TYPE_INT:
		errors.append("consumption_minutes должен быть целым числом")
	elif int(profile["consumption_minutes"]) < 0 or int(profile["consumption_minutes"]) > 120:
		errors.append("consumption_minutes находится вне диапазона 0–120")
	if not profile.get("effects", null) is Array or Array(profile.get("effects", [])).is_empty():
		errors.append("effects должен быть непустым массивом")
	else:
		var seen: Dictionary = {}
		var beneficial := false
		for index: int in Array(profile["effects"]).size():
			var raw_effect: Variant = profile["effects"][index]
			if not raw_effect is Dictionary:
				errors.append("effects[%d] должен быть объектом" % index)
				continue
			var effect: Dictionary = raw_effect
			var meter_id := String(effect.get("id", ""))
			if effect.get("type") != "change_state" or meter_id not in METER_LABELS:
				errors.append("effects[%d] должен менять известный показатель" % index)
				continue
			if seen.has(meter_id):
				errors.append("показатель %s указан дважды" % meter_id)
			seen[meter_id] = true
			if typeof(effect.get("delta", null)) != TYPE_INT or int(effect.get("delta", 0)) == 0:
				errors.append("effects[%d].delta должен быть ненулевым целым числом" % index)
				continue
			var delta := int(effect["delta"])
			if delta < -100 or delta > 100:
				errors.append("effects[%d].delta находится вне диапазона" % index)
			beneficial = beneficial or (meter_id == "hunger" and delta < 0)
			beneficial = beneficial or (meter_id in ["health", "energy", "mental_state"] and delta > 0)
		if not beneficial:
			errors.append("еда должна иметь хотя бы один полезный эффект")
	return {"ok": errors.is_empty(), "errors": errors}


static func command_effects(profile: Dictionary) -> Dictionary:
	var validation := validate(profile)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "code": "invalid_food_profile", "error": str(validation["errors"]), "effects": []}
	var effects: Array = []
	var minutes := int(profile["consumption_minutes"])
	if minutes > 0:
		effects.append({
			"type": "advance_time",
			"minutes": minutes,
			"reason": "Приём пищи: %s" % String(profile["title"]),
		})
	for raw_effect: Variant in Array(profile["effects"]):
		effects.append(Dictionary(raw_effect).duplicate(true))
	return {"ok": true, "code": "ok", "error": "", "effects": effects}


static func describe(profile: Dictionary) -> Dictionary:
	var validation := validate(profile)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "code": "invalid_food_profile", "error": str(validation["errors"])}
	var tokens: Array = []
	var parts: Array[String] = []
	for raw_effect: Variant in Array(profile["effects"]):
		var effect: Dictionary = raw_effect
		var meter_id := String(effect["id"])
		var delta := int(effect["delta"])
		var signed := "%+d" % delta
		var text := "%s %s" % [String(METER_LABELS[meter_id]), signed]
		tokens.append({
			"meter_id": meter_id,
			"label": METER_LABELS[meter_id],
			"delta": delta,
			"text": text,
			"accessible_text": text,
		})
		parts.append(text)
	var minutes := int(profile["consumption_minutes"])
	if minutes > 0:
		parts.append("%d мин" % minutes)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"profile_id": String(profile["profile_id"]),
		"title": String(profile["title"]),
		"minutes": minutes,
		"tokens": tokens,
		"summary_ru": " · ".join(parts),
	}


static func preview(profile: Dictionary, meters: Dictionary) -> Dictionary:
	var validation := validate(profile)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "code": "invalid_food_profile", "error": str(validation["errors"])}
	var result := meters.duplicate(true)
	var changes: Array = []
	for raw_effect: Variant in Array(profile["effects"]):
		var effect: Dictionary = raw_effect
		var meter_id := String(effect["id"])
		if not result.has(meter_id) or typeof(result[meter_id]) != TYPE_INT:
			return {"ok": false, "code": "invalid_meters", "error": "Отсутствует показатель %s" % meter_id}
		var before := int(result[meter_id])
		var after := clampi(before + int(effect["delta"]), 0, 100)
		result[meter_id] = after
		changes.append({"meter_id": meter_id, "before": before, "after": after, "delta": after - before})
	return {"ok": true, "code": "ok", "error": "", "meters": result, "changes": changes}
