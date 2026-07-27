class_name FocusedTextureRect
extends Control

## Draws a texture with aspect-cover while keeping an authored normalized
## focus point inside the visible crop. TextureRect's built-in cover mode is
## always centre-biased, which cuts faces out of tall portrait artwork.

const DEFAULT_FOCUS := Vector2(0.5, 0.35)

var _texture: Texture2D
var _focus := DEFAULT_FOCUS
var _crop_mode := "focus_cover"


func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func present(
	texture: Texture2D,
	normalized_focus: Vector2 = DEFAULT_FOCUS,
	crop_mode: String = "focus_cover"
) -> void:
	_texture = texture
	_crop_mode = crop_mode if crop_mode == "focus_cover" else "focus_cover"
	_focus = Vector2(
		clampf(normalized_focus.x, 0.0, 1.0),
		clampf(normalized_focus.y, 0.0, 1.0)
	)
	queue_redraw()


func focus_normalized() -> Vector2:
	return _focus


func crop_mode() -> String:
	return _crop_mode


func has_texture() -> bool:
	return _texture != null


func _draw() -> void:
	if _texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var texture_size := _texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var cover_scale := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var source_size := Vector2(size.x, size.y) / cover_scale
	source_size.x = minf(source_size.x, texture_size.x)
	source_size.y = minf(source_size.y, texture_size.y)
	var source_origin := _focus * texture_size - source_size * 0.5
	var max_origin := texture_size - source_size
	source_origin.x = clampf(source_origin.x, 0.0, max_origin.x)
	source_origin.y = clampf(source_origin.y, 0.0, max_origin.y)
	draw_texture_rect_region(
		_texture,
		Rect2(Vector2.ZERO, size),
		Rect2(source_origin, source_size)
	)
