extends RefCounted

const MAP_INSET := Vector2(30.0, 30.0)

var nodes: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var nodes_by_id: Dictionary = {}
var current_id := ""


func present(model: Dictionary) -> void:
	nodes.clear()
	routes.clear()
	nodes_by_id.clear()
	for raw_node in model.get("nodes", []):
		if not raw_node is Dictionary:
			continue
		var node_model := Dictionary(raw_node).duplicate(true)
		var node_id := String(node_model.get("id", ""))
		if node_id.is_empty():
			continue
		nodes.append(node_model)
		nodes_by_id[node_id] = node_model
	for raw_route in model.get("routes", []):
		if raw_route is Dictionary:
			routes.append(Dictionary(raw_route).duplicate(true))

	current_id = _resolve_current_id(model.get("current_location", ""))
	if current_id.is_empty():
		for node_model in nodes:
			if bool(node_model.get("current", false)):
				current_id = String(node_model.get("id", ""))
				break


func node_position(node_id: String, map_rect: Rect2) -> Vector2:
	var node_model: Dictionary = nodes_by_id.get(node_id, {})
	var normalized := _normalized_position(node_model.get("position", Vector2(0.5, 0.5)))
	var usable := Vector2(
		maxf(map_rect.size.x - MAP_INSET.x * 2.0, 1.0),
		maxf(map_rect.size.y - MAP_INSET.y * 2.0, 1.0)
	)
	return map_rect.position + MAP_INSET + normalized * usable


func route_endpoint(route: Dictionary, side: String) -> String:
	var direct := String(route.get(side, ""))
	if not direct.is_empty():
		return direct
	if side == "from":
		return String(route.get("origin_id", current_id))
	return String(route.get("destination_id", ""))


func route_available(route: Dictionary) -> bool:
	var modes: Variant = route.get("modes", [])
	if modes is Array and not modes.is_empty():
		for raw_mode in modes:
			if raw_mode is Dictionary and bool(raw_mode.get("available", true)):
				return true
		return false
	return bool(route.get("available", true))


func node_is_known(node_id: String) -> bool:
	return nodes_by_id.has(node_id) and bool(Dictionary(nodes_by_id[node_id]).get("known", true))


func is_selectable(node_id: String) -> bool:
	return not node_id.is_empty() and node_id != current_id and node_is_known(node_id)


func first_selectable_id() -> String:
	for node_model in nodes:
		var node_id := String(node_model.get("id", ""))
		if is_selectable(node_id):
			return node_id
	return ""


func label_lines(title: String, maximum_characters: int) -> Array[String]:
	if title.length() <= maximum_characters:
		return [title]
	var words := title.split(" ", false)
	if words.size() < 2:
		return [_shorten_title(title, maximum_characters)]
	var best_lines: Array[String] = []
	var best_score := 1_000_000
	for split_index in range(1, words.size()):
		var first := " ".join(words.slice(0, split_index))
		var second := " ".join(words.slice(split_index))
		var score := maxi(first.length(), second.length())
		if score < best_score:
			best_score = score
			best_lines = [
				_shorten_title(first, maximum_characters),
				_shorten_title(second, maximum_characters),
			]
	return best_lines


func _resolve_current_id(raw_current: Variant) -> String:
	if raw_current is Dictionary:
		return String(raw_current.get("id", ""))
	return String(raw_current)


func _normalized_position(raw_position: Variant) -> Vector2:
	if raw_position is Vector2:
		return Vector2(clampf(raw_position.x, 0.0, 1.0), clampf(raw_position.y, 0.0, 1.0))
	if raw_position is Array and raw_position.size() >= 2:
		return Vector2(clampf(float(raw_position[0]), 0.0, 1.0), clampf(float(raw_position[1]), 0.0, 1.0))
	if raw_position is Dictionary:
		return Vector2(
			clampf(float(raw_position.get("x", 0.5)), 0.0, 1.0),
			clampf(float(raw_position.get("y", 0.5)), 0.0, 1.0)
		)
	return Vector2(0.5, 0.5)


func _shorten_title(title: String, maximum_characters: int) -> String:
	if title.length() <= maximum_characters:
		return title
	return "%s…" % title.left(maximum_characters - 1).strip_edges()
