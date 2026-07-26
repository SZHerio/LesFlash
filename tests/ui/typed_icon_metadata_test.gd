extends SceneTree

const UiModels := preload("res://app/ui_model_factory.gd")
const SearchModels := preload("res://app/search/search_model_mapper.gd")
const CityMapModels := preload("res://app/map/city_map_view_model.gd")
const EncounterModels := preload("res://app/events/encounter_view_model.gd")
const LocationCatalog := preload("res://game/location/location_action_catalog.gd")
const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_location_catalog()
	_check_location_model()
	_check_search_model()
	_check_map_model()
	_check_encounter_model()
	if _failures.is_empty():
		print("TYPED ICON METADATA PASSED: location, search, map and encounter")
		quit(0)
		return
	for failure: String in _failures:
		push_error("TYPED ICON METADATA: %s" % failure)
	quit(1)


func _check_location_catalog() -> void:
	var loaded := LocationCatalog.load_default()
	_require(bool(loaded.get("ok", false)), "location catalog did not load")
	for action: Dictionary in Dictionary(loaded.get("catalog", {})).get("actions", []):
		var category_id := String(action.get("category_id", ""))
		_require(
			IconRegistryScript.has(LocationCatalog.category_icon_id(category_id)),
			"catalog action %s has no registered category icon" % action.get("id", "")
		)


func _check_location_model() -> void:
	var model := UiModels.location({
		"location": {
			"title": "Проверка",
			"actions": [{
				"id": "misleading_title",
				"kind": "local",
				"category_id": "talk",
				"title": "Поспать",
				"available": true,
				"meta_tokens": [{
					"icon_id": &"meta_time",
					"text": "7 мин",
					"accessible_text": "Семь минут",
				}],
			}],
		},
		"status": {"meters": {}, "calendar": {}},
	}, true)
	var actions: Array = model.get("actions", [])
	_require(actions.size() == 1, "location action was lost")
	if actions.is_empty():
		return
	var action: Dictionary = actions[0]
	_require(
		StringName(action.get("category_icon_id", &"")) == &"action_talk",
		"location icon was inferred from Russian title instead of category_id"
	)
	var meta_tokens: Array = action.get("meta_tokens", [])
	_require(
		meta_tokens.size() == 1
		and StringName(Dictionary(meta_tokens[0]).get("icon_id", &"")) == &"meta_time",
		"typed location metadata was not preserved"
	)


func _check_search_model() -> void:
	var objects := SearchModels.objects([{
		"id": "crate",
		"title": "Ящик",
		"type": "open",
		"position": [1, 1],
		"approaches": [{
			"id": "inspect",
			"title": "Осмотреть",
			"costs": {"minutes": 4, "energy": 2, "noise": 1},
		}],
	}], {})
	var approaches: Array = Dictionary(objects[0]).get("approaches", []) if not objects.is_empty() else []
	var tokens: Array = Dictionary(approaches[0]).get("cost_tokens", []) if not approaches.is_empty() else []
	var ids: Array[StringName] = []
	for token: Dictionary in tokens:
		ids.append(StringName(token.get("icon_id", &"")))
	_require(ids == [&"meta_time", &"meta_energy", &"meta_risk"], "search costs are not explicit typed tokens")


func _check_map_model() -> void:
	var model := CityMapModels.build({
		"current_location_id": "station_square",
		"locations": [
			{"id": "station_square", "title": "Вокзал"},
			{"id": "market", "title": "Рынок"},
		],
		"routes": [{
			"from_location_id": "station_square",
			"destination_id": "market",
			"mode": "bus",
			"mode_title": "Автобус",
			"minutes": 9,
			"price": 6,
		}],
	}, true)
	var nodes: Array = model.get("nodes", [])
	for node: Dictionary in nodes:
		_require(
			IconRegistryScript.has(StringName(node.get("place_icon_id", &""))),
			"map node has no explicit registered icon"
		)
	var routes: Array = model.get("routes", [])
	var modes: Array = Dictionary(routes[0]).get("modes", []) if not routes.is_empty() else []
	var mode: Dictionary = modes[0] if not modes.is_empty() else {}
	_require(StringName(mode.get("icon_id", &"")) == &"transport_bus", "transport icon was not mapped by stable mode ID")
	var price_tokens: Array = mode.get("meta_tokens", [])
	_require(
		price_tokens.size() == 2
		and StringName(Dictionary(price_tokens[1]).get("icon_id", &"")) == &"currency_arden_compact"
		and String(Dictionary(price_tokens[1]).get("text", "")) == "6",
		"map price duplicated or lost the arden token"
	)


func _check_encounter_model() -> void:
	var model := EncounterModels.build({
		"title": "Проверка",
		"options": [{
			"id": "trade_answer",
			"label": "Отдать",
			"category_id": "trade",
			"available": true,
			"effects": [{"type": "change_money", "delta": -4}],
		}],
	}, "Рынок", true)
	var options: Array = model.get("options", [])
	var option: Dictionary = options[0] if not options.is_empty() else {}
	_require(StringName(option.get("category_icon_id", &"")) == &"action_trade", "encounter category did not map explicitly")
	var tokens: Array = option.get("meta_tokens", [])
	_require(
		tokens.size() == 1
		and StringName(Dictionary(tokens[0]).get("icon_id", &"")) == &"currency_arden_compact"
		and String(Dictionary(tokens[0]).get("text", "")) == "-4",
		"encounter price duplicated or lost the arden token"
	)
	_require("₽" not in var_to_str(model), "real currency symbol leaked into encounter model")


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
