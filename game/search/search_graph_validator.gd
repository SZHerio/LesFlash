class_name SearchGraphValidator
extends RefCounted

## Structural validation for authored search-zone navigation. The runtime does
## not infer walkable geometry from the illustration: designers provide a graph
## and obstacles that can be reviewed and reproduced exactly.


static func validate(template: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var map_value: Variant = template.get("map", null)
	if not map_value is Dictionary:
		return {"ok": false, "errors": ["map должен быть объектом"]}
	var map_data: Dictionary = map_value
	var size: Variant = _point(map_data.get("size", null))
	if size == null or size.x <= 0.0 or size.y <= 0.0:
		errors.append("map.size должен содержать положительные ширину и высоту")
	var asset := String(map_data.get("asset", "")).strip_edges()
	if asset.is_empty() or not FileAccess.file_exists(asset):
		errors.append("map.asset не найден: %s" % asset)

	var graph_value: Variant = template.get("walk_graph", null)
	if not graph_value is Dictionary:
		errors.append("walk_graph должен быть объектом")
		return {"ok": errors.is_empty(), "errors": errors}
	var graph: Dictionary = graph_value
	var nodes := _validate_nodes(graph.get("nodes", null), size, errors)
	var adjacency := _validate_edges(graph.get("edges", null), nodes, errors)
	_validate_obstacles(graph.get("obstacles", null), size, errors)

	var spawn_node := String(map_data.get("spawn_node", "")).strip_edges()
	if not nodes.has(spawn_node):
		errors.append("map.spawn_node ссылается на неизвестный узел «%s»" % spawn_node)
	elif _reachable(adjacency, spawn_node).size() != nodes.size():
		errors.append("walk_graph содержит недостижимые от spawn_node узлы")
	return {"ok": errors.is_empty(), "errors": errors}


static func node_ids(template: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var graph: Variant = template.get("walk_graph", null)
	if not graph is Dictionary:
		return result
	var nodes: Variant = graph.get("nodes", null)
	if not nodes is Array:
		return result
	for raw_node: Variant in nodes:
		if raw_node is Dictionary:
			var node_id := String(raw_node.get("id", "")).strip_edges()
			if not node_id.is_empty():
				result[node_id] = true
	return result


static func _validate_nodes(raw_nodes: Variant, size: Variant, errors: Array[String]) -> Dictionary:
	var nodes: Dictionary = {}
	if not raw_nodes is Array or raw_nodes.is_empty():
		errors.append("walk_graph.nodes должен быть непустым массивом")
		return nodes
	for index: int in raw_nodes.size():
		var raw_node: Variant = raw_nodes[index]
		if not raw_node is Dictionary:
			errors.append("walk_graph.nodes[%d] должен быть объектом" % index)
			continue
		var node_id := String(raw_node.get("id", "")).strip_edges()
		var position: Variant = _point(raw_node.get("position", null))
		if node_id.is_empty() or nodes.has(node_id):
			errors.append("walk_graph.nodes[%d] содержит пустой или повторный id" % index)
			continue
		if position == null:
			errors.append("walk_graph.nodes[%d].position некорректна" % index)
			continue
		if size is Vector2 and not _inside(position, size):
			errors.append("Узел «%s» находится за пределами карты" % node_id)
		nodes[node_id] = position
	return nodes


static func _validate_edges(raw_edges: Variant, nodes: Dictionary, errors: Array[String]) -> Dictionary:
	var adjacency: Dictionary = {}
	for node_id: Variant in nodes:
		adjacency[node_id] = []
	if not raw_edges is Array or raw_edges.is_empty():
		errors.append("walk_graph.edges должен быть непустым массивом")
		return adjacency
	var seen: Dictionary = {}
	for index: int in raw_edges.size():
		var raw_edge: Variant = raw_edges[index]
		if not raw_edge is Dictionary:
			errors.append("walk_graph.edges[%d] должен быть объектом" % index)
			continue
		var from_id := String(raw_edge.get("from", "")).strip_edges()
		var to_id := String(raw_edge.get("to", "")).strip_edges()
		var bidirectional: Variant = raw_edge.get("bidirectional", null)
		if not nodes.has(from_id) or not nodes.has(to_id):
			errors.append("walk_graph.edges[%d] ссылается на неизвестный узел" % index)
			continue
		if from_id == to_id:
			errors.append("walk_graph.edges[%d] образует петлю" % index)
			continue
		if typeof(bidirectional) != TYPE_BOOL:
			errors.append("walk_graph.edges[%d].bidirectional должен быть bool" % index)
			continue
		var key := "%s>%s" % [from_id, to_id]
		if seen.has(key):
			errors.append("Повторное ребро walk_graph «%s»" % key)
			continue
		seen[key] = true
		adjacency[from_id].append(to_id)
		if bool(bidirectional):
			adjacency[to_id].append(from_id)
	return adjacency


static func _validate_obstacles(raw_obstacles: Variant, size: Variant, errors: Array[String]) -> void:
	if not raw_obstacles is Array:
		errors.append("walk_graph.obstacles должен быть массивом")
		return
	var seen: Dictionary = {}
	for index: int in raw_obstacles.size():
		var raw_obstacle: Variant = raw_obstacles[index]
		if not raw_obstacle is Dictionary:
			errors.append("walk_graph.obstacles[%d] должен быть объектом" % index)
			continue
		var obstacle_id := String(raw_obstacle.get("id", "")).strip_edges()
		if obstacle_id.is_empty() or seen.has(obstacle_id):
			errors.append("walk_graph.obstacles[%d] содержит пустой или повторный id" % index)
		else:
			seen[obstacle_id] = true
		var polygon: Variant = raw_obstacle.get("polygon", null)
		if not polygon is Array or polygon.size() < 3:
			errors.append("Препятствие «%s» должно иметь полигон минимум из трёх точек" % obstacle_id)
			continue
		for raw_point: Variant in polygon:
			var point: Variant = _point(raw_point)
			if point == null or (size is Vector2 and not _inside(point, size)):
				errors.append("Препятствие «%s» содержит точку за пределами карты" % obstacle_id)
				break


static func _reachable(adjacency: Dictionary, start_id: String) -> Dictionary:
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for raw_neighbor: Variant in Array(adjacency.get(current, [])):
			var neighbor := String(raw_neighbor)
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited


static func _point(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	if typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var x := float(value[0])
	var y := float(value[1])
	if not is_finite(x) or not is_finite(y):
		return null
	return Vector2(x, y)


static func _inside(point: Vector2, size: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= size.x and point.y <= size.y
