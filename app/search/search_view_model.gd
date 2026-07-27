class_name SearchViewModel
extends RefCounted

const PsycheScaleScript := preload("res://core/state/psyche_scale.gd")

const SearchModelMapper := preload("res://app/search/search_model_mapper.gd")


static func build(
	raw_model: Dictionary,
	shell_model: Dictionary,
	reduced_motion: bool,
	font_scale: float,
	psyche_effect_mode: String = "full"
) -> Dictionary:
	var snapshot: Dictionary = Dictionary(raw_model.get("snapshot", {})).duplicate(true)
	var template: Dictionary = Dictionary(raw_model.get("template", {})).duplicate(true)
	var map_model: Dictionary = Dictionary(
		snapshot.get("map", template.get("map", {}))
	).duplicate(true)
	var player: Dictionary = Dictionary(snapshot.get("player", {})).duplicate(true)
	var risk_source: Dictionary = Dictionary(
		raw_model.get("risk", snapshot.get("risk", {}))
	).duplicate(true)
	var raw_objects: Array = Array(
		raw_model.get("objects", snapshot.get("objects", []))
	).duplicate(true)
	var path: Array = Array(
		raw_model.get("path", player.get("planned_path", []))
	).duplicate(true)
	return {
		"header": _header(shell_model),
		"zone_id": String(raw_model.get(
			"zone_id",
			snapshot.get("template_id", template.get("id", ""))
		)),
		"title": String(template.get("title", "Поиск")),
		# The place is already described on the card that opens the zone. Inside
		# it, the rule the player needs is the one about time.
		"subtitle": String(raw_model.get(
			"subtitle",
			"Ходьба не тратит игровое время. Его тратят только подтверждённые решения."
		)),
		"background_path": String(map_model.get(
			"asset",
			"res://assets/search/underpass_service_yard_v1.png"
		)),
		"world_size": Array(map_model.get("size", [1648, 960])).duplicate(),
		"hero": player,
		"path": path,
		"objects": SearchModelMapper.objects(
			raw_objects,
			raw_model.get("approaches", {})
		),
		"risk": SearchModelMapper.risk(risk_source, raw_model),
		"loot_tray": SearchModelMapper.loot(
			_loot_source(raw_model, snapshot)
		),
		"quick_search": _quick_search_model(raw_model.get("quick_search", {})),
		"psyche_intensity": _effective_psyche_intensity(
			raw_model,
			shell_model,
			psyche_effect_mode
		),
		"reduced_motion": reduced_motion,
		"font_scale": clampf(font_scale, 1.0, 2.0),
	}


static func _loot_source(raw_model: Dictionary, snapshot: Dictionary) -> Array:
	if raw_model.has("loot_tray"):
		return Array(raw_model.get("loot_tray", [])).duplicate(true)
	return Array(snapshot.get("ground_items", [])).duplicate(true)


static func _quick_search_model(raw_value: Variant) -> Dictionary:
	if not raw_value is Dictionary:
		return {"visible": false, "enabled": false, "blocked_reason": ""}
	var model: Dictionary = Dictionary(raw_value).duplicate(true)
	return {
		"visible": bool(model.get("visible", not model.is_empty())),
		"enabled": bool(model.get("enabled", false)),
	}


static func _effective_psyche_intensity(
	raw_model: Dictionary,
	shell_model: Dictionary,
	mode: String
) -> float:
	if raw_model.has("psyche_intensity"):
		return clampf(float(raw_model.get("psyche_intensity", 0.0)), 0.0, 1.0)
	var meters: Dictionary = Dictionary(
		Dictionary(shell_model.get("status", {})).get("meters", {})
	)
	var intensity := PsycheScaleScript.filter_for(int(meters.get("mental_state", 50)))
	match mode:
		"off":
			return 0.0
		"reduced":
			return intensity * 0.45
		_:
			return intensity


static func _header(shell_model: Dictionary) -> Dictionary:
	var status: Dictionary = Dictionary(shell_model.get("status", {}))
	var calendar: Dictionary = Dictionary(status.get("calendar", {}))
	var minute := int(calendar.get("minute_of_day", 0))
	return {
		"district_title": "ПРИРЕЧНЫЙ РАЙОН",
		"location_title": String(
			Dictionary(shell_model.get("location", {})).get("title", "Поиск")
		),
		"date_text": "%02d.%02d.%04d" % [
			int(calendar.get("day", 1)),
			int(calendar.get("month", 1)),
			int(calendar.get("year", 1980)),
		],
		"time_text": "%02d:%02d" % [minute / 60, minute % 60],
		"money": int(status.get("money", 0)),
		"show_settings": false,
	}
