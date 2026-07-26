class_name MapHotspotLayer
extends Control

signal destination_requested(destination_id: String)
signal hovered_changed(destination_id: String)
signal focused_changed(destination_id: String)

const MapNodeHotspotScript := preload("res://ui/components/map_node_hotspot.gd")
const MapNodeHotspotScene := preload("res://ui/components/map_node_hotspot.tscn")

const TOUCH_SIZE := Vector2(56, 56)

var _models: Array[Dictionary] = []
var _hotspots: Dictionary = {}
var _selected_id := ""
var _locked := false
var _hovered_id := ""
var _focused_id := ""


func present(models: Array[Dictionary], selected_id: String, locked: bool) -> void:
	_models.clear()
	for model: Dictionary in models:
		_models.append(model.duplicate(true))
	_selected_id = selected_id
	_locked = locked
	_rebuild()


func set_selected(destination_id: String) -> void:
	_selected_id = destination_id
	for node_id: String in _hotspots:
		var hotspot := _hotspots[node_id] as MapNodeHotspotScript
		if hotspot != null:
			hotspot.set_selected(node_id == _selected_id)


func set_locked(locked: bool) -> void:
	_locked = locked
	for raw_hotspot: Variant in _hotspots.values():
		var hotspot := raw_hotspot as MapNodeHotspotScript
		if hotspot != null:
			hotspot.disabled = _locked


func hotspot(destination_id: String) -> MapNodeHotspotScript:
	return _hotspots.get(destination_id) as MapNodeHotspotScript


func _rebuild() -> void:
	for raw_hotspot: Variant in _hotspots.values():
		var hotspot := raw_hotspot as MapNodeHotspotScript
		if hotspot != null:
			remove_child(hotspot)
			hotspot.queue_free()
	_hotspots.clear()
	_hovered_id = ""
	_focused_id = ""
	for model: Dictionary in _models:
		var node_id := String(model.get("id", ""))
		if node_id.is_empty():
			continue
		var hotspot := MapNodeHotspotScene.instantiate() as MapNodeHotspotScript
		add_child(hotspot)
		hotspot.present(node_id, String(model.get("title", node_id)))
		hotspot.position = Vector2(model.get("center", Vector2.ZERO)) - TOUCH_SIZE * 0.5
		hotspot.size = TOUCH_SIZE
		hotspot.set_selected(node_id == _selected_id)
		hotspot.disabled = _locked
		hotspot.destination_requested.connect(destination_requested.emit)
		hotspot.mouse_entered.connect(_on_hovered.bind(node_id, true))
		hotspot.mouse_exited.connect(_on_hovered.bind(node_id, false))
		hotspot.focus_entered.connect(_on_focused.bind(node_id, true))
		hotspot.focus_exited.connect(_on_focused.bind(node_id, false))
		_hotspots[node_id] = hotspot


func _on_hovered(node_id: String, hovered: bool) -> void:
	_hovered_id = node_id if hovered else "" if _hovered_id == node_id else _hovered_id
	hovered_changed.emit(_hovered_id)


func _on_focused(node_id: String, focused: bool) -> void:
	_focused_id = node_id if focused else "" if _focused_id == node_id else _focused_id
	focused_changed.emit(_focused_id)
