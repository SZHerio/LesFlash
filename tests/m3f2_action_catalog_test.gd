extends SceneTree

const Catalog := preload("res://game/sandbox/sandbox_action_catalog.gd")
const Validator := preload("res://game/sandbox/sandbox_action_validator.gd")
const KnowledgeCatalog := preload("res://game/content/catalogs/knowledge_catalog.gd")
const JobCatalog := preload("res://game/content/catalogs/job_catalog.gd")
const ReputationCatalog := preload("res://game/content/catalogs/reputation_catalog.gd")
const StoreCatalog := preload("res://game/commerce/store_catalog.gd")
const SearchZoneCatalog := preload("res://game/search/search_zone_catalog.gd")
const IconRegistry := preload("res://ui/icons/icon_registry.gd")

## Underpass and the clinic yard each gained somewhere to practise what the
## skill catalog now says they teach: warming food and dressing hands at the
## pipes, helping in the queue at the clinic. Six of seven skills could not
## otherwise leave rank zero.
const EXPECTED_LOCATION_COUNTS := {
	"bus_depot": 2,
	"night_canteen": 3,
	"workshop_row": 2,
	"cathedral_steps": 2,
	"almshouse": 3,
	"pawn_row": 5,
	"underpass": 7,
	"market": 4,
	"station_square": 7,
	"recycling_point": 6,
	"clinic_yard": 6,
	"embankment": 4,
}

var _catalog: Dictionary = {}
var _reference_ids: Dictionary = {}
var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_reference_ids = _build_reference_ids()
	var loaded := Catalog.load_default(_reference_ids)
	if bool(loaded.get("ok", false)):
		_catalog = Dictionary(loaded.get("catalog", {}))
	else:
		_failures.append("catalog setup — %s" % str(loaded.get("errors", [])))
	_run("versioned catalog loads with twelve locations and 51 actions", _test_header_and_spread)
	_run("free-week activity coverage is complete", _test_activity_coverage)
	_run("only confirmed decisions carry duration", _test_time_contract)
	_run("all external IDs and semantic icons are canonical", _test_references)
	_run("intent payloads are exact typed packets", _test_intent_schema_failures)
	_run("time contract rejects ambiguous packets", _test_time_schema_failures)
	_run("catalog identity, uniqueness and location coverage are strict", _test_catalog_failures)
	_run("numeric fields reject non-integer values", _test_numeric_failure)
	_run("M3F.2 actions contain no NPC or executable content", _test_content_boundary)
	_run("lookup helpers and validation do not mutate source data", _test_purity_and_copies)
	_finish()


func _test_header_and_spread() -> void:
	_expect(_catalog.get("schema_version") == 1, "schema version must be 1")
	_expect(_catalog.get("catalog_id") == "riverside_sandbox_actions", "catalog ID")
	_expect(_catalog.get("catalog_version") == 1, "catalog version must be 1")
	_expect(_catalog.get("location_ids", []) == Validator.CANONICAL_LOCATION_IDS, "canonical location order")
	_expect(Array(_catalog.get("actions", [])).size() == 51, "the authored slice must contain 51 actions")
	for location_id: String in EXPECTED_LOCATION_COUNTS:
		var actions := Catalog.actions_for_location(_catalog, location_id)
		_expect(actions.size() == int(EXPECTED_LOCATION_COUNTS[location_id]), "%s action count" % location_id)


func _test_activity_coverage() -> void:
	var intent_counts: Dictionary = {}
	var store_ids: Dictionary = {}
	for raw_action: Variant in _catalog.get("actions", []):
		var action: Dictionary = raw_action
		var intent: Dictionary = action.get("intent", {})
		var intent_type := String(intent.get("type", ""))
		intent_counts[intent_type] = int(intent_counts.get(intent_type, 0)) + 1
		if intent_type == "open_store":
			store_ids[String(Dictionary(intent.get("payload", {})).get("store_id", ""))] = true
	_expect(int(intent_counts.get("inspect", 0)) >= 5, "reading and observation actions")
	_expect(int(intent_counts.get("enter_search", 0)) == 1, "one search mini-game entrance")
	_expect(int(intent_counts.get("consume_item", 0)) == 1, "food action")
	_expect(store_ids.size() == 4, "four distinct stores")
	_expect(int(intent_counts.get("open_recycling_sale", 0)) == 1, "recycling sale route")
	_expect(int(intent_counts.get("open_job", 0)) == 1, "work mini-game route")
	_expect(int(intent_counts.get("open_shelter", 0)) == 2, "shelter selection in two locations")
	_expect(int(intent_counts.get("travel", 0)) == 1, "local movement decision")
	_expect(int(intent_counts.get("perform_activity", 0)) >= 5, "ordinary confirmed activities")


func _test_time_contract() -> void:
	var confirmed := 0
	var immediate := 0
	for raw_action: Variant in _catalog.get("actions", []):
		var action: Dictionary = raw_action
		if String(action.get("confirmation", "")) == "required":
			confirmed += 1
			var duration: Dictionary = action.get("duration", {})
			_expect(duration.get("kind") == "fixed", "%s fixed duration" % action.get("action_id", ""))
			_expect(typeof(duration.get("minutes", null)) == TYPE_INT, "%s integer minutes" % action.get("action_id", ""))
		else:
			immediate += 1
			_expect(not action.has("duration"), "%s must not advance time" % action.get("action_id", ""))
	_expect(confirmed == 34, "thirty-four actions are confirmed decisions")
	_expect(immediate == 17, "seventeen actions only open or inspect content")


func _test_references() -> void:
	var validation := Validator.validate(_catalog, _reference_ids)
	_expect(bool(validation.get("ok", false)), "reference-aware validation — %s" % str(validation.get("errors", [])))
	for raw_action: Variant in _catalog.get("actions", []):
		var action: Dictionary = raw_action
		_expect(IconRegistry.has(StringName(action.get("icon_id", ""))), "%s icon exists" % action.get("action_id", ""))
	var broken := _catalog.duplicate(true)
	var store_action := _find_mutable_action(broken, "action_market_open_food_row")
	store_action["intent"]["payload"]["store_id"] = "store_missing"
	_expect(not bool(Validator.validate(broken, _reference_ids).get("ok", true)), "unknown store ID must fail")


func _test_intent_schema_failures() -> void:
	var missing_payload_field := _catalog.duplicate(true)
	var search := _find_mutable_action(missing_payload_field, "action_underpass_enter_service_yard")
	search["intent"]["payload"].erase("zone_id")
	_expect(not bool(Validator.validate(missing_payload_field).get("ok", true)), "missing typed payload field")
	var extra_payload_field := _catalog.duplicate(true)
	var store := _find_mutable_action(extra_payload_field, "action_station_open_commission")
	store["intent"]["payload"]["price"] = 1
	_expect(not bool(Validator.validate(extra_payload_field).get("ok", true)), "extra payload field")
	var unknown_intent := _catalog.duplicate(true)
	_find_mutable_action(unknown_intent, "action_clinic_rest_bench")["intent"]["type"] = "run_script"
	_expect(not bool(Validator.validate(unknown_intent).get("ok", true)), "unknown intent")


func _test_time_schema_failures() -> void:
	var immediate_with_duration := _catalog.duplicate(true)
	_find_mutable_action(immediate_with_duration, "action_market_read_board")["duration"] = {"kind": "fixed", "minutes": 5}
	_expect(not bool(Validator.validate(immediate_with_duration).get("ok", true)), "unconfirmed action with duration")
	var confirmed_without_duration := _catalog.duplicate(true)
	_find_mutable_action(confirmed_without_duration, "action_market_eat_simple_meal").erase("duration")
	_expect(not bool(Validator.validate(confirmed_without_duration).get("ok", true)), "confirmed action without duration")
	var mismatched_confirmation := _catalog.duplicate(true)
	var rest := _find_mutable_action(mismatched_confirmation, "action_underpass_rest_by_pipes")
	rest["confirmation"] = "none"
	_expect(not bool(Validator.validate(mismatched_confirmation).get("ok", true)), "duration remains forbidden after mode change")


func _test_catalog_failures() -> void:
	var duplicate_id := _catalog.duplicate(true)
	duplicate_id["actions"][20]["action_id"] = duplicate_id["actions"][19]["action_id"]
	_expect(not bool(Validator.validate(duplicate_id).get("ok", true)), "duplicate action ID")
	var wrong_locations := _catalog.duplicate(true)
	wrong_locations["location_ids"].append("old_harbor")
	_expect(not bool(Validator.validate(wrong_locations).get("ok", true)), "seventh location")
	var empty_location := _catalog.duplicate(true)
	for raw_action: Variant in empty_location["actions"]:
		if String(raw_action.get("location_id", "")) == "embankment":
			raw_action["location_id"] = "underpass"
	_expect(not bool(Validator.validate(empty_location).get("ok", true)), "every location needs meaningful choices")


func _test_numeric_failure() -> void:
	var float_duration := _catalog.duplicate(true)
	_find_mutable_action(float_duration, "action_station_walk_to_underpass")["duration"]["minutes"] = 12.5
	_expect(not bool(Validator.validate(float_duration).get("ok", true)), "fractional duration")
	var float_requirement := _catalog.duplicate(true)
	_find_mutable_action(float_requirement, "action_recycling_move_bundle")["requirements"][0]["value"] = 6.0
	_expect(not bool(Validator.validate(float_requirement).get("ok", true)), "fractional characteristic threshold")


func _test_content_boundary() -> void:
	_expect(not _contains_key_or_value(_catalog, "npc_"), "catalog must not embed NPC IDs or fields")
	_expect(not _contains_key_or_value(_catalog, "script"), "catalog must not embed scripts")
	_expect(not _contains_key_or_value(_catalog, "effects"), "catalog must expose intents instead of effects")
	var injected := _catalog.duplicate(true)
	_find_mutable_action(injected, "action_recycling_open_shift")["intent"]["payload"]["npc_id"] = "npc_viktor_koren"
	_expect(not bool(Validator.validate(injected).get("ok", true)), "NPC injection is rejected")


func _test_purity_and_copies() -> void:
	var before := _catalog.duplicate(true)
	var validation := Validator.validate(_catalog, _reference_ids)
	_expect(bool(validation.get("ok", false)), "source validates")
	_expect(_catalog == before, "validation does not mutate the catalog")
	var found := Catalog.find_action(_catalog, "action_market_open_food_row")
	found["title"] = "Изменено"
	_expect(Catalog.find_action(_catalog, "action_market_open_food_row").get("title") != "Изменено", "find_action returns a deep copy")
	var location_actions := Catalog.actions_for_location(_catalog, "market")
	location_actions[0]["requirements"].append({"type": "test"})
	_expect(_catalog == before, "actions_for_location returns independent deep copies")


func _build_reference_ids() -> Dictionary:
	var knowledge_loaded := KnowledgeCatalog.load_default()
	var job_loaded := JobCatalog.load_default()
	var reputation_loaded := ReputationCatalog.load_default()
	var store_loaded := StoreCatalog.load_default()
	var zone_loaded := SearchZoneCatalog.load_default()
	_record_load_failure("knowledge", knowledge_loaded)
	_record_load_failure("jobs", job_loaded)
	_record_load_failure("reputations", reputation_loaded)
	_record_load_failure("stores", store_loaded)
	_record_load_failure("search zone", zone_loaded)
	var knowledge: Dictionary = knowledge_loaded.get("catalog", {})
	var jobs: Dictionary = job_loaded.get("catalog", {})
	var reputations: Dictionary = reputation_loaded.get("catalog", {})
	var stores: Dictionary = store_loaded.get("catalog", {})
	var zone: Dictionary = zone_loaded.get("template", {})
	return {
		"knowledge_ids": _index_entries(knowledge.get("knowledge", []), "id"),
		"job_ids": _index_entries(jobs.get("jobs", []), "id"),
		"organization_ids": _index_entries(reputations.get("audiences", []), "id"),
		"store_ids": _index_entries(stores.get("stores", []), "store_id"),
		"search_zone_ids": {String(zone.get("id", "")): true},
		"item_ids": _load_item_ids(),
	}


func _load_item_ids() -> Dictionary:
	var file := FileAccess.open("res://game/items/data/item_catalog_v1.json", FileAccess.READ)
	if file == null:
		_failures.append("item catalog setup — cannot open file")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_failures.append("item catalog setup — invalid JSON")
		return {}
	return _index_entries(parsed.get("items", []), "id")


func _index_entries(values: Variant, id_key: String) -> Dictionary:
	var result: Dictionary = {}
	if not values is Array:
		return result
	for raw_entry: Variant in values:
		if raw_entry is Dictionary:
			result[String(raw_entry.get(id_key, ""))] = true
	return result


func _record_load_failure(label: String, loaded: Dictionary) -> void:
	if not bool(loaded.get("ok", false)):
		_failures.append("%s setup — %s" % [label, str(loaded.get("errors", []))])


func _find_mutable_action(catalog: Dictionary, action_id: String) -> Dictionary:
	for raw_action: Variant in catalog.get("actions", []):
		if raw_action is Dictionary and String(raw_action.get("action_id", "")) == action_id:
			return raw_action
	return {}


func _contains_key_or_value(value: Variant, needle: String) -> bool:
	if value is Dictionary:
		for raw_key: Variant in value:
			if String(raw_key).to_lower().begins_with(needle) or _contains_key_or_value(value[raw_key], needle):
				return true
	elif value is Array:
		for nested: Variant in value:
			if _contains_key_or_value(nested, needle):
				return true
	elif typeof(value) == TYPE_STRING:
		return String(value).to_lower().contains(needle)
	return false


func _run(label: String, test: Callable) -> void:
	_tests_run += 1
	_current = label
	test.call()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _finish() -> void:
	if _failures.is_empty():
		print("M3F.2 action catalog: %d tests passed" % _tests_run)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
