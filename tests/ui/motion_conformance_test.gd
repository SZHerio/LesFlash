extends SceneTree

## Keeps motion a system rather than 11 opinions.
##
## Two halves. The first checks the tokens themselves against the intervals in
## UI_UX_STANDARD §4. The second walks every screen and component and fails on a
## script that builds its own tween or writes a duration by hand — that is how
## 0.17 and 0.18 ended up on two sheets that open the same way.

const Motion = preload("res://ui/theme/motion.gd")

## Read as a resource rather than through the `Motion` const: that const
## resolves to the class UiMotion, and a class cannot be asked for its own
## constant map. Reading the map instead of naming each token means a token that
## disappears fails the test rather than silently stopping being checked.
var _tokens: Dictionary = (load("res://ui/theme/motion.gd") as GDScript).get_script_constant_map()

## Nothing is exempt. The legacy M2 screen was the only entry here and M3F.7
## deleted it, so "motion is a system" is now true of every live script.
const EXEMPT: Array[String] = []

## The trip along a map route is not the interface answering a tap, so §4 does
## not govern it. Named explicitly rather than left as an unchecked constant.
const OUTSIDE_STANDARD := ["JOURNEY", "TOAST_DWELL", "TOAST_DWELL_ERROR"]

const INTERVALS := {
	"PRESS": [0.08, 0.12],
	"FADE": [0.18, 0.26],
	"REVEAL": [0.18, 0.26],
	"SHEET": [0.18, 0.26],
	"SCREEN": [0.18, 0.32],
	"METER_MIN": [0.24, 0.45],
	"METER_MAX": [0.24, 0.45],
}

var _failures: Array[String] = []


func _init() -> void:
	_test_tokens_obey_the_standard()
	_test_meter_duration_follows_the_delta()
	_test_reduced_motion_settles_instead_of_animating()
	_test_no_script_rolls_its_own_motion()
	if _failures.is_empty():
		print("MOTION CONFORMANCE PASSED: токены в интервалах стандарта, самодельных твинов нет")
		quit(0)
		return
	for failure in _failures:
		push_error("MOTION: %s" % failure)
	quit(1)


func _test_tokens_obey_the_standard() -> void:
	for name: String in INTERVALS:
		_require(_tokens.has(name), "токен %s исчез" % name)
		if not _tokens.has(name):
			continue
		var bounds: Array = INTERVALS[name]
		var value := float(_tokens[name])
		_require(
			value >= float(bounds[0]) and value <= float(bounds[1]),
			"%s = %.3f вне интервала %.2f–%.2f по стандарту §4"
				% [name, value, float(bounds[0]), float(bounds[1])]
		)
	_require(
		Motion.FADE <= Motion.SHEET,
		"панель проявляется дольше, чем едет: она будет возникать, а не приезжать"
	)
	_require(
		Motion.SCREEN > Motion.REVEAL,
		"смена экрана не длиннее обычного перехода, поэтому смена места читается как раскрытие строки"
	)
	_require(Motion.METER_MIN < Motion.METER_MAX, "интервал показателя вырожден")


func _test_meter_duration_follows_the_delta() -> void:
	_require(
		is_equal_approx(Motion.meter_duration(0.0), Motion.METER_MIN),
		"нулевая дельта не даёт минимальную длительность"
	)
	_require(
		is_equal_approx(Motion.meter_duration(100.0), Motion.METER_MAX),
		"полная дельта не даёт максимальную длительность"
	)
	_require(
		Motion.meter_duration(-60.0) == Motion.meter_duration(60.0),
		"падение показателя длится не столько же, сколько рост"
	)
	_require(
		Motion.meter_duration(500.0) <= Motion.METER_MAX,
		"дельта больше шкалы выводит длительность за потолок"
	)
	_require(
		Motion.meter_duration(10.0, 0.0) == Motion.METER_MIN,
		"нулевая шкала не обработана"
	)


## Reduced motion must leave the same picture, not a half-finished one.
func _test_reduced_motion_settles_instead_of_animating() -> void:
	var host := Control.new()
	var subject := Control.new()
	root.add_child(host)
	host.add_child(subject)
	subject.modulate = Color(1, 1, 1, 0)
	subject.position.x = 10.0

	var tween: Tween = Motion.play(null, host, [
		{"target": subject, "property": "modulate:a", "to": 1.0, "duration": Motion.FADE},
		{"target": subject, "property": "position:x", "to": 0.0, "duration": Motion.SCREEN},
	], true)
	_require(tween == null, "уменьшенное движение всё равно создало твин")
	_require(
		is_equal_approx(subject.modulate.a, 1.0) and is_equal_approx(subject.position.x, 0.0),
		"уменьшенное движение оставило элемент на полпути: a=%.2f x=%.2f"
			% [subject.modulate.a, subject.position.x]
	)

	# Press feedback is the exception: it ends where it began, so settling would
	# hold the control squeezed instead of leaving it alone.
	subject.scale = Vector2.ONE
	var pressed: Tween = Motion.press(null, host, subject, 0.96, true)
	_require(pressed == null, "уменьшенное движение всё равно анимировало нажатие")
	_require(
		subject.scale.is_equal_approx(Vector2.ONE),
		"уменьшенное движение защёлкнуло нажатую кнопку на %s" % subject.scale
	)

	var detached := Control.new()
	var orphan: Tween = Motion.play(null, detached, [
		{"target": detached, "property": "modulate:a", "to": 1.0, "duration": Motion.FADE},
	], false)
	_require(orphan == null, "узел вне дерева получил твин")
	detached.free()
	host.queue_free()


func _test_no_script_rolls_its_own_motion() -> void:
	var offenders: Array[String] = []
	for path in _scripts("res://ui") + _scripts("res://app"):
		if EXEMPT.has(path) or path == "res://ui/theme/motion.gd":
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var line_number := 0
		while not file.eof_reached():
			var line := file.get_line()
			line_number += 1
			var code := line.split("#")[0]
			if code.strip_edges().is_empty():
				continue
			if code.contains("create_tween(") or code.contains("Tween.TRANS") or code.contains("Tween.EASE"):
				offenders.append("%s:%d собирает твин сам" % [path, line_number])
			var regex := RegEx.new()
			regex.compile("tween_(property|method|interval)\\(.*[^_a-zA-Z0-9](0\\.[0-9]+|[0-9]+\\.[0-9]+)\\s*\\)")
			if regex.search(code) != null:
				offenders.append("%s:%d числовая длительность вместо токена" % [path, line_number])
		file.close()
	for offender in offenders:
		_failures.append(offender)


func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	for entry in DirAccess.get_directories_at(directory):
		found.append_array(_scripts("%s/%s" % [directory, entry]))
	for entry in DirAccess.get_files_at(directory):
		if entry.ends_with(".gd"):
			found.append("%s/%s" % [directory, entry])
	return found


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
