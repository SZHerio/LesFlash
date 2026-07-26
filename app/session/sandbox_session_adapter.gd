class_name SandboxSessionAdapter
extends FirstDaySessionAdapter

## Product-facing session façade for the location-first sandbox.
##
## The inherited adapter keeps the verified M2 commands available for legacy
## saves. New runs and read models use the M3B contract: the location is the
## base screen, ordinary events are not exposed as permanent action buttons,
## and travel is described before it is confirmed.

const LegacySessionScript := preload("res://game/first_day/first_day_session.gd")
const LegacySaveScript := preload("res://game/first_day/first_day_save.gd")
const FirstDayContentScript := preload("res://game/first_day/first_day_content.gd")
const LocationActions := preload("res://game/location/location_action_service.gd")
const LocationActionCommand := preload("res://game/location/first_day_location_action_command.gd")
const InventoryTransaction := preload("res://core/inventory/inventory_transaction.gd")
const SearchCommands := preload("res://app/session/search_session_commands.gd")
const SearchModels := preload("res://app/search/search_read_model.gd")
const EncounterCommand := preload("res://game/events/search_encounter_command.gd")
const HeroModels := preload("res://app/hero/hero_view_model.gd")

const CATEGORY_BY_ACTION_KIND := {
	"local": "observe",
	"search": "search",
	"job": "work",
	"wait": "rest",
	"shelter": "shelter",
}


static func create(characteristics: Dictionary, seed: int) -> RefCounted:
	var session := LegacySessionScript.create_location_first(characteristics, seed)
	if session == null:
		return null
	var adapter_script: Script = load("res://app/session/sandbox_session_adapter.gd")
	return adapter_script.new(session)


static func load_session(path: String = FirstDaySave.DEFAULT_SAVE_PATH) -> Dictionary:
	var result: Dictionary = LegacySaveScript.load_session(path)
	if bool(result.get("ok", false)):
		var adapter_script: Script = load("res://app/session/sandbox_session_adapter.gd")
		result["adapter"] = adapter_script.new(result.get("session"))
	return result


func start_new_run(characteristics: Dictionary, seed: int) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _session.start_new_location_first(characteristics, seed)


func get_location_model() -> Dictionary:
	var model := super.get_location_model()
	var sandbox_actions: Array = []
	var include_blocked := bool(_session.settings.get("show_locked_options", false))
	for raw_action in LocationActions.get_actions(
		_session,
		_session.location,
		{"include_blocked": include_blocked}
	):
		if not raw_action is Dictionary:
			continue
		var action := Dictionary(raw_action).duplicate(true)
		action["kind"] = "local"
		action["minutes"] = int(action.get("duration_minutes", 0))
		sandbox_actions.append(_with_action_semantics(action))
	for raw_action in Array(model.get("actions", [])):
		if raw_action is Dictionary and String(raw_action.get("kind", "")) != "event":
			var inherited_action := Dictionary(raw_action).duplicate(true)
			if String(inherited_action.get("kind", "")) == "wait":
				inherited_action["description"] = "Перейти к вечерним делам и подготовке ночлега."
			sandbox_actions.append(_with_action_semantics(inherited_action))
	var search_action := _search_action()
	if not search_action.is_empty():
		sandbox_actions.push_front(search_action)
	model["actions"] = sandbox_actions
	return model


## The searchable yard is the headline activity of the place that owns it, so it
## leads the list instead of sitting below the ordinary actions.
func _search_action() -> Dictionary:
	if _session == null:
		return {}
	var template := SearchModels.zone_for_location(_session.location)
	if template.is_empty():
		return {}
	return {
		"id": "search_zone:%s" % String(template.get("id", "")),
		"kind": "search",
		"category_id": "search",
		"category_icon_id": String(LocationActions.category_icon_id("search")),
		"location_id": _session.location,
		"title": "Продолжить поиск" if _session.is_search_active() else "Искать полезное",
		"description": "%s Ходьба по зоне не тратит время — его тратят только подтверждённые решения." % String(
			template.get("description", "")
		),
		"minutes": 0,
		"risk": 0,
		"available": true,
		"reasons": [],
		"meta_tokens": [{
			"icon_id": &"",
			"text": "Мини-игра",
			"accessible_text": "Мини-игра поиска",
		}],
	}


func _with_action_semantics(raw_action: Dictionary) -> Dictionary:
	var action := raw_action.duplicate(true)
	var kind := String(action.get("kind", "local"))
	var category_id := String(action.get("category_id", "")).strip_edges()
	if category_id.is_empty():
		category_id = String(CATEGORY_BY_ACTION_KIND.get(kind, "observe"))
	action["category_id"] = category_id
	action["category_icon_id"] = String(LocationActions.category_icon_id(category_id))
	action["meta_tokens"] = _action_meta_tokens(action)
	return action


func _action_meta_tokens(action: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var has_time := false
	for raw_token: Variant in Array(action.get("meta_tokens", [])):
		if not raw_token is Dictionary:
			continue
		var token: Dictionary = Dictionary(raw_token).duplicate(true)
		if String(token.get("text", "")).strip_edges().is_empty():
			continue
		has_time = has_time or String(token.get("icon_id", "")) == "meta_time"
		result.append(token)
	var minutes := int(action.get("minutes", action.get("duration_minutes", 0)))
	if minutes > 0 and not has_time:
		var time_text := "%d мин" % minutes
		result.append({"icon_id": &"meta_time", "text": time_text, "accessible_text": time_text})
	return result


func perform_location_action(action_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return LocationActionCommand.execute(_session, action_id)


func get_hero_model() -> Dictionary:
	if _session == null or _session.run_state == null:
		return {}
	return HeroModels.raw(_session.run_state)


func get_inventory_model() -> Dictionary:
	if _session == null or _session.run_state == null:
		return {}
	var location_model := get_location_model()
	return {
		"inventory": _session.run_state.inventory.duplicate(true),
		"strength": _session.run_state.get_characteristic("strength"),
		"location_id": _session.location,
		"location_title": String(location_model.get("title", _session.location)),
	}


func perform_inventory_action(
	stack_id: String,
	action_id: String,
	quantity: int = 0,
	target_container_id: String = ""
) -> Dictionary:
	if _session == null or _session.run_state == null:
		return _missing_sandbox_session()
	var result: Dictionary
	match action_id:
		"select":
			result = InventoryTransaction.select(_session.run_state, stack_id)
		"move":
			result = InventoryTransaction.move(
				_session.run_state,
				stack_id,
				target_container_id,
				quantity
			)
		"pick_up":
			result = InventoryTransaction.pick_up(
				_session.run_state,
				stack_id,
				target_container_id,
				quantity
			)
		"use":
			result = InventoryTransaction.use(_session.run_state, stack_id)
		"disassemble":
			result = InventoryTransaction.disassemble(_session.run_state, stack_id)
		"drop":
			result = InventoryTransaction.drop(
				_session.run_state,
				stack_id,
				_session.location,
				quantity
			)
		_:
			return {
				"ok": false,
				"code": "unknown_inventory_action",
				"error": "Неизвестное действие с предметом.",
			}
	if bool(result.get("ok", false)):
		_session.flow_revision += 1
		result["flow_revision"] = _session.flow_revision
	return result


func perform_inventory_replacement(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	if _session == null or _session.run_state == null:
		return _missing_sandbox_session()
	var result := InventoryTransaction.replace(
		_session.run_state,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	if bool(result.get("ok", false)):
		_session.flow_revision += 1
		result["flow_revision"] = _session.flow_revision
	return result


func is_search_active() -> bool:
	return _session != null and _session.is_search_active()


func get_search_zone_id() -> String:
	return SearchCommands.zone_id(_session)


func get_search_model() -> Dictionary:
	return SearchModels.build(_session) if _session != null else {}


func get_encounter_model() -> Dictionary:
	return EncounterCommand.pending(_session) if _session != null else {}


func suggest_loot_container(stack_id: String, exclude_container_id: String) -> String:
	if _session == null:
		return ""
	return SearchModels.alternative_container(_session, stack_id, exclude_container_id)


func begin_search() -> Dictionary:
	return SearchCommands.begin(_session) if _session != null else _missing_sandbox_session()


func finish_search() -> Dictionary:
	return SearchCommands.finish(_session) if _session != null else _missing_sandbox_session()


func plan_search_move(target: Variant) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.plan_move(_session, target)


func checkpoint_search_move(position: Variant, path_index: int) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.arrive(_session, position, path_index)


func confirm_search_interaction(object_id: String, approach_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.interact(_session, object_id, approach_id)


func pick_up_search_loot(stack_id: String, target_container_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.pick_up(_session, stack_id, target_container_id)


func replace_search_loot(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.replace(
		_session,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)


func run_quick_search() -> Dictionary:
	return SearchCommands.quick(_session) if _session != null else _missing_sandbox_session()


func resolve_encounter(option_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return SearchCommands.resolve_encounter(_session, option_id)


func get_city_map_model() -> Dictionary:
	if _session == null:
		return {}
	var raw_model: Dictionary = _session.get_map_model()
	var locations: Array = []
	for raw_location in Array(raw_model.get("locations", [])):
		if not raw_location is Dictionary:
			continue
		var location_model := Dictionary(raw_location).duplicate(true)
		location_model["known"] = true
		locations.append(location_model)
	var routes: Array = []
	var origin := String(raw_model.get("current_location_id", _session.location))
	for raw_route in Array(raw_model.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route := Dictionary(raw_route).duplicate(true)
		var destination := String(route.get("destination_id", ""))
		var mode := String(route.get("mode", "walk"))
		route["from_location_id"] = origin
		route["option_id"] = "%s:%s:%s" % [origin, destination, mode]
		route["price"] = _route_price(origin, destination, mode)
		routes.append(route)
	var district: Dictionary = FirstDayContentScript.district()
	return {
		"district_id": String(district.get("id", "")),
		"district_title": String(district.get("title", "Город")),
		"district_description": String(district.get("description", "")),
		"current_location_id": origin,
		"locations": locations,
		"routes": routes,
		"calendar": Dictionary(raw_model.get("calendar", {})).duplicate(true),
	}


func travel(destination: String, mode: String = "walk") -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	var selected_route := _find_map_route(destination, mode)
	var result := super.travel(destination, mode)
	if bool(result.get("ok", false)) and not selected_route.is_empty():
		result["route_option_id"] = String(selected_route.get("option_id", ""))
		result["mode"] = mode
		result["minutes"] = int(selected_route.get("minutes", 0))
		result["price"] = int(selected_route.get("price", 0))
	return result


func _find_map_route(destination: String, mode: String) -> Dictionary:
	for raw_route in Array(get_city_map_model().get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		if (
			String(route.get("destination_id", "")) == destination
			and String(route.get("mode", "walk")) == mode
		):
			return route.duplicate(true)
	return {}


func _route_price(origin: String, destination: String, mode: String) -> int:
	if mode != "bus":
		return 0
	var place: Dictionary = FirstDayContentScript.location(origin)
	for raw_route in Array(place.get("routes", [])):
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var route_destination := String(
			route.get("destination_id", route.get("destination", route.get("to", "")))
		)
		if route_destination == destination:
			return maxi(int(route.get("fare", 0)), 0)
	return 0


func _missing_sandbox_session() -> Dictionary:
	return {
		"ok": false,
		"code": "missing_session",
		"error": "FirstDaySession is not attached.",
	}
