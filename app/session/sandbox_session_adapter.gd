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
const WeekCityMapModelScript := preload("res://app/map/week_city_map_model.gd")
const WeekInventoryBoundary := preload("res://app/session/week_inventory_session_boundary.gd")
const WeekFacade := preload("res://app/session/week_session_facade.gd")
const SearchCommands := preload("res://app/session/search_session_commands.gd")
const SearchModels := preload("res://app/search/search_read_model.gd")
const EncounterCommand := preload("res://game/events/search_encounter_command.gd")
const HeroModels := preload("res://app/hero/hero_view_model.gd")

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


func get_phase() -> String:
	if _session == null:
		return "uninitialized"
	if _session.survival_state != null and _session.survival_state.is_terminal():
		return "completed"
	return _session.phase


func get_summary_model() -> Dictionary:
	var result := super.get_summary_model()
	if _session != null and _session.survival_state != null:
		result["lifecycle"] = _session.survival_state.to_dict()
	return result


func get_location_model() -> Dictionary:
	if _session == null:
		return {}
	return WeekFacade.location_model(
		_session,
		super.get_location_model(),
		bool(_session.settings.get("show_locked_options", false))
	)


func perform_location_action(action_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.execute_location_action(
		_session,
		action_id,
		_session.flow_revision
	))


func get_store_model(store_id: String, reduced_motion: bool = false) -> Dictionary:
	return (
		WeekFacade.store_model(_session, store_id, reduced_motion)
		if _session != null
		else _missing_sandbox_session()
	)


func buy_store_offer(
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	expected_revision: int
) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.buy(
		_session,
		store_id,
		offer_id,
		quantity,
		target_container_id,
		expected_revision,
		_session.flow_revision
	))


func get_store_sell_offers(store_id: String) -> Dictionary:
	return (
		WeekFacade.sell_offers(_session, store_id)
		if _session != null
		else _missing_sandbox_session()
	)


func sell_store_item(
	store_id: String,
	stack_id: String,
	quantity: int,
	expected_revision: int
) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.sell(
		_session,
		store_id,
		stack_id,
		quantity,
		expected_revision,
		_session.flow_revision
	))


func available_shelters() -> Array:
	return [] if _session == null else WeekFacade.shelters(_session)


func choose_shelter(shelter_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.sleep(
		_session,
		shelter_id,
		_session.flow_revision
	))


func get_recycling_offers() -> Array[Dictionary]:
	return [] if _session == null else WeekFacade.recycling_offers(_session)


func get_npc_model(npc_id: String, reduced_motion: bool = false) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	var result := WeekFacade.npc_model(
		_session,
		npc_id,
		bool(_session.settings.get("show_locked_options", false)),
		reduced_motion
	)
	if bool(result.get("ok", false)):
		result["expected_revision"] = _session.flow_revision
	return result


func preview_npc_interaction(npc_id: String, interaction_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return WeekFacade.preview_npc_interaction(_session, npc_id, interaction_id)


func execute_npc_interaction(
	npc_id: String,
	interaction_id: String,
	expected_flow_revision: int
) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.execute_npc_interaction(
		_session,
		npc_id,
		interaction_id,
		expected_flow_revision
	))


func get_npc_gift_offers(npc_id: String) -> Array[Dictionary]:
	if _session == null:
		return []
	return WeekFacade.gift_offers(_session, npc_id)


func give_to_npc(npc_id: String, stack_id: String, quantity: int = 0) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.give_to_npc(
		_session,
		npc_id,
		stack_id,
		quantity,
		_session.flow_revision
	))


func get_hero_model() -> Dictionary:
	if _session == null or _session.run_state == null:
		return {}
	return HeroModels.raw(_session.run_state)


func get_inventory_model() -> Dictionary:
	if _session == null or _session.run_state == null:
		return {}
	# The boundary only needs the name of the place, so the full location
	# read-model — NPC schedules, shift availability and all — is not built.
	return WeekInventoryBoundary.model(_session, _session.get_location_summary())


func perform_inventory_action(
	stack_id: String,
	action_id: String,
	quantity: int = 0,
	target_container_id: String = ""
) -> Dictionary:
	if _session == null or _session.run_state == null:
		return _missing_sandbox_session()
	return WeekInventoryBoundary.execute(
		_session,
		stack_id,
		action_id,
		quantity,
		target_container_id
	)


func get_job_shift_model(reduced_motion: bool = false) -> Dictionary:
	if _session == null:
		return {}
	return WeekFacade.job_shift_model(_session, reduced_motion)


func is_job_shift_active() -> bool:
	if _session == null:
		return false
	var work_state: JobWorkState = _session.job_work_state
	return work_state != null and work_state.is_active()


func begin_job_shift() -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.begin_job_shift(_session, _session.flow_revision))


func quick_resolve_job_shift() -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.quick_resolve_job_shift(
		_session,
		_session.flow_revision
	))


func resolve_job_shift_step(choice_id: String) -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	return _finish_week_command(WeekFacade.resolve_job_shift_step(
		_session,
		choice_id,
		_session.flow_revision
	))


func _finish_week_command(result: Dictionary) -> Dictionary:
	if (
		bool(result.get("ok", false))
		and String(result.get("code", "")) != "already_applied"
		and bool(result.get("mutated", true))
	):
		_session.flow_revision += 1
	result["flow_revision"] = _session.flow_revision if _session != null else 0
	return result


func perform_inventory_replacement(
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	if _session == null or _session.run_state == null:
		return _missing_sandbox_session()
	return WeekInventoryBoundary.replace(
		_session,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)


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
	return {} if _session == null else WeekCityMapModelScript.build(_session)


func travel(destination: String, mode: String = "walk") -> Dictionary:
	if _session == null:
		return _missing_sandbox_session()
	var selected_route := WeekCityMapModelScript.find_route(
		get_city_map_model(),
		destination,
		mode
	)
	var result := super.travel(destination, mode)
	if bool(result.get("ok", false)) and not selected_route.is_empty():
		result["route_option_id"] = String(selected_route.get("option_id", ""))
		result["mode"] = mode
		result["minutes"] = int(selected_route.get("minutes", 0))
		result["price"] = int(selected_route.get("price", 0))
	return result
func _missing_sandbox_session() -> Dictionary:
	return {
		"ok": false,
		"code": "missing_session",
		"error": "FirstDaySession is not attached.",
	}
