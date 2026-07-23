extends RefCounted

const Query := preload("res://core/inventory/inventory_query.gd")
const Mutation := preload("res://core/inventory/inventory_mutation.gd")
const StackWriter := preload("res://core/inventory/inventory_stack_writer.gd")


static func replace_stack(
	inventory: Dictionary,
	incoming_stack_id: String,
	displaced_stack_id: String,
	target_container_id: String,
	strength: int
) -> Dictionary:
	var incoming := Query.find_stack(inventory, incoming_stack_id)
	var displaced := Query.find_stack(inventory, displaced_stack_id)
	if incoming.is_empty() or not bool(incoming.get("external", false)):
		return _failure("missing_incoming_stack", "Находка больше не лежит в исходном месте.")
	if (
		displaced.is_empty()
		or bool(displaced.get("external", false))
		or String(displaced.get("container_id", "")) != target_container_id
	):
		return _failure("invalid_replacement", "Выбранная вещь не находится в целевом контейнере.")
	var source_container_id := String(incoming.get("container_id", ""))
	var displaced_removal := Mutation.remove_stack(
		inventory,
		displaced_stack_id,
		int(displaced.get("quantity", 0))
	)
	if not bool(displaced_removal.get("ok", false)):
		return displaced_removal
	var incoming_move := Mutation.move_stack(
		displaced_removal["inventory"],
		incoming_stack_id,
		target_container_id,
		0,
		strength
	)
	if not bool(incoming_move.get("ok", false)):
		return _failure(
			String(incoming_move.get("code", "capacity_conflict")),
			String(incoming_move.get("error", "Замена не освобождает достаточно места.")),
			{"conflict": incoming_move.duplicate(true)}
		)
	var displaced_restore := StackWriter.add_to_container(
		incoming_move["inventory"],
		source_container_id,
		String(displaced.get("item_id", "")),
		int(displaced.get("quantity", 0)),
		int(displaced.get("condition", 100)),
		displaced_stack_id,
		Dictionary(displaced.get("metadata", {})).duplicate(true),
		String(displaced.get("quantity_encoding", ""))
	)
	if not bool(displaced_restore.get("ok", false)):
		return displaced_restore
	return _success({
		"inventory": displaced_restore["inventory"],
		"incoming_stack_id": incoming_stack_id,
		"displaced_stack_id": displaced_stack_id,
		"target_container_id": target_container_id,
	})


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": ""}
	result.merge(extra, true)
	return result


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
