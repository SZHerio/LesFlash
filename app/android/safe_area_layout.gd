class_name SafeAreaLayout
extends RefCounted


static func compute(
	viewport_size: Vector2,
	screen_size: Vector2i,
	safe_rect: Rect2i,
	include_system_insets: bool,
	base_margin: float = 16.0
) -> Dictionary:
	var margins := {
		"left": maxf(base_margin, 0.0),
		"top": maxf(base_margin, 0.0),
		"right": maxf(base_margin, 0.0),
		"bottom": maxf(base_margin, 0.0),
	}
	if (
		include_system_insets
		and viewport_size.x > 0.0
		and viewport_size.y > 0.0
		and screen_size.x > 0
		and screen_size.y > 0
		and safe_rect.size.x > 0
		and safe_rect.size.y > 0
	):
		var clipped := safe_rect.intersection(Rect2i(Vector2i.ZERO, screen_size))
		if clipped.size.x > 0 and clipped.size.y > 0:
			var ratio := viewport_size / Vector2(screen_size)
			margins.left += float(clipped.position.x) * ratio.x
			margins.top += float(clipped.position.y) * ratio.y
			margins.right += float(screen_size.x - clipped.end.x) * ratio.x
			margins.bottom += float(screen_size.y - clipped.end.y) * ratio.y
	return margins
