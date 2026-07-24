class_name SearchQuickSearch
extends RefCounted

const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const InteractionTransaction := preload(
	"res://game/search/search_interaction_transaction.gd"
)


static func execute(session: Object, snapshot: Dictionary) -> Dictionary:
	var run_state: RunState = session.get("run_state")
	var resolved := InteractionResolver.exhausted_count(snapshot)
	if (
		resolved < InteractionTransaction.QUICK_SEARCH_RESOLVED_REQUIRED
		or run_state.get_skill_rank("search") < 1
	):
		return _failure(
			"quick_search_locked",
			"Быстрый поиск откроется после освоения шести объектов зоны."
		)
	var working := snapshot.duplicate(true)
	var resolved_objects: Array[String] = []
	var transactions: Array = []
	var ground_items: Array = []
	for raw_object: Variant in Array(working.get("objects", [])):
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = raw_object
		if (
			String(object.get("state", "")) == "exhausted"
			or bool(object.get("interacted", false))
		):
			continue
		var selected := _first_allowed(run_state, working, object)
		if selected.is_empty():
			continue
		_move_to_object(working, object)
		var applied := InteractionTransaction.apply(
			session,
			working,
			String(object.get("id", "")),
			String(selected.get("id", "")),
			false
		)
		if not bool(applied.get("ok", false)):
			return applied
		working = applied["snapshot"]
		resolved_objects.append(String(object.get("id", "")))
		transactions.append(Dictionary(applied.get("transaction", {})).duplicate(true))
		for raw_ground: Variant in Array(applied.get("ground_items", [])):
			if raw_ground is Dictionary:
				ground_items.append(Dictionary(raw_ground).duplicate(true))
		if not Dictionary(applied.get("encounter", {})).is_empty():
			break
	if resolved_objects.is_empty():
		return _failure(
			"quick_search_no_available_objects",
			"Для быстрого поиска не осталось доступных действий."
		)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"snapshot": working,
		"resolved_object_ids": resolved_objects,
		"transactions": transactions,
		"ground_items": ground_items,
		"encounter": Dictionary(working.get("pending_encounter", {})).duplicate(true),
	}


static func _first_allowed(
	run_state: RunState,
	snapshot: Dictionary,
	object: Dictionary
) -> Dictionary:
	for raw_approach: Variant in Array(object.get("approaches", [])):
		if not raw_approach is Dictionary:
			continue
		var approach: Dictionary = raw_approach
		var preview := InteractionResolver.preview(
			run_state,
			snapshot,
			String(object.get("id", "")),
			String(approach.get("id", "")),
			false
		)
		if bool(preview.get("ok", false)) and bool(preview.get("allowed", false)):
			return approach.duplicate(true)
	return {}


static func _move_to_object(snapshot: Dictionary, object: Dictionary) -> void:
	var player: Dictionary = Dictionary(snapshot.get("player", {})).duplicate(true)
	player["node_id"] = String(object.get("approach_node", ""))
	player["position"] = _node_position(
		Dictionary(snapshot.get("walk_graph", {})),
		String(object.get("approach_node", ""))
	)
	player["planned_nodes"] = []
	player["planned_path"] = []
	player["path_index"] = 0
	player["focus_object_id"] = ""
	snapshot["player"] = player


static func _node_position(graph: Dictionary, node_id: String) -> Array:
	for raw_node: Variant in Array(graph.get("nodes", [])):
		if raw_node is Dictionary and String(raw_node.get("id", "")) == node_id:
			return Array(raw_node.get("position", [0, 0])).duplicate()
	return [0, 0]


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
