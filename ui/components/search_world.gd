class_name SearchWorld
extends Control

signal move_requested(target: Vector2, focus_object_id: String)
signal object_requested(object_id: String)
signal movement_checkpoint(position: Vector2, path_index: int, completed: bool)

const HERO_SPEED := 250.0
const CHECKPOINT_SECONDS := 0.45
const HOTSPOT_TOUCH_RADIUS := 52.0
const SearchWorldRenderer := preload("res://ui/components/search_world_renderer.gd")

var _texture: Texture2D
var _world_size := Vector2(1648.0, 960.0)
var _hero_position := Vector2(823.0, 912.0)
var _camera_position := Vector2.ZERO
var _path: Array[Vector2] = []
var _path_index := 0
var _path_offset := 0
var _objects: Array[Dictionary] = []
var _reduced_motion := false
var _walk_clock := 0.0
var _checkpoint_clock := 0.0
var _focus_object_id := ""
var _tap_position := Vector2.ZERO
var _tap_visible := false
var _facing := Vector2(0.0, -1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	set_process(true)
	queue_redraw()


func present(model: Dictionary) -> void:
	_reduced_motion = bool(model.get("reduced_motion", false))
	_world_size = _vector_from(model.get("world_size", [1648, 960]), _world_size)
	_set_psyche_intensity(float(model.get("psyche_intensity", 0.0)))
	var background_path := String(model.get(
		"background_path",
		"res://assets/search/underpass_service_yard_v1.png"
	))
	_texture = (
		load(background_path) as Texture2D
		if ResourceLoader.exists(background_path)
		else null
	)
	var hero: Dictionary = Dictionary(model.get("hero", {}))
	_hero_position = _vector_from(hero.get("position", [823, 912]), _hero_position)
	_objects = _dictionary_array(model.get("objects", []))
	var full_path := _vector_array(model.get("path", hero.get("planned_path", [])))
	_path_offset = clampi(int(hero.get("path_index", 0)), 0, full_path.size())
	_path = full_path.slice(_path_offset)
	_path_index = 0
	_focus_object_id = String(hero.get("focus_object_id", ""))
	_tap_visible = false
	_snap_camera()
	queue_redraw()


func animate_path(path: Array, focus_object_id: String = "") -> void:
	_path = _vector_array(path)
	_path_index = 0
	_path_offset = 0
	_focus_object_id = focus_object_id
	if _reduced_motion and not _path.is_empty():
		_hero_position = _path.back()
		_path_index = _path.size()
		_snap_camera()
		movement_checkpoint.emit(_hero_position, _path_index, true)
		_complete_path()
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func hero_position() -> Vector2:
	return _hero_position


func object_screen_position(object_id: String) -> Vector2:
	var object := _object_by_id(object_id)
	return (
		_vector_from(object.get("position", [0, 0]), Vector2.ZERO) - _camera_position
		if not object.is_empty()
		else Vector2(-1.0, -1.0)
	)


func is_moving() -> bool:
	return not _path.is_empty()


func _gui_input(event: InputEvent) -> void:
	var local_position := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		local_position = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton:
		local_position = event.position
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	var world_position := _clamp_world(local_position + _camera_position)
	var object := _object_at(world_position)
	if object.is_empty():
		_request_move(world_position, "")
	else:
		var object_id := String(object.get("id", ""))
		var object_position := _vector_from(object.get("position", [0, 0]), world_position)
		var radius := float(object.get("interaction_radius", 112))
		if _hero_position.distance_to(object_position) <= radius:
			object_requested.emit(object_id)
		else:
			_request_move(object_position, object_id)
	accept_event()


func _request_move(world_position: Vector2, object_id: String) -> void:
	_focus_object_id = object_id
	_tap_position = world_position
	_tap_visible = true
	move_requested.emit(world_position, object_id)
	queue_redraw()


func _process(delta: float) -> void:
	_walk_clock += delta
	_checkpoint_clock += delta
	if not _path.is_empty() and _path_index < _path.size():
		var target := _path[_path_index]
		var direction := target - _hero_position
		if direction.length_squared() > 1.0:
			_facing = direction.normalized()
		_hero_position = _hero_position.move_toward(target, HERO_SPEED * delta)
		if _hero_position.distance_to(target) < 1.5:
			_hero_position = target
			_path_index += 1
		var completed := _path_index >= _path.size()
		if completed or _checkpoint_clock >= CHECKPOINT_SECONDS:
			_checkpoint_clock = 0.0
			movement_checkpoint.emit(
				_hero_position,
				_path_offset + _path_index,
				completed
			)
		if completed:
			_complete_path()
	_follow_camera(delta)
	queue_redraw()


func _complete_path() -> void:
	_path.clear()
	_path_index = 0
	_path_offset = 0
	_tap_visible = false
	if not _focus_object_id.is_empty():
		var focused := _object_by_id(_focus_object_id)
		if not focused.is_empty():
			var radius := float(focused.get("interaction_radius", 112))
			var position := _vector_from(focused.get("position", [0, 0]), _hero_position)
			if _hero_position.distance_to(position) <= radius:
				object_requested.emit(_focus_object_id)
	_focus_object_id = ""


func _draw() -> void:
	SearchWorldRenderer.draw_scene(self, {
		"texture": _texture,
		"world_size": _world_size,
		"camera": _camera_position,
		"hero_position": _hero_position,
		"facing": _facing,
		"path": _path,
		"path_index": _path_index,
		"objects": _objects,
		"focus_object_id": _focus_object_id,
		"tap_position": _tap_position,
		"tap_visible": _tap_visible,
		"walk_clock": _walk_clock,
		"moving": not _path.is_empty(),
		"reduced_motion": _reduced_motion,
	})


func _follow_camera(delta: float) -> void:
	var target := _camera_target()
	_camera_position = (
		target
		if _reduced_motion
		else _camera_position.lerp(target, clampf(delta * 5.5, 0.0, 1.0))
	)


func _snap_camera() -> void:
	_camera_position = _camera_target()


func _camera_target() -> Vector2:
	var desired := _hero_position - size * Vector2(0.5, 0.61)
	return Vector2(
		clampf(desired.x, 0.0, maxf(_world_size.x - size.x, 0.0)),
		clampf(desired.y, 0.0, maxf(_world_size.y - size.y, 0.0))
	)


func _clamp_world(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, 0.0, _world_size.x),
		clampf(position.y, 0.0, _world_size.y)
	)


func _object_at(position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := HOTSPOT_TOUCH_RADIUS
	for object: Dictionary in _objects:
		if not bool(object.get("revealed", true)):
			continue
		var distance := position.distance_to(
			_vector_from(object.get("position", [0, 0]), position)
		)
		if distance < best_distance:
			best_distance = distance
			best = object
	return best


func _object_by_id(object_id: String) -> Dictionary:
	for object: Dictionary in _objects:
		if String(object.get("id", "")) == object_id:
			return object
	return {}


func _set_psyche_intensity(value: float) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(
			"psyche_intensity",
			clampf(value, 0.0, 1.0)
		)


func _on_resized() -> void:
	_snap_camera()
	queue_redraw()


static func _vector_from(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


static func _vector_array(value: Variant) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if value is Array:
		for entry: Variant in value:
			result.append(_vector_from(entry, Vector2.ZERO))
	return result


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				result.append(Dictionary(entry).duplicate(true))
	return result
