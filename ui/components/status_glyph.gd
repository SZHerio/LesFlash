class_name StatusGlyph
extends BaseButton

signal detail_requested(status_id: String)

const Palette = preload("res://ui/theme/palette.gd")
const Motion := preload("res://ui/theme/motion.gd")

@onready var _value_label: Label = %ValueLabel
@onready var _title_label: Label = %TitleLabel
@onready var _delta_label: Label = %DeltaLabel

var _status_id: StringName = &"health"
var _maximum := 100.0
var _target_value := 0.0
var _display_value := 0.0:
	set(value):
		_display_value = value
		if is_instance_valid(_value_label):
			_value_label.text = str(int(round(value)))
		queue_redraw()
var _accent := Palette.status_accent(&"health")
var _reduced_motion := false
var _pulse_phase := 0.0
var _value_tween: Tween
var _scale_tween: Tween
var _has_presented := false


func _ready() -> void:
	pressed.connect(_on_pressed)
	button_down.connect(_animate_scale.bind(0.95))
	button_up.connect(_animate_scale.bind(1.0))
	mouse_entered.connect(_animate_scale.bind(1.025))
	mouse_exited.connect(_animate_scale.bind(1.0))
	resized.connect(_on_resized)
	set_process(true)
	_on_resized()
	queue_redraw()


func present(model: Dictionary) -> void:
	_status_id = StringName(model.get("id", &"health"))
	_title_label.text = String(model.get("title", _default_title(_status_id)))
	_maximum = maxf(float(model.get("maximum", 100.0)), 1.0)
	_target_value = clampf(float(model.get("value", 0.0)), 0.0, _maximum)
	var raw_accent: Variant = model.get("accent", Palette.status_accent(_status_id))
	_accent = raw_accent if raw_accent is Color else Palette.status_accent(_status_id)

	var delta := int(model.get("delta", 0))
	var animate_delta := bool(model.get("animate_delta", true))
	_delta_label.visible = delta != 0
	_delta_label.text = ("+%d" % delta) if delta > 0 else str(delta)
	_delta_label.add_theme_color_override("font_color", _accent)
	if not _has_presented:
		_display_value = (
			clampf(_target_value - float(delta), 0.0, _maximum)
			if animate_delta and delta != 0
			else _target_value
		)
		_has_presented = true

	var detail := String(model.get("detail", ""))
	tooltip_text = "%s: %d из %d%s" % [
		_title_label.text,
		int(round(_target_value)),
		int(round(_maximum)),
		("\n" + detail) if not detail.is_empty() else "",
	]

	# A meter that moves by one point and one that halves must not take the same
	# time, so the duration follows the size of the delta.
	_value_tween = Motion.play(_value_tween, self, [{
		"target": self,
		"property": "_display_value",
		"to": _target_value,
		"duration": Motion.meter_duration(delta, _maximum),
	}], _reduced_motion or delta == 0 or not animate_delta)
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	set_process(not enabled)
	if enabled:
		_pulse_phase = 0.0
		if _value_tween != null and _value_tween.is_valid():
			_value_tween.kill()
		if _scale_tween != null and _scale_tween.is_valid():
			_scale_tween.kill()
		scale = Vector2.ONE
		_display_value = _target_value
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta, TAU)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, 31.0)
	var radius := minf(23.0, maxf(18.0, size.x * 0.32))
	var pulse := 0.0 if _reduced_motion else (sin(_pulse_phase * 1.25) + 1.0) * 0.5
	var ratio := clampf(_display_value / _maximum, 0.0, 1.0)

	draw_circle(center, radius + 4.0, Color(Palette.INK, 0.78))
	draw_circle(center, radius + 1.0, Color(_accent, 0.07 + pulse * 0.035))
	draw_arc(center, radius + 1.0, -PI * 0.5, PI * 1.5, 52, Color(Palette.BORDER, 0.32), 3.0, true)
	if ratio > 0.001:
		draw_arc(center, radius + 1.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 52, _accent, 4.0, true)
	_draw_status_icon(center, radius * 0.57, Color(_accent, 0.96))

	if has_focus():
		draw_arc(center, radius + 6.0, 0.0, TAU, 52, Palette.GOLD, 2.0, true)


func _draw_status_icon(center: Vector2, radius: float, colour: Color) -> void:
	var width := 2.6
	match _status_id:
		&"health":
			draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), colour, width, true)
			draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), colour, width, true)
		&"hunger":
			draw_arc(center + Vector2(0.0, -1.0), radius, 0.05, PI - 0.05, 20, colour, width, true)
			draw_line(center + Vector2(-radius, -1.0), center + Vector2(radius, -1.0), colour, width, true)
			draw_line(center + Vector2(-radius * 0.6, radius * 0.72), center + Vector2(radius * 0.6, radius * 0.72), colour, width, true)
		&"energy":
			var bolt := PackedVector2Array([
				center + Vector2(radius * 0.15, -radius),
				center + Vector2(-radius * 0.55, radius * 0.08),
				center + Vector2(-radius * 0.04, radius * 0.08),
				center + Vector2(-radius * 0.22, radius),
				center + Vector2(radius * 0.62, -radius * 0.2),
				center + Vector2(radius * 0.1, -radius * 0.2),
			])
			draw_colored_polygon(bolt, colour)
		&"tension":
			var wave := PackedVector2Array([
				center + Vector2(-radius, radius * 0.35),
				center + Vector2(-radius * 0.45, -radius * 0.4),
				center + Vector2(-radius * 0.05, radius * 0.42),
				center + Vector2(radius * 0.4, -radius * 0.48),
				center + Vector2(radius, radius * 0.15),
			])
			draw_polyline(wave, colour, width, true)
		&"morale":
			draw_circle(center, radius * 0.67, Color(colour, 0.2))
			draw_arc(center, radius * 0.72, 0.25, PI - 0.25, 18, colour, width, true)
			draw_circle(center + Vector2(-radius * 0.28, -radius * 0.18), 1.8, colour)
			draw_circle(center + Vector2(radius * 0.28, -radius * 0.18), 1.8, colour)
		_:
			draw_circle(center, radius * 0.58, Color(colour, 0.72))


func _default_title(status_id: StringName) -> String:
	match status_id:
		&"health":
			return "Здоровье"
		&"hunger":
			return "Голод"
		&"energy":
			return "Энергия"
		&"tension":
			return "Напряжение"
		&"morale":
			return "Мораль"
		_:
			return "Состояние"


func _on_pressed() -> void:
	detail_requested.emit(String(_status_id))


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _animate_scale(target: float) -> void:
	_scale_tween = Motion.press(_scale_tween, self, self, target, _reduced_motion or disabled)
