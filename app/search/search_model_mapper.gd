class_name SearchModelMapper
extends RefCounted

const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")


static func objects(raw_objects: Array, raw_overrides: Variant) -> Array:
	var result: Array = []
	var overrides := _approach_overrides(raw_overrides)
	for raw_object: Variant in raw_objects:
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = Dictionary(raw_object).duplicate(true)
		var object_id := String(object.get("id", ""))
		if object_id.is_empty():
			continue
		var interacted := bool(object.get("interacted", false))
		result.append({
			"id": object_id,
			"title": String(object.get("title", object_id)),
			"type": String(object.get("type", "open")),
			"position": Array(object.get("position", [0, 0])).duplicate(),
			"interaction_radius": int(object.get("interaction_radius", 112)),
			"state": String(object.get("state", "available")),
			"revealed": bool(object.get("revealed", object.get("type", "") != "hidden")),
			"interacted": interacted,
			"approaches": _approach_models(
				Array(object.get("approaches", [])),
				Dictionary(overrides.get(object_id, {})),
				interacted
			),
		})
	return result


static func risk(source: Dictionary, raw_model: Dictionary) -> Dictionary:
	var noise := maxi(int(source.get("noise", 0)), 0)
	var trespass := maxi(int(source.get("trespass", 0)), 0)
	var repeated := maxi(int(source.get("repeated_attempts", 0)), 0)
	var derived_score := clampi((noise + trespass + repeated) * 5, 0, 100)
	var score := clampi(int(source.get("score", derived_score)), 0, 100)
	var warning := maxi(int(raw_model.get("warning_threshold", 35)), 1)
	return {
		"score": score,
		"noise": noise,
		"trespass": trespass,
		"repeated_attempts": repeated,
		"warning_threshold": warning,
		"label": (
			"Высокий"
			if score >= warning
			else "Растёт" if score >= warning / 2 else "Низкий"
		),
	}


static func loot(raw_loot: Array) -> Array:
	var result: Array = []
	for raw_entry: Variant in raw_loot:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = Dictionary(raw_entry).duplicate(true)
		var definition: Variant = ItemCatalogScript.definition(String(entry.get("item_id", "")))
		var quantity := int(entry.get("quantity", 1))
		entry["stack_id"] = String(entry.get(
			"stack_id",
			entry.get("loot_id", entry.get("ground_id", ""))
		))
		entry["target_container_id"] = String(entry.get("target_container_id", ""))
		entry["pickup_enabled"] = (
			bool(entry.get("pickup_enabled", true))
			and not String(entry["target_container_id"]).is_empty()
		)
		if not bool(entry["pickup_enabled"]):
			entry["pickup_blocked_reason"] = String(entry.get(
				"pickup_blocked_reason",
				"Выберите место для находки в инвентаре."
			))
		entry["title"] = definition.title()
		entry["mass_text"] = _mass_text(definition.mass_grams() * quantity)
		entry["volume_text"] = _volume_text(definition.volume_ml() * quantity)
		result.append(entry)
	return result


static func _approach_models(
	raw_approaches: Array,
	overrides: Dictionary,
	interacted: bool
) -> Array:
	var result: Array = []
	for raw_approach: Variant in raw_approaches:
		if not raw_approach is Dictionary:
			continue
		var approach: Dictionary = Dictionary(raw_approach).duplicate(true)
		var approach_id := String(approach.get("id", ""))
		if approach_id.is_empty():
			continue
		var override: Dictionary = Dictionary(overrides.get(approach_id, {}))
		for key: Variant in override:
			approach[key] = override[key]
		var costs := _cost_model(approach)
		var enabled := bool(approach.get(
			"enabled",
			approach.get("allowed", true)
		)) and not interacted
		var blocked_reasons := _string_array(approach.get("blocked_reasons", []))
		if interacted:
			blocked_reasons = ["Этот объект уже осмотрен."]
		elif not enabled and blocked_reasons.is_empty():
			blocked_reasons = ["Этот способ сейчас недоступен."]
		result.append({
			"id": approach_id,
			"title": String(approach.get("title", approach_id)),
			"description": String(approach.get("description", "")),
			"enabled": enabled,
			"blocked_reasons": blocked_reasons,
			"costs": costs,
			"cost_rows": _cost_rows(costs),
			"cost_text": _cost_text(costs),
		})
	return result


static func _cost_model(approach: Dictionary) -> Dictionary:
	var nested: Dictionary = Dictionary(approach.get("costs", {}))
	var raw_risk: Dictionary = Dictionary(approach.get("risk", {}))
	return {
		"minutes": int(nested.get("minutes", approach.get("duration_minutes", 0))),
		"energy": int(nested.get("energy", approach.get("energy_cost", 0))),
		"noise": int(nested.get("noise", raw_risk.get("noise", 0))),
		"trespass": int(nested.get("trespass", raw_risk.get("trespass", 0))),
		"repeated": int(nested.get(
			"repeated",
			raw_risk.get("repeated_attempts", 0)
		)),
	}


static func _cost_rows(costs: Dictionary) -> Array:
	var rows: Array = []
	var minutes := int(costs.get("minutes", 0))
	var energy := int(costs.get("energy", 0))
	var noise := int(costs.get("noise", 0))
	var trespass := int(costs.get("trespass", 0))
	var repeated := int(costs.get("repeated", 0))
	if minutes > 0:
		rows.append({"label": "Время", "value": "%d мин." % minutes, "tone": "neutral"})
	if energy > 0:
		rows.append({"label": "Энергия", "value": "−%d" % energy, "tone": "danger"})
	if noise != 0:
		rows.append({"label": "Шум", "value": "%+d" % noise, "tone": "warning"})
	if trespass != 0:
		rows.append({"label": "Проникновение", "value": "%+d" % trespass, "tone": "danger"})
	if repeated != 0:
		rows.append({"label": "Повторная попытка", "value": "%+d" % repeated, "tone": "warning"})
	return rows


static func _cost_text(costs: Dictionary) -> String:
	var parts := PackedStringArray()
	for raw_row: Variant in _cost_rows(costs):
		var row: Dictionary = raw_row
		parts.append("%s: %s" % [String(row["label"]), String(row["value"])])
	return "  ·  ".join(parts)


static func _approach_overrides(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw_value is Dictionary:
		for raw_object_id: Variant in raw_value:
			result[String(raw_object_id)] = _index_approaches(raw_value[raw_object_id])
	elif raw_value is Array:
		for raw_override: Variant in raw_value:
			if not raw_override is Dictionary:
				continue
			var override: Dictionary = raw_override
			var object_id := String(override.get("object_id", ""))
			var approach_id := String(override.get("id", ""))
			if object_id.is_empty() or approach_id.is_empty():
				continue
			if not result.has(object_id):
				result[object_id] = {}
			result[object_id][approach_id] = override.duplicate(true)
	return result


static func _index_approaches(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw_value is Dictionary:
		for raw_id: Variant in raw_value:
			if raw_value[raw_id] is Dictionary:
				result[String(raw_id)] = Dictionary(raw_value[raw_id]).duplicate(true)
	elif raw_value is Array:
		for raw_entry: Variant in raw_value:
			if raw_entry is Dictionary:
				var entry: Dictionary = raw_entry
				var approach_id := String(entry.get("id", ""))
				if not approach_id.is_empty():
					result[approach_id] = entry.duplicate(true)
	return result


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is String and not String(value).strip_edges().is_empty():
		result.append(String(value))
	elif value is Array:
		for raw_entry: Variant in value:
			var entry := String(raw_entry).strip_edges()
			if not entry.is_empty():
				result.append(entry)
	return result


static func _mass_text(grams: int) -> String:
	return (
		("%.1f кг" % (float(grams) / 1000.0)).replace(".", ",")
		if grams >= 1000 else "%d г" % grams
	)


static func _volume_text(milliliters: int) -> String:
	return (
		("%.1f л" % (float(milliliters) / 1000.0)).replace(".", ",")
		if milliliters >= 1000 else "%d мл" % milliliters
	)
