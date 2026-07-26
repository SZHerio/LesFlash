class_name AppShell
extends Control

signal back_requested
signal close_requested
signal pause_requested
signal autosave_requested
signal navigation_requested(tab_id: String)

const BaseTheme: Theme = preload("res://ui/theme/m3_ui_theme.tres")
const SafeAreaLayoutScript := preload("res://app/android/safe_area_layout.gd")
const TokensScript := preload("res://ui/theme/tokens.gd")
const ColourSpace := preload("res://ui/theme/colour_space.gd")
const BACKGROUNDS := {
	"riverside_station_square_day": "res://assets/backgrounds/riverside_station_square_day.png",
	"riverside_underpass_day": "res://assets/backgrounds/riverside_underpass_day.png",
	"riverside_embankment_day": "res://assets/backgrounds/riverside_embankment_day.png",
	"riverside_market_day": "res://assets/backgrounds/riverside_market_day.png",
	"riverside_recycling_point_day": "res://assets/backgrounds/riverside_recycling_point_day.png",
	"riverside_clinic_yard_day": "res://assets/backgrounds/riverside_clinic_yard_day.png",
}
const DEFAULT_BACKGROUND := "riverside_station_square_day"
const BASE_MARGIN := 16.0
const MAX_CONTENT_WIDTH := 680.0

@onready var _backdrop: TextureRect = %Backdrop
@onready var _safe_area: MarginContainer = %SafeArea
@onready var _content_frame: VBoxContainer = %ContentFrame
@onready var _screen_host: Control = %ScreenHost
@onready var _navigation: BottomNavigation = %BottomNavigation
@onready var _toast: ToastOverlay = %ToastOverlay

var _current_screen: Control
var _reduced_motion := false
var _font_scale := 1.0
var _month := 9
var _screen_tween: Tween


func _ready() -> void:
	_navigation.tab_requested.connect(func(tab_id: StringName) -> void:
		navigation_requested.emit(String(tab_id))
	)
	resized.connect(_update_safe_layout)
	call_deferred("_update_safe_layout")
	set_background(DEFAULT_BACKGROUND)
	set_navigation_visible(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			pause_requested.emit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_requested.emit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			close_requested.emit()


func show_screen(scene: PackedScene) -> Control:
	var instance := scene.instantiate() as Control
	if instance == null:
		push_error("AppShell received a scene whose root is not Control.")
		return null
	if _screen_tween != null and _screen_tween.is_valid():
		_screen_tween.kill()
	if _current_screen != null:
		_current_screen.queue_free()
	_current_screen = instance
	_screen_host.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if instance.has_method("set_reduced_motion"):
		instance.call("set_reduced_motion", _reduced_motion)
	if not _reduced_motion:
		instance.modulate.a = 0.0
		instance.position.x = 10.0
		_screen_tween = create_tween().set_parallel(true)
		_screen_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_screen_tween.tween_property(instance, "modulate:a", 1.0, 0.2)
		_screen_tween.tween_property(instance, "position:x", 0.0, 0.22)
	return instance


func current_screen() -> Control:
	return _current_screen


func set_background(background_key: String) -> void:
	var key := background_key if BACKGROUNDS.has(background_key) else DEFAULT_BACKGROUND
	var resource := load(String(BACKGROUNDS[key])) as Texture2D
	if resource != null:
		_backdrop.texture = resource


func set_psyche_intensity(value: float, mode: String = "full") -> void:
	var strength := clampf(value, 0.0, 1.0)
	match mode:
		"off":
			strength = 0.0
		"reduced":
			strength *= 0.45
	var material := _backdrop.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("psyche_intensity", strength)


func set_navigation_visible(visible: bool) -> void:
	_navigation.visible = visible


func present_navigation(model: Dictionary) -> void:
	_navigation.present(model)


func show_toast(message: String, is_error: bool = false) -> void:
	_toast.show_message(message, is_error)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_navigation.set_reduced_motion(enabled)
	_toast.set_reduced_motion(enabled)
	if _current_screen != null and _current_screen.has_method("set_reduced_motion"):
		_current_screen.call("set_reduced_motion", enabled)
	if enabled and _screen_tween != null and _screen_tween.is_valid():
		_screen_tween.kill()
		_current_screen.modulate = Color.WHITE
		_current_screen.position.x = 0.0


func set_font_scale(scale_value: float) -> void:
	_font_scale = clampf(scale_value, 1.0, 2.0)
	_rebuild_theme()


## The month of the game year tints every neutral surface. Only the hue moves;
## each surface keeps its own lightness, so the three-step depth hierarchy and
## the contrast of text survive the calendar.
func set_month(month: int) -> void:
	var next := clampi(month, 1, 12)
	if next == _month:
		return
	_month = next
	_rebuild_theme()


func _rebuild_theme() -> void:
	var scaled_theme := BaseTheme.duplicate(true) as Theme
	scaled_theme.default_font_size = maxi(12, int(round(float(BaseTheme.default_font_size) * _font_scale)))
	for type_name in BaseTheme.get_type_list():
		for font_name in BaseTheme.get_font_size_list(type_name):
			var base_size := BaseTheme.get_font_size(font_name, type_name)
			var type_scale := _font_scale
			if type_name in [&"DisplayTitle", &"LocationTitleLabel"]:
				type_scale = minf(type_scale, 1.4)
			elif type_name in [&"ScreenTitle", &"SectionTitle"]:
				type_scale = minf(type_scale, 1.6)
			elif type_name == &"StatusNameLabel":
				type_scale = minf(type_scale, 1.1)
			elif type_name == &"StatusDeltaLabel":
				type_scale = minf(type_scale, 1.2)
			elif type_name == &"StatusValueLabel":
				type_scale = minf(type_scale, 1.3)
			elif type_name in [&"BottomNavButton", &"BottomNavButtonActive"]:
				type_scale = minf(type_scale, 1.25)
			elif type_name in [&"StepperNameButton", &"StepperValueLabel"]:
				# They share one row with both controls, so they grow less than
				# body text or the row cannot hold them all.
				type_scale = minf(type_scale, 1.2)
			scaled_theme.set_font_size(font_name, type_name, maxi(10, int(round(base_size * type_scale))))
	_tint_surfaces(scaled_theme)
	theme = scaled_theme


## Repaints the neutral dark surfaces to the season. Saturated colours are left
## alone: the gold accent and the danger red carry meaning, and meaning must not
## drift with the calendar.
func _tint_surfaces(target: Theme) -> void:
	var hue := TokensScript.month_hue(_month)
	for type_name in target.get_type_list():
		for style_name in target.get_stylebox_list(type_name):
			var box := target.get_stylebox(style_name, type_name) as StyleBoxFlat
			if box == null or box.bg_color.a <= 0.0:
				continue
			var source := box.bg_color
			if source.v >= 0.35 or source.s >= 0.35:
				continue
			box.bg_color = ColourSpace.recast(
				source,
				TokensScript.SURFACE_CHROMA,
				hue
			)


func _on_autosave_timer_timeout() -> void:
	autosave_requested.emit()


func _update_safe_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var margins := SafeAreaLayoutScript.compute(
		viewport_size,
		DisplayServer.screen_get_size(),
		DisplayServer.get_display_safe_area(),
		OS.has_feature("android"),
		BASE_MARGIN
	)
	var left := float(margins.left)
	var top := float(margins.top)
	var right := float(margins.right)
	var bottom := float(margins.bottom)
	_safe_area.add_theme_constant_override("margin_left", int(round(left)))
	_safe_area.add_theme_constant_override("margin_top", int(round(top)))
	_safe_area.add_theme_constant_override("margin_right", int(round(right)))
	_safe_area.add_theme_constant_override("margin_bottom", int(round(bottom)))
	var available_width := maxf(viewport_size.x - left - right, 280.0)
	_content_frame.custom_minimum_size = Vector2(
		minf(available_width, MAX_CONTENT_WIDTH),
		maxf(viewport_size.y - top - bottom, 320.0)
	)
