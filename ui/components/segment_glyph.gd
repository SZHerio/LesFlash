class_name SegmentGlyph
extends Control

## Vector marks for segmented options.
##
## Drawn rather than imported: the shapes are a few lines each, they scale with
## the row instead of needing a texture per density, and they take the current
## font colour so they stay correct in every button state.

const WALK := "walk"
const BUS := "bus"
const TRAM := "tram"


func _draw() -> void:
	var icon_id := String(get_meta(&"icon_id", ""))
	if icon_id.is_empty():
		return
	var colour := get_theme_color(&"font_color", &"Button")
	var centre := size * 0.5
	match icon_id:
		WALK:
			_draw_walk(centre, colour)
		BUS:
			_draw_bus(centre, colour)
		TRAM:
			_draw_tram(centre, colour)
		_:
			draw_circle(centre, 3.0, colour)


func _draw_walk(centre: Vector2, colour: Color) -> void:
	draw_circle(centre + Vector2(0.5, -7.0), 2.6, colour)
	draw_line(centre + Vector2(0, -4.5), centre + Vector2(-0.5, 1.0), colour, 1.8)
	draw_line(centre + Vector2(-0.5, 1.0), centre + Vector2(-3.5, 7.0), colour, 1.8)
	draw_line(centre + Vector2(-0.5, 1.0), centre + Vector2(3.5, 6.5), colour, 1.8)
	draw_line(centre + Vector2(0, -3.0), centre + Vector2(-4.0, -0.5), colour, 1.6)
	draw_line(centre + Vector2(0, -3.0), centre + Vector2(4.0, -1.5), colour, 1.6)


func _draw_tram(centre: Vector2, colour: Color) -> void:
	_draw_bus(centre, colour)
	draw_line(centre + Vector2(2.0, -7.0), centre + Vector2(6.0, -10.0), colour, 1.3)


func _draw_bus(centre: Vector2, colour: Color) -> void:
	draw_rect(
		Rect2(centre + Vector2(-7.0, -7.0), Vector2(14.0, 11.0)),
		colour,
		false,
		1.6
	)
	draw_line(centre + Vector2(-7.0, -2.5), centre + Vector2(7.0, -2.5), colour, 1.4)
	draw_line(centre + Vector2(0.0, -7.0), centre + Vector2(0.0, -2.5), colour, 1.4)
	draw_circle(centre + Vector2(-4.0, 5.0), 2.0, colour)
	draw_circle(centre + Vector2(4.0, 5.0), 2.0, colour)
