extends SceneTree

const SearchModels := preload("res://app/search/search_view_model.gd")
const ZoneCatalog := preload("res://game/search/search_zone_catalog.gd")
const SnapshotGenerator := preload("res://game/search/search_snapshot_generator.gd")


func _init() -> void:
	var loaded := ZoneCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		_fail("template fixture did not load")
		return
	var template: Dictionary = loaded["template"]
	var generated := SnapshotGenerator.generate(
		template,
		73_001,
		1,
		{"luck": 6, "depletion": 0, "weather": "dry", "time_band": "day"}
	)
	if not bool(generated.get("ok", false)):
		_fail("snapshot fixture did not generate")
		return
	var snapshot: Dictionary = generated["snapshot"]
	snapshot["risk"] = {
		"noise": 3,
		"trespass": 2,
		"repeated_attempts": 1,
	}
	var first_object: Dictionary = Array(snapshot["objects"])[0]
	var first_loot: Dictionary = Array(first_object["contents"])[0].duplicate(true)
	var raw := {
		"template": template,
		"snapshot": snapshot,
		"path": [[823, 912], [823, 742], [735, 552]],
		"approaches": {
			"locked_shed": {
				"study_lock": {
					"enabled": false,
					"blocked_reasons": ["Интеллект: нужно 7, сейчас 6"],
					"costs": {
						"minutes": 18,
						"energy": 2,
						"noise": 2,
						"trespass": 2,
					},
				},
			},
		},
		"loot_tray": [first_loot],
		"quick_search": {
			"visible": true,
			"enabled": false,
			"blocked_reason": "Сначала изучите двор вручную.",
		},
	}
	var shell := {
		"status": {
			"money": 0,
			"meters": {"tension": 80, "morale": 20},
			"calendar": {
				"day": 1,
				"month": 9,
				"year": 1970,
				"minute_of_day": 480,
			},
		},
		"location": {"title": "Старый переход"},
	}
	var before := raw.duplicate(true)
	var model := SearchModels.build(raw, shell, true, 2.0, "reduced")
	_expect(raw == before, "builder mutated domain data")
	_expect(
		model.get("background_path") == template["map"]["asset"],
		"map.asset was not mapped"
	)
	_expect(
		Array(model.get("world_size", [])) == [1648, 960],
		"map.size array was not mapped"
	)
	_expect(
		Array(Dictionary(model.get("hero", {})).get("position", [])) == [823, 912],
		"snapshot.player.position array was not preserved"
	)
	_expect(Array(model.get("objects", [])).size() == 8, "snapshot objects were lost")
	var hidden := _object(model, "hidden_newspapers")
	_expect(not bool(hidden.get("revealed", true)), "concealed object became visible")
	var locked := _object(model, "locked_shed")
	var approach := _approach(locked, "study_lock")
	_expect(not bool(approach.get("enabled", true)), "blocked approach became enabled")
	_expect(
		String(approach.get("cost_text", "")).contains("18 мин."),
		"exact duration was not exposed"
	)
	_expect(
		String(approach.get("cost_text", "")).contains("Проникновение: +2"),
		"exact trespass cost was not exposed"
	)
	_expect(
		Array(approach.get("blocked_reasons", [])).size() == 1,
		"blocked reason was not preserved"
	)
	_expect(not locked.has("contents"), "pre-rolled loot leaked through object model")
	var risk: Dictionary = model["risk"]
	_expect(int(risk.get("noise", -1)) == 3, "noise risk was lost")
	_expect(int(risk.get("trespass", -1)) == 2, "trespass risk was lost")
	_expect(
		int(risk.get("repeated_attempts", -1)) == 1,
		"repeated-attempt risk was lost"
	)
	var tray: Array = model["loot_tray"]
	_expect(not tray.is_empty(), "loot tray did not map the latest find")
	if not tray.is_empty():
		_expect(
			String(Dictionary(tray[0]).get("stack_id", "")).begins_with("open_dumpster:loot:"),
			"loot_id did not become a stable pickup id"
		)
		_expect(
			not String(Dictionary(tray[0]).get("mass_text", "")).is_empty(),
			"loot mass was not formatted"
		)
	_expect(
		is_equal_approx(float(model.get("psyche_intensity", -1.0)), 0.36),
		"reduced psyche intensity was not calculated"
	)
	_expect(
		not bool(Dictionary(model["quick_search"]).get("enabled", true)),
		"quick-search lock was not preserved"
	)
	if _failures.is_empty():
		print("M3D SEARCH VIEW-MODEL TEST PASSED: flat snapshot, costs, risk and loot")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M3D SEARCH VIEW-MODEL: %s" % failure)
	quit(1)


var _failures: Array[String] = []


func _object(model: Dictionary, object_id: String) -> Dictionary:
	for raw_object: Variant in Array(model.get("objects", [])):
		if raw_object is Dictionary and String(raw_object.get("id", "")) == object_id:
			return raw_object
	return {}


func _approach(object: Dictionary, approach_id: String) -> Dictionary:
	for raw_approach: Variant in Array(object.get("approaches", [])):
		if raw_approach is Dictionary and String(raw_approach.get("id", "")) == approach_id:
			return raw_approach
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	push_error("M3D SEARCH VIEW-MODEL: %s" % message)
	quit(1)
