class_name SearchWorldRenderer
extends RefCounted


static func draw_scene(canvas: Control, model: Dictionary) -> void:
	var camera: Vector2 = model["camera"]
	var world_size: Vector2 = model["world_size"]
	var world_rect := Rect2(-camera, world_size)
	var texture: Texture2D = model.get("texture", null)
	if texture != null:
		canvas.draw_texture_rect(texture, world_rect, false)
	else:
		_draw_fallback_world(canvas, world_rect, world_size, camera)
	_draw_planned_path(canvas, model)
	for raw_object: Variant in Array(model.get("objects", [])):
		if raw_object is Dictionary:
			_draw_object(canvas, Dictionary(raw_object), model)
	if bool(model.get("tap_visible", false)):
		var tap: Vector2 = model["tap_position"] - camera
		canvas.draw_circle(tap, 7.0, Color("#f2c977", 0.28))
		canvas.draw_arc(tap, 15.0, 0.0, TAU, 28, Color("#f2c977", 0.95), 2.0)
	_draw_hero(canvas, model)


static func _draw_planned_path(canvas: Control, model: Dictionary) -> void:
	var path: Array = model["path"]
	if path.is_empty():
		return
	var camera: Vector2 = model["camera"]
	var points := PackedVector2Array([Vector2(model["hero_position"]) - camera])
	for index: int in range(int(model["path_index"]), path.size()):
		points.append(Vector2(path[index]) - camera)
	if points.size() >= 2:
		canvas.draw_polyline(points, Color("#e7c177", 0.58), 3.0, true)


static func _draw_object(
	canvas: Control,
	object: Dictionary,
	model: Dictionary
) -> void:
	if not bool(object.get("revealed", true)):
		return
	var camera: Vector2 = model["camera"]
	var hero_position: Vector2 = model["hero_position"]
	var world_position := _vector_from(object.get("position", [0, 0]))
	var position := world_position - camera
	if not Rect2(Vector2.ZERO, canvas.size).grow(72.0).has_point(position):
		return
	var interacted := bool(object.get("interacted", false))
	var near := hero_position.distance_to(world_position) <= float(
		object.get("interaction_radius", 112)
	)
	var focused := String(object.get("id", "")) == String(
		model.get("focus_object_id", "")
	)
	var color := _object_color(String(object.get("type", "open")))
	if interacted:
		color = Color("#87919a")
	var pulse := (
		1.0 + sin(float(model["walk_clock"]) * 4.0) * 0.09
		if near and not bool(model["reduced_motion"])
		else 1.0
	)
	canvas.draw_circle(position, 21.0 * pulse, Color(0.03, 0.05, 0.055, 0.68))
	canvas.draw_circle(position, 17.0 * pulse, Color(color, 0.16 if not near else 0.3))
	canvas.draw_arc(position, 19.0 * pulse, 0.0, TAU, 30, Color(color, 0.95), 2.5)
	_draw_object_mark(
		canvas,
		position,
		String(object.get("type", "open")),
		color,
		interacted
	)
	if near or focused:
		_draw_object_label(
			canvas,
			position,
			String(object.get("title", "Объект")),
			color
		)


static func _draw_object_mark(
	canvas: Control,
	position: Vector2,
	type_id: String,
	color: Color,
	interacted: bool
) -> void:
	if interacted:
		canvas.draw_line(position + Vector2(-5, 0), position + Vector2(-1, 5), color, 2.5)
		canvas.draw_line(position + Vector2(-1, 5), position + Vector2(7, -6), color, 2.5)
	elif type_id in ["locked", "trespass"]:
		canvas.draw_rect(Rect2(position + Vector2(-6, -1), Vector2(12, 10)), color, false, 2.0)
		canvas.draw_arc(position + Vector2(0, -2), 6.0, PI, TAU, 14, color, 2.0)
	elif type_id == "social":
		canvas.draw_circle(position + Vector2(0, -5), 4.0, color)
		canvas.draw_arc(position + Vector2(0, 8), 8.0, PI, TAU, 14, color, 2.0)
	else:
		canvas.draw_line(position + Vector2(-7, 0), position + Vector2(7, 0), color, 2.0)
		canvas.draw_line(position + Vector2(0, -7), position + Vector2(0, 7), color, 2.0)


static func _draw_object_label(
	canvas: Control,
	position: Vector2,
	title: String,
	color: Color
) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 13
	var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var width := minf(text_size.x + 18.0, 220.0)
	var rect := Rect2(
		Vector2(
			clampf(
				position.x - width * 0.5,
				6.0,
				maxf(canvas.size.x - width - 6.0, 6.0)
			),
			position.y - 54.0
		),
		Vector2(width, 28.0)
	)
	canvas.draw_style_box(_label_style(color), rect)
	canvas.draw_string(
		font,
		rect.position + Vector2(9.0, 19.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 18.0,
		font_size,
		Color("#f2f0e9")
	)


static func _draw_hero(canvas: Control, model: Dictionary) -> void:
	var position: Vector2 = model["hero_position"] - model["camera"]
	var moving := bool(model["moving"])
	var phase := float(model["walk_clock"]) * 11.0
	var reduced_motion := bool(model["reduced_motion"])
	var bob := sin(phase * 2.0) * 1.4 if moving and not reduced_motion else 0.0
	var stride := sin(phase) * 5.0 if moving and not reduced_motion else 1.5
	_draw_ellipse(
		canvas,
		Rect2(position + Vector2(-12, 11), Vector2(24, 8)),
		Color(0.02, 0.025, 0.03, 0.48)
	)
	canvas.draw_line(position + Vector2(-4, 7 + bob), position + Vector2(-5 + stride, 18), Color("#20282b"), 4.0)
	canvas.draw_line(position + Vector2(4, 7 + bob), position + Vector2(5 - stride, 18), Color("#20282b"), 4.0)
	var coat := PackedVector2Array([
		position + Vector2(-9, -6 + bob),
		position + Vector2(8, -6 + bob),
		position + Vector2(11, 10 + bob),
		position + Vector2(-10, 10 + bob),
	])
	canvas.draw_colored_polygon(coat, Color("#31494c"))
	canvas.draw_polyline(coat, Color("#9bb0aa", 0.58), 1.2)
	canvas.draw_line(position + Vector2(-8, -2 + bob), position + Vector2(-13 - stride * 0.35, 7), Color("#31494c"), 4.0)
	canvas.draw_line(position + Vector2(8, -2 + bob), position + Vector2(13 + stride * 0.35, 7), Color("#31494c"), 4.0)
	var facing: Vector2 = model["facing"]
	canvas.draw_circle(position + Vector2(facing.x * 1.5, -14 + bob), 7.0, Color("#d0aa82"))
	canvas.draw_arc(position + Vector2(0, -14 + bob), 7.0, PI, TAU, 12, Color("#40352f"), 3.0)
	canvas.draw_arc(position, 24.0, 0.0, TAU, 32, Color("#e6c171", 0.46), 1.5)


static func _draw_fallback_world(
	canvas: Control,
	rect: Rect2,
	world_size: Vector2,
	camera: Vector2
) -> void:
	canvas.draw_rect(rect, Color("#30343a"))
	for x: int in range(0, int(world_size.x), 96):
		canvas.draw_line(
			Vector2(x, 0) - camera,
			Vector2(x, world_size.y) - camera,
			Color(1, 1, 1, 0.025)
		)


static func _draw_ellipse(canvas: Control, rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var points := PackedVector2Array()
	for index: int in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(
			cos(angle) * rect.size.x * 0.5,
			sin(angle) * rect.size.y * 0.5
		))
	canvas.draw_colored_polygon(points, color)


static func _object_color(type_id: String) -> Color:
	match type_id:
		"locked", "trespass":
			return Color("#df8e82")
		"heavy", "hazardous":
			return Color("#e4bd73")
		"social":
			return Color("#83b8d5")
		_:
			return Color("#83c9aa")


static func _label_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.048, 0.052, 0.93)
	style.border_color = Color(color, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style


static func _vector_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO
