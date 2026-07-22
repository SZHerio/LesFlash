extends SceneTree

const SafeArea := preload("res://app/android/safe_area_layout.gd")


func _init() -> void:
	var normal := SafeArea.compute(Vector2(360, 640), Vector2i(1080, 1920), Rect2i(0, 0, 1080, 1920), true)
	_expect(normal, {"left": 16.0, "top": 16.0, "right": 16.0, "bottom": 16.0}, "full screen")

	var cutout := SafeArea.compute(Vector2(360, 800), Vector2i(1080, 2400), Rect2i(0, 120, 1080, 2160), true)
	_expect(cutout, {"left": 16.0, "top": 56.0, "right": 16.0, "bottom": 56.0}, "cutout and gesture inset")

	var desktop := SafeArea.compute(Vector2(540, 960), Vector2i(1920, 1080), Rect2i(100, 100, 1720, 880), false)
	_expect(desktop, {"left": 16.0, "top": 16.0, "right": 16.0, "bottom": 16.0}, "desktop ignores display work area")

	print("SAFE AREA TEST PASSED: base, cutout, gesture and desktop cases")
	quit(0)


func _expect(actual: Dictionary, expected: Dictionary, context: String) -> void:
	for key in expected:
		if not is_equal_approx(float(actual.get(key, -1.0)), float(expected[key])):
			push_error("SAFE AREA FAILED (%s): %s expected %s, got %s" % [context, key, expected[key], actual.get(key)])
			quit(1)
