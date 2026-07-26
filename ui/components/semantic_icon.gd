class_name SemanticIcon
extends TextureRect

## Non-interactive renderer for an icon registered by semantic ID.

const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")
const DEFAULT_SIZE := 24
const SUPPORTED_SIZES := [16, 20, 24, 32]

@export var icon_id: StringName = &""
@export_enum("16:16", "20:20", "24:24", "32:32") var icon_size_dp := DEFAULT_SIZE
@export var icon_colour := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _ready() -> void:
	icon_size_dp = _normalise_size(icon_size_dp)
	_apply_size()
	self_modulate = icon_colour
	_refresh_texture()


## Returns whether the requested authored texture is currently available.
func present(
	next_icon_id: StringName,
	size_dp: int = DEFAULT_SIZE,
	colour: Color = Color.WHITE
) -> bool:
	icon_id = next_icon_id
	icon_size_dp = _normalise_size(size_dp)
	icon_colour = colour
	_apply_size()
	self_modulate = icon_colour
	_refresh_texture()
	return texture != null


func clear() -> void:
	icon_id = &""
	texture = null
	visible = false


func _refresh_texture() -> void:
	if icon_id.is_empty():
		texture = null
		visible = false
		return
	texture = IconRegistryScript.texture(icon_id)
	visible = texture != null


func _apply_size() -> void:
	custom_minimum_size = Vector2(icon_size_dp, icon_size_dp)


func _normalise_size(requested: int) -> int:
	return requested if SUPPORTED_SIZES.has(requested) else DEFAULT_SIZE
