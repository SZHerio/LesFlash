class_name PolarityTrack
extends Control

## A two-sided axis: the centre is a real position, not an absence of one, so
## the fill runs from the middle outwards rather than from the left edge. A
## plain progress bar would say "almost empty" where the truth is "leaning
## slightly towards Мощь".

const TRACK_HEIGHT := 4.0
const MARKER_RADIUS := 5.0

var _value := 0
var _formed := true


func present(value: int, formed: bool) -> void:
	_value = clampi(value, GameRules.POLARITY_MIN, GameRules.POLARITY_MAX)
	_formed = formed
	queue_redraw()


func _draw() -> void:
	var middle := size.y * 0.5
	var centre_x := size.x * 0.5
	var track := get_theme_color(&"font_color", &"MutedLabel")
	draw_rect(
		Rect2(Vector2(0.0, middle - TRACK_HEIGHT * 0.5), Vector2(size.x, TRACK_HEIGHT)),
		Color(track, 0.18)
	)
	draw_rect(
		Rect2(Vector2(centre_x - 0.5, middle - TRACK_HEIGHT), Vector2(1.0, TRACK_HEIGHT * 2.0)),
		Color(track, 0.45)
	)
	if not _formed:
		return
	var offset := centre_x * (float(_value) / float(GameRules.POLARITY_MAX))
	var accent := get_theme_color(&"font_color", &"SectionTitle")
	if absf(offset) >= 1.0:
		var from_x := minf(centre_x, centre_x + offset)
		draw_rect(
			Rect2(
				Vector2(from_x, middle - TRACK_HEIGHT * 0.5),
				Vector2(absf(offset), TRACK_HEIGHT)
			),
			Color(accent, 0.85)
		)
	draw_circle(Vector2(centre_x + offset, middle), MARKER_RADIUS, accent)
