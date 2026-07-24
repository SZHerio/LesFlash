extends SceneTree

const RunStateScript := preload("res://core/state/run_state.gd")
const CatalogScript := preload("res://game/search/search_zone_catalog.gd")
const ContentValidator := preload("res://game/search/search_content_validator.gd")
const TemplateValidator := preload("res://game/search/search_template_validator.gd")
const SnapshotGenerator := preload("res://game/search/search_snapshot_generator.gd")
const SnapshotValidator := preload("res://game/search/search_snapshot_validator.gd")
const Pathfinder := preload("res://game/search/search_pathfinder.gd")

var _failures: Array[String] = []
var _tests_run := 0
var _current_test := ""
var _template: Dictionary = {}


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if bool(loaded.get("ok", false)):
		_template = Dictionary(loaded["template"]).duplicate(true)
	else:
		_failures.append("catalog bootstrap — %s" % str(loaded.get("errors", [])))
	_run_test("versioned template and authored content validate", _test_catalog)
	_run_test("generation resolves immutable deterministic contents", _test_determinism)
	_run_test("visit index owns a distinct search stream", _test_different_visit)
	_run_test("search generation never consumes the run RNG", _test_main_rng_unchanged)
	_run_test("every authored object is reachable", _test_reachability)
	_run_test("invalid graph and content references are rejected", _test_invalid_references)
	_run_test("snapshot validator rejects corrupted resolved loot", _test_snapshot_corruption)

	if _failures.is_empty():
		print("M3D SEARCH DOMAIN TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3D SEARCH DOMAIN TESTS FAILED: %d failure(s) across %d test(s)" % [
		_failures.size(),
		_tests_run,
	])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run_test(test_name: String, test_method: Callable) -> void:
	_tests_run += 1
	_current_test = test_name
	var before := _failures.size()
	test_method.call()
	print("PASS: %s" % test_name if _failures.size() == before else "FAIL: %s" % test_name)


func _test_catalog() -> void:
	_expect(not _template.is_empty(), "default template must load")
	if _template.is_empty():
		return
	var validation := TemplateValidator.validate(_template)
	_expect(bool(validation.get("ok", false)), "template must validate: %s" % str(validation.get("errors", [])))
	_expect_equal(_template.get("schema_version"), 1, "catalog schema must be explicit")
	_expect_equal(_template.get("template_version"), 1, "template version must be explicit")
	_expect_equal(_template.get("id"), "underpass_service_yard", "template id must remain stable")
	var map_data: Dictionary = _template["map"]
	_expect_equal(map_data.get("size"), [1648, 960], "map coordinates must match the authored illustration")
	_expect(FileAccess.file_exists(String(map_data.get("asset", ""))), "authored map asset must exist")

	var objects: Array = _template["objects"]
	_expect_equal(objects.size(), 8, "first search zone must contain eight authored objects")
	var types: Dictionary = {}
	for raw_object: Variant in objects:
		var object: Dictionary = raw_object
		types[String(object["type"])] = true
		_expect(not Array(object["approaches"]).is_empty(), "%s must expose an explicit decision" % object["id"])
		for raw_approach: Variant in Array(object["approaches"]):
			var approach: Dictionary = raw_approach
			_expect(int(approach["duration_minutes"]) > 0, "interaction time must be previewable")
			_expect(int(approach["energy_cost"]) >= 0, "interaction energy cost must be previewable")
			_expect(approach["conditions"] is Array, "interaction conditions must remain data")
	for object_type: String in ContentValidator.OBJECT_TYPES:
		_expect(types.has(object_type), "authored map must cover object type %s" % object_type)
	_expect_equal(Dictionary(_template["loot_tables"]).size(), 8, "each object family must use a declared loot table")


func _test_determinism() -> void:
	if _template.is_empty():
		return
	var first := SnapshotGenerator.generate(_template, 81_001, 1, {"luck": 6, "weather": "dry"})
	var second := SnapshotGenerator.generate(_template, 81_001, 1, {"luck": 6, "weather": "dry"})
	_expect(bool(first.get("ok", false)), "first generation must succeed: %s" % str(first.get("errors", [])))
	_expect(bool(second.get("ok", false)), "second generation must succeed")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return
	var first_snapshot: Dictionary = first["snapshot"]
	var second_snapshot: Dictionary = second["snapshot"]
	_expect_equal(first_snapshot, second_snapshot, "same seed/context/visit must produce the same snapshot")
	_expect(
		bool(SnapshotValidator.validate(first_snapshot, _template).get("ok", false)),
		"generated snapshot must validate"
	)
	for raw_object: Variant in Array(first_snapshot["objects"]):
		var object: Dictionary = raw_object
		_expect(not Array(object["contents"]).is_empty(), "%s contents must be resolved on entry" % object["id"])
		for raw_loot: Variant in Array(object["contents"]):
			_expect(not bool(raw_loot.get("claimed", true)), "new resolved loot must be unclaimed")


func _test_different_visit() -> void:
	if _template.is_empty():
		return
	var first := SnapshotGenerator.generate(_template, 82_001, 1, {"luck": 5})
	var second := SnapshotGenerator.generate(_template, 82_001, 2, {"luck": 5})
	_expect(bool(first.get("ok", false)) and bool(second.get("ok", false)), "both visits must generate")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return
	var first_snapshot: Dictionary = first["snapshot"]
	var second_snapshot: Dictionary = second["snapshot"]
	_expect_equal(first_snapshot.get("visit_index"), 1, "first visit must retain its index")
	_expect_equal(second_snapshot.get("visit_index"), 2, "second visit must retain its index")
	_expect(
		String(Dictionary(first_snapshot["rng"])["seed"]) != String(Dictionary(second_snapshot["rng"])["seed"]),
		"different visits must derive different streams"
	)
	_expect(first_snapshot != second_snapshot, "different visits must not share a snapshot")


func _test_main_rng_unchanged() -> void:
	if _template.is_empty():
		return
	var state = RunStateScript.new(_build(), 83_001)
	var before: Dictionary = state.rng.to_dict()
	var generated := SnapshotGenerator.generate(
		_template,
		state.rng.seed,
		1,
		{"luck": state.get_characteristic("luck")}
	)
	_expect(bool(generated.get("ok", false)), "search snapshot must generate from immutable run seed")
	_expect_equal(state.rng.to_dict(), before, "generation must not read forward or reseed the run RNG")


func _test_reachability() -> void:
	if _template.is_empty():
		return
	var before := _template.duplicate(true)
	var spawn := String(Dictionary(_template["map"])["spawn_node"])
	for raw_object: Variant in Array(_template["objects"]):
		var object: Dictionary = raw_object
		var path := Pathfinder.find_path_to_object(_template, spawn, String(object["id"]))
		_expect(bool(path.get("ok", false)), "%s approach node must be reachable" % object["id"])
		if bool(path.get("ok", false)):
			var nodes: Array = path["nodes"]
			_expect_equal(nodes[0], spawn, "path must begin at spawn")
			_expect_equal(nodes[-1], object["approach_node"], "path must end at the authored approach")
			_expect(float(path["distance"]) >= 0.0, "path distance must be finite and nonnegative")
	var graph: Dictionary = _template["walk_graph"]
	_expect(Array(graph["nodes"]).size() >= 12, "walk graph must support a map larger than one screen")
	_expect(Array(graph["obstacles"]).size() >= 5, "authored obstacles must be persisted")
	_expect_equal(_template, before, "path previews must not mutate template data")


func _test_invalid_references() -> void:
	if _template.is_empty():
		return
	var bad_edge := _template.duplicate(true)
	bad_edge["walk_graph"]["edges"][0]["to"] = "missing_node"
	var validation := TemplateValidator.validate(bad_edge)
	_expect(not bool(validation.get("ok", true)), "unknown edge node must fail validation")
	_expect_error_contains(validation, "неизвестный узел")

	var bad_approach := _template.duplicate(true)
	bad_approach["objects"][0]["approach_node"] = "missing_node"
	validation = TemplateValidator.validate(bad_approach)
	_expect(not bool(validation.get("ok", true)), "unknown object approach node must fail validation")

	var bad_table := _template.duplicate(true)
	bad_table["objects"][0]["loot_table_id"] = "missing_table"
	validation = TemplateValidator.validate(bad_table)
	_expect(not bool(validation.get("ok", true)), "unknown loot table must fail validation")

	var bad_item := _template.duplicate(true)
	bad_item["loot_tables"]["dumpster_mixed"]["entries"][0]["item_id"] = "missing_item"
	validation = TemplateValidator.validate(bad_item)
	_expect(not bool(validation.get("ok", true)), "unknown item reference must fail validation")


func _test_snapshot_corruption() -> void:
	if _template.is_empty():
		return
	var generated := SnapshotGenerator.generate(_template, 84_001, 1, {"luck": 4})
	_expect(bool(generated.get("ok", false)), "snapshot fixture must generate")
	if not bool(generated.get("ok", false)):
		return
	var corrupted: Dictionary = Dictionary(generated["snapshot"]).duplicate(true)
	corrupted["objects"][0]["contents"][0]["item_id"] = "missing_item"
	var validation := SnapshotValidator.validate(corrupted, _template)
	_expect(not bool(validation.get("ok", true)), "unknown resolved item must invalidate snapshot")


func _expect_error_contains(validation: Dictionary, fragment: String) -> void:
	for raw_error: Variant in Array(validation.get("errors", [])):
		if String(raw_error).contains(fragment):
			return
	_expect(false, "expected an error containing «%s»: %s" % [fragment, str(validation.get("errors", []))])


func _build() -> Dictionary:
	return {"strength": 5, "charisma": 4, "intelligence": 4, "luck": 5}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current_test, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current_test,
			message,
			str(expected),
			str(actual),
		])
