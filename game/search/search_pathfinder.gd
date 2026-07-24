class_name SearchPathfinder
extends RefCounted

const GraphValidator := preload("res://game/search/search_graph_validator.gd")


static func find_path(template: Dictionary, start_id: String, goal_id: String) -> Dictionary:
	var validation := GraphValidator.validate(template)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_graph", Array(validation.get("errors", [])))
	var graph: Dictionary = template["walk_graph"]
	var positions := _positions(graph)
	if not positions.has(start_id) or not positions.has(goal_id):
		return _failure("unknown_node", ["Начальный или конечный узел отсутствует в walk_graph"])
	var adjacency := _adjacency(graph, positions)
	var distances: Dictionary = {}
	var previous: Dictionary = {}
	var unvisited: Dictionary = {}
	for node_id: Variant in positions:
		distances[node_id] = 0.0 if String(node_id) == start_id else INF
		unvisited[node_id] = true

	while not unvisited.is_empty():
		var current := _nearest(unvisited, distances)
		if current.is_empty() or float(distances[current]) == INF:
			break
		unvisited.erase(current)
		if current == goal_id:
			break
		for raw_neighbor: Variant in Array(adjacency.get(current, [])):
			var edge: Dictionary = raw_neighbor
			var neighbor := String(edge["id"])
			if not unvisited.has(neighbor):
				continue
			var candidate := float(distances[current]) + float(edge["distance"])
			if candidate < float(distances[neighbor]):
				distances[neighbor] = candidate
				previous[neighbor] = current
	if float(distances[goal_id]) == INF:
		return _failure("unreachable", ["Между узлами нет пути"])

	var node_path: Array[String] = [goal_id]
	var cursor := goal_id
	while cursor != start_id:
		if not previous.has(cursor):
			return _failure("unreachable", ["Не удалось восстановить путь"])
		cursor = String(previous[cursor])
		node_path.push_front(cursor)
	var point_path: Array = []
	for node_id: String in node_path:
		var point: Vector2 = positions[node_id]
		point_path.append([point.x, point.y])
	return {
		"ok": true,
		"code": "ok",
		"nodes": node_path,
		"points": point_path,
		"distance": float(distances[goal_id]),
		"errors": [],
	}


static func find_path_to_object(
	template: Dictionary,
	start_id: String,
	object_id: String
) -> Dictionary:
	for raw_object: Variant in Array(template.get("objects", [])):
		if raw_object is Dictionary and String(raw_object.get("id", "")) == object_id:
			return find_path(template, start_id, String(raw_object.get("approach_node", "")))
	return _failure("unknown_object", ["Объект «%s» отсутствует в шаблоне" % object_id])


static func _positions(graph: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_node: Variant in Array(graph["nodes"]):
		var node: Dictionary = raw_node
		var position: Array = node["position"]
		result[String(node["id"])] = Vector2(float(position[0]), float(position[1]))
	return result


static func _adjacency(graph: Dictionary, positions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node_id: Variant in positions:
		result[node_id] = []
	for raw_edge: Variant in Array(graph["edges"]):
		var edge: Dictionary = raw_edge
		var from_id := String(edge["from"])
		var to_id := String(edge["to"])
		var from_position: Vector2 = positions[from_id]
		var to_position: Vector2 = positions[to_id]
		var distance := from_position.distance_to(to_position)
		result[from_id].append({"id": to_id, "distance": distance})
		if bool(edge["bidirectional"]):
			result[to_id].append({"id": from_id, "distance": distance})
	return result


static func _nearest(unvisited: Dictionary, distances: Dictionary) -> String:
	var best_id := ""
	var best_distance := INF
	for raw_node_id: Variant in unvisited:
		var node_id := String(raw_node_id)
		var distance := float(distances[node_id])
		if (
			distance < best_distance
			or (
				distance == best_distance
				and (best_id.is_empty() or node_id.naturalnocasecmp_to(best_id) < 0)
			)
		):
			best_id = node_id
			best_distance = distance
	return best_id


static func _failure(code: String, raw_errors: Array) -> Dictionary:
	var errors: Array[String] = []
	for raw_error: Variant in raw_errors:
		errors.append(String(raw_error))
	return {
		"ok": false,
		"code": code,
		"nodes": [],
		"points": [],
		"distance": 0.0,
		"errors": errors,
	}
