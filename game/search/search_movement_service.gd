class_name SearchMovementService
extends RefCounted

const Pathfinder := preload("res://game/search/search_pathfinder.gd")
const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const CommandService := preload("res://game/search/search_command_service.gd")
const SessionTransaction := preload(
	"res://game/search/search_session_transaction.gd"
)


static func plan_move(
	session: Object,
	target: Variant,
	command_id: String
) -> Dictionary:
	var prepared := CommandService.prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var snapshot: Dictionary = prepared["snapshot"]
	var path_result := _path_to_target(snapshot, target)
	if not bool(path_result.get("ok", false)):
		return path_result
	var player: Dictionary = Dictionary(snapshot.get("player", {})).duplicate(true)
	player["planned_nodes"] = Array(path_result["nodes"]).duplicate()
	player["planned_path"] = Array(path_result["points"]).duplicate(true)
	player["path_index"] = 0
	player["target_node_id"] = String(path_result["nodes"].back())
	player["focus_object_id"] = String(path_result.get("focus_object_id", ""))
	snapshot["player"] = player
	return CommandService.commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(snapshot, command_id),
		{"path": path_result}
	)


static func checkpoint_move(
	session: Object,
	position: Variant,
	path_index: int,
	completed: bool,
	command_id: String
) -> Dictionary:
	var prepared := CommandService.prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var point: Variant = _point(position)
	if point == null:
		return SessionTransaction.failure(
			"invalid_checkpoint",
			"Координаты контрольной точки некорректны."
		)
	var snapshot: Dictionary = prepared["snapshot"]
	var player: Dictionary = Dictionary(snapshot.get("player", {})).duplicate(true)
	var path: Array = Array(player.get("planned_path", []))
	var nodes: Array = Array(player.get("planned_nodes", []))
	if path.is_empty() or path_index < 0 or path_index >= path.size():
		return SessionTransaction.failure(
			"movement_plan_missing",
			"Маршрут движения отсутствует или устарел."
		)
	player["position"] = point
	player["path_index"] = path_index
	if completed:
		player["node_id"] = String(nodes.back())
		player["position"] = Array(path.back()).duplicate()
		_reveal_focus(snapshot, String(player.get("focus_object_id", "")))
		player["planned_nodes"] = []
		player["planned_path"] = []
		player["path_index"] = 0
		player["target_node_id"] = ""
		player["focus_object_id"] = ""
	snapshot["player"] = player
	return CommandService.commit_active(
		session,
		prepared["candidate"],
		SessionTransaction.mark_applied(snapshot, command_id)
	)


static func _path_to_target(snapshot: Dictionary, target: Variant) -> Dictionary:
	var start_id := String(Dictionary(snapshot.get("player", {})).get("node_id", ""))
	var object_id := ""
	var goal_id := ""
	if target is String or target is StringName:
		var identifier := String(target)
		var object := InteractionResolver.find_object(snapshot, identifier)
		if object.is_empty():
			goal_id = identifier
		else:
			object_id = identifier
	elif target is Dictionary:
		object_id = String(target.get("object_id", ""))
		goal_id = String(target.get("node_id", ""))
	else:
		var point: Variant = _point(target)
		if point != null:
			goal_id = _nearest_node(snapshot, point)
	var result := (
		Pathfinder.find_path_to_object(snapshot, start_id, object_id)
		if not object_id.is_empty()
		else Pathfinder.find_path(snapshot, start_id, goal_id)
	)
	if bool(result.get("ok", false)):
		result["focus_object_id"] = object_id
	return result


static func _nearest_node(snapshot: Dictionary, point: Array) -> String:
	var target := Vector2(float(point[0]), float(point[1]))
	var best_id := ""
	var best_distance := INF
	for raw_node: Variant in Array(
		Dictionary(snapshot.get("walk_graph", {})).get("nodes", [])
	):
		if not raw_node is Dictionary:
			continue
		var position: Array = raw_node.get("position", [])
		if position.size() != 2:
			continue
		var distance := target.distance_squared_to(
			Vector2(float(position[0]), float(position[1]))
		)
		var node_id := String(raw_node.get("id", ""))
		if distance < best_distance or (
			distance == best_distance
			and (best_id.is_empty() or node_id < best_id)
		):
			best_distance = distance
			best_id = node_id
	return best_id


static func _reveal_focus(snapshot: Dictionary, object_id: String) -> void:
	if object_id.is_empty():
		return
	var object := InteractionResolver.find_object(snapshot, object_id)
	if object.is_empty():
		return
	object["revealed"] = true
	if String(object.get("state", "")) == "concealed":
		object["state"] = "available"
	var updated := InteractionResolver.replace_object(snapshot, object)
	snapshot.clear()
	snapshot.merge(updated, true)


static func _point(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y] if is_finite(value.x) and is_finite(value.y) else null
	if not value is Array or value.size() != 2:
		return null
	if typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [
		TYPE_INT,
		TYPE_FLOAT,
	]:
		return null
	var point := Vector2(float(value[0]), float(value[1]))
	return [point.x, point.y] if is_finite(point.x) and is_finite(point.y) else null
