class_name SearchSessionService
extends RefCounted

## Public facade for the M3D search aggregate. Responsibilities live in small
## lifecycle, movement and gameplay command collaborators.

const Lifecycle := preload("res://game/search/search_session_lifecycle.gd")
const Movement := preload("res://game/search/search_movement_service.gd")
const Commands := preload("res://game/search/search_command_service.gd")


static func begin_search(
	session: Object,
	template_id: String,
	command_id: String
) -> Dictionary:
	return Lifecycle.begin_search(session, template_id, command_id)


static func finish_search(session: Object, command_id: String) -> Dictionary:
	return Lifecycle.finish_search(session, command_id)


static func plan_move(
	session: Object,
	target: Variant,
	command_id: String
) -> Dictionary:
	return Movement.plan_move(session, target, command_id)


static func checkpoint_move(
	session: Object,
	position: Variant,
	path_index: int,
	completed: bool,
	command_id: String
) -> Dictionary:
	return Movement.checkpoint_move(
		session,
		position,
		path_index,
		completed,
		command_id
	)


static func preview_interaction(
	session: Object,
	object_id: String,
	approach_id: String
) -> Dictionary:
	return Commands.preview_interaction(session, object_id, approach_id)


static func confirm_interaction(
	session: Object,
	object_id: String,
	approach_id: String,
	command_id: String
) -> Dictionary:
	return Commands.confirm_interaction(
		session,
		object_id,
		approach_id,
		command_id
	)


static func pick_up(
	session: Object,
	stack_id: String,
	target_container_id: String,
	command_id: String
) -> Dictionary:
	return Commands.pick_up(
		session,
		stack_id,
		target_container_id,
		command_id
	)


static func replace(
	session: Object,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String,
	command_id: String
) -> Dictionary:
	return Commands.replace(
		session,
		incoming_stack_id,
		displaced_stack_id,
		target_container_id,
		command_id
	)


static func quick_search(session: Object, command_id: String) -> Dictionary:
	return Commands.quick_search(session, command_id)
