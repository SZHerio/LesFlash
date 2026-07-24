class_name SearchSessionCommands
extends RefCounted

## Command boundary for the search activity.
##
## Every mutating call carries a command id derived from the session revision,
## so retrying after a failed save reuses it and can never apply the same
## decision twice.

const SearchService := preload("res://game/search/search_session_service.gd")
const SearchModels := preload("res://app/search/search_read_model.gd")
const EncounterCommand := preload("res://game/events/search_encounter_command.gd")


static func zone_id(session: Object) -> String:
	if session == null:
		return ""
	return String(SearchModels.zone_for_location(session.get("location")).get("id", ""))


static func begin(session: Object) -> Dictionary:
	var identifier := zone_id(session)
	if identifier.is_empty():
		return {
			"ok": false,
			"code": "no_search_zone",
			"error": "Здесь нечего обыскивать.",
		}
	return SearchService.begin_search(
		session,
		identifier,
		command_id(session, ["begin", identifier])
	)


static func finish(session: Object) -> Dictionary:
	return SearchService.finish_search(session, command_id(session, ["finish"]))


static func plan_move(session: Object, target: Variant) -> Dictionary:
	return SearchService.plan_move(
		session,
		target,
		command_id(session, ["move", str(target)])
	)


static func arrive(session: Object, position: Variant, path_index: int) -> Dictionary:
	return SearchService.checkpoint_move(
		session,
		position,
		path_index,
		true,
		command_id(session, ["arrive", str(path_index)])
	)


static func interact(
	session: Object,
	object_id: String,
	approach_id: String
) -> Dictionary:
	return SearchService.confirm_interaction(
		session,
		object_id,
		approach_id,
		command_id(session, ["interact", object_id, approach_id])
	)


static func pick_up(
	session: Object,
	stack_id: String,
	target_container_id: String
) -> Dictionary:
	return SearchService.pick_up(
		session,
		stack_id,
		target_container_id,
		command_id(session, ["pickup", stack_id, target_container_id])
	)


static func replace(
	session: Object,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	return SearchService.replace(
		session,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id,
		command_id(session, ["swap", incoming_stack_id, displaced_stack_id])
	)


static func quick(session: Object) -> Dictionary:
	return SearchService.quick_search(session, command_id(session, ["quick"]))


static func resolve_encounter(session: Object, option_id: String) -> Dictionary:
	return EncounterCommand.resolve(
		session,
		option_id,
		command_id(session, ["encounter", option_id])
	)


static func command_id(session: Object, parts: Array) -> String:
	var pieces := PackedStringArray(["search"])
	for part: Variant in parts:
		pieces.append(String(part))
	pieces.append(str(session.get("flow_revision") if session != null else 0))
	return ":".join(pieces)
