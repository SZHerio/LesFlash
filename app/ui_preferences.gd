class_name UiPreferences
extends RefCounted

const SETTINGS_PATH := "user://ui_settings.cfg"
const PSYCHE_MODES := ["off", "reduced", "full"]
const FONT_SCALES := [1.0, 1.25, 1.5, 2.0]

var show_locked_options := false
var psyche_effect_mode := "full"
var font_scale := 1.0
var reduced_motion := false


func load_from_disk(path: String = SETTINGS_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return {"ok": true, "created": true}
	if error != OK:
		return {"ok": false, "code": "preferences_load_failed", "engine_error": error}
	show_locked_options = bool(config.get_value("accessibility", "show_locked_options", false))
	psyche_effect_mode = _valid_psyche_mode(String(config.get_value("visual", "psyche_effect_mode", "full")))
	font_scale = _valid_font_scale(float(config.get_value("accessibility", "font_scale", 1.0)))
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	return {"ok": true, "created": false}


func save_to_disk(path: String = SETTINGS_PATH) -> Dictionary:
	var config := ConfigFile.new()
	config.set_value("accessibility", "show_locked_options", show_locked_options)
	config.set_value("accessibility", "font_scale", font_scale)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	config.set_value("visual", "psyche_effect_mode", psyche_effect_mode)
	var error := config.save(path)
	return (
		{"ok": true}
		if error == OK
		else {"ok": false, "code": "preferences_save_failed", "engine_error": error}
	)


func apply(key: String, value: Variant) -> bool:
	match key:
		"show_locked_options":
			show_locked_options = bool(value)
		"psyche_effect_mode":
			psyche_effect_mode = _valid_psyche_mode(String(value))
		"font_scale":
			font_scale = _valid_font_scale(float(value))
		"reduced_motion":
			reduced_motion = bool(value)
		_:
			return false
	return true


func to_model() -> Dictionary:
	return {
		"show_locked_options": show_locked_options,
		"psyche_effect_mode": psyche_effect_mode,
		"font_scale": font_scale,
		"reduced_motion": reduced_motion,
	}


func _valid_psyche_mode(value: String) -> String:
	return value if value in PSYCHE_MODES else "full"


func _valid_font_scale(value: float) -> float:
	var closest := 1.0
	var distance := INF
	for candidate in FONT_SCALES:
		var candidate_distance := absf(float(candidate) - value)
		if candidate_distance < distance:
			distance = candidate_distance
			closest = float(candidate)
	return closest
