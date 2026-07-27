class_name WeekInventorySessionBoundary
extends RefCounted

## Application boundary for the week inventory. It keeps item routing and
## revision bookkeeping out of the sandbox session facade while delegating
## every mutation to the existing inventory/domain transactions.

const InventoryTransaction := preload("res://core/inventory/inventory_transaction.gd")
const WeekInventoryCommand := preload("res://game/week/week_inventory_command.gd")


static func model(session: Object, location_model: Dictionary) -> Dictionary:
	var run_state: RunState = session.get("run_state")
	var location_id := String(session.get("location"))
	return {
		"inventory": run_state.inventory.duplicate(true),
		"strength": run_state.get_characteristic("strength"),
		"location_id": location_id,
		"location_title": String(location_model.get("title", location_id)),
	}


static func execute(
	session: Object,
	stack_id: String,
	action_id: String,
	quantity: int = 0,
	target_container_id: String = ""
) -> Dictionary:
	var run_state: RunState = session.get("run_state")
	var result: Dictionary
	match action_id:
		"select":
			result = InventoryTransaction.select(run_state, stack_id)
		"move":
			result = InventoryTransaction.move(
				run_state,
				stack_id,
				target_container_id,
				quantity
			)
		"pick_up":
			result = InventoryTransaction.pick_up(
				run_state,
				stack_id,
				target_container_id,
				quantity
			)
		"use", "disassemble", "sell":
			result = WeekInventoryCommand.execute(
				session,
				stack_id,
				action_id,
				_command_id(session, stack_id, action_id),
				quantity
			)
		"drop":
			result = InventoryTransaction.drop(
				run_state,
				stack_id,
				String(session.get("location")),
				quantity
			)
		_:
			return {
				"ok": false,
				"code": "unknown_inventory_action",
				"error": "Неизвестное действие с предметом.",
			}
	return _finish(session, result)


static func replace(
	session: Object,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String
) -> Dictionary:
	var result := InventoryTransaction.replace(
		session.get("run_state"),
		incoming_stack_id,
		displaced_stack_id,
		target_container_id
	)
	return _finish(session, result)


static func _command_id(
	session: Object,
	stack_id: String,
	action_id: String
) -> String:
	var run_state: RunState = session.get("run_state")
	return "week:item:%s:%s:%d:%d" % [
		action_id,
		stack_id,
		run_state.calendar.elapsed_minutes,
		int(session.get("flow_revision")),
	]


static func _finish(session: Object, result: Dictionary) -> Dictionary:
	if bool(result.get("ok", false)):
		var revision := int(session.get("flow_revision")) + 1
		session.set("flow_revision", revision)
		result["flow_revision"] = revision
	return result
