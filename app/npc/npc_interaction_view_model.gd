class_name NpcInteractionViewModel
extends RefCounted

## Pure presentation boundary for one persistent NPC encounter. The producer
## supplies semantic IDs and observed text; this adapter never infers hidden
## relationship facts or interaction icons from Russian copy.


static func build(raw: Dictionary, reduced_motion: bool = false) -> Dictionary:
	var relationship := _relationship(raw)
	return {
		"npc_id": String(raw.get("npc_id", "")),
		"name": _text(raw.get("name", "Неизвестный человек"), "Неизвестный человек"),
		"role": _text(raw.get("role", "")),
		"portrait_path": _text(raw.get("portrait_path", "")),
		"portrait_key": _text(raw.get("portrait_key", "")),
		"portrait_crop_mode": _crop_mode(raw.get("portrait_crop_mode", "focus_cover")),
		"portrait_focus": _portrait_focus(raw.get("portrait_focus", {})),
		"presence_text": _text(raw.get("presence_text", "Сейчас здесь"), "Сейчас здесь"),
		"relationship_label": relationship["label"],
		"relationship_value": relationship["value"],
		"reactions": _lines(raw.get("reactions", [])),
		"outcome": _outcome(raw.get("outcome", "")),
		"interactions": _interactions(raw.get("interactions", [])),
		"expected_revision": int(raw.get("expected_revision", raw.get("revision", 0))),
		"reduced_motion": reduced_motion,
	}


static func _crop_mode(value: Variant) -> String:
	var mode := String(value)
	return mode if mode == "focus_cover" else "focus_cover"


static func _portrait_focus(value: Variant) -> Dictionary:
	var focus := Vector2(0.5, 0.35)
	if value is Vector2:
		focus = value
	elif value is Dictionary:
		var source: Dictionary = value
		focus = Vector2(
			float(source.get("x", focus.x)),
			float(source.get("y", focus.y))
		)
	elif value is Array and Array(value).size() >= 2:
		focus = Vector2(float(Array(value)[0]), float(Array(value)[1]))
	return {
		"x": clampf(focus.x, 0.0, 1.0),
		"y": clampf(focus.y, 0.0, 1.0),
	}


static func _relationship(raw: Dictionary) -> Dictionary:
	var nested: Dictionary = (
		Dictionary(raw.get("relationship", {}))
		if raw.get("relationship", {}) is Dictionary
		else {}
	)
	return {
		"label": _text(
			raw.get("relationship_label", nested.get("label", "Отношение")),
			"Отношение"
		),
		"value": _text(
			raw.get("relationship_value", nested.get("value", "Пока неясно")),
			"Пока неясно"
		),
	}


static func _interactions(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_interaction: Variant in raw_value:
		if not raw_interaction is Dictionary:
			continue
		var source: Dictionary = raw_interaction
		var interaction_id := String(
			source.get("interaction_id", source.get("id", ""))
		).strip_edges()
		if interaction_id.is_empty():
			continue
		var available := bool(source.get("available", true))
		var reasons := _lines(source.get("reasons", []))
		var duration_value: Variant = source.get(
			"duration_minutes", source.get("duration", 0)
		)
		if duration_value is Dictionary:
			duration_value = Dictionary(duration_value).get("minutes", 0)
		var duration := maxi(int(duration_value), 0)
		var tokens: Array[Dictionary] = []
		if duration > 0:
			tokens.append({
				"icon_id": &"meta_time",
				"text": "%d мин" % duration,
				"accessible_text": "%d %s" % [duration, _minute_word(duration)],
			})
		result.append({
			"id": interaction_id,
			"title": _text(source.get("title", "Поговорить"), "Поговорить"),
			"description": _text(source.get("description", "")),
			"enabled": available,
			"locked_reason": "\n".join(PackedStringArray(reasons)),
			"category_icon_id": StringName(source.get(
				"icon_id",
				source.get("category_icon_id", &"action_talk")
			)),
			"variant": StringName(source.get("variant", &"normal")),
			"meta_tokens": tokens,
		})
	return result


static func _outcome(value: Variant) -> String:
	if value is Dictionary:
		return _text(Dictionary(value).get("text", Dictionary(value).get("summary", "")))
	return _text(value)


static func _lines(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			var line := _text(
				Dictionary(entry).get(
					"text", Dictionary(entry).get("message", "")
				) if entry is Dictionary else entry
			)
			if not line.is_empty():
				result.append(line)
	else:
		var line := _text(value)
		if not line.is_empty():
			result.append(line)
	return result


static func _text(value: Variant, fallback: String = "") -> String:
	if value == null:
		return fallback
	var result := String(value).strip_edges()
	return fallback if result.is_empty() else result


static func _minute_word(value: int) -> String:
	var last_two := value % 100
	if last_two >= 11 and last_two <= 14:
		return "минут"
	match value % 10:
		1:
			return "минута"
		2, 3, 4:
			return "минуты"
		_:
			return "минут"
