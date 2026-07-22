class_name UiScreenPresenter
extends RefCounted

const UiModels := preload("res://app/ui_model_factory.gd")
const MainMenuScene := preload("res://ui/screens/main_menu/main_menu.tscn")
const CharacterCreationScene := preload("res://ui/screens/character_creation/character_creation.tscn")
const SettingsScene := preload("res://ui/screens/settings/settings_screen.tscn")
const LocationScene := preload("res://ui/screens/location/location_screen.tscn")
const ChoiceScene := preload("res://ui/screens/choice/choice_screen.tscn")
const ResultScene := preload("res://ui/screens/result/result_screen.tscn")
const DEFAULT_BACKGROUND := "riverside_station_square_day"
const CREATION_BACKGROUND := "riverside_underpass_day"

var _shell: AppShell


func _init(shell: AppShell) -> void:
	_shell = shell


func show_main_menu(can_continue: bool, handlers: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	_shell.set_background(DEFAULT_BACKGROUND)
	_shell.set_psyche_intensity(0.0, "off")
	var screen := _shell.show_screen(MainMenuScene) as MainMenuScreen
	screen.new_game_requested.connect(_handler(handlers, "new_game"))
	screen.continue_requested.connect(_handler(handlers, "continue"))
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.quit_requested.connect(_handler(handlers, "quit"))
	screen.present({"can_continue": can_continue})


func show_character_creation(handlers: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	_shell.set_background(CREATION_BACKGROUND)
	_shell.set_psyche_intensity(0.0, "off")
	var screen := _shell.show_screen(CharacterCreationScene) as CharacterCreationScreen
	screen.back_requested.connect(_handler(handlers, "back"))
	screen.character_confirmed.connect(_handler(handlers, "confirm"))
	screen.present({
		"values": {"strength": 1, "charisma": 1, "intelligence": 1, "luck": 1},
		"budget": 18,
		"minimum": 1,
		"maximum": 10,
	})


func show_location(
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary,
	last_transaction: Dictionary = {},
	animate_status_delta: bool = true
) -> void:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_shell.set_navigation_visible(true)
	_shell.present_navigation({
		"active_tab": "place",
		"enabled_tabs": {"place": true, "map": false, "hero": false, "items": false, "tasks": false},
	})
	var screen := _shell.show_screen(LocationScene) as LocationScreen
	screen.action_requested.connect(_handler(handlers, "action"))
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.present(UiModels.location(
		shell_model,
		bool(preferences.get("reduced_motion", false)),
		float(preferences.get("font_scale", 1.0)),
		String(preferences.get("psyche_effect_mode", "full")),
		last_transaction,
		animate_status_delta
	))


func show_event(raw_model: Dictionary, shell_model: Dictionary, preferences: Dictionary, handlers: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	_shell.set_background(String(raw_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_choice(UiModels.event(raw_model), handlers)


func show_job(raw_model: Dictionary, shell_model: Dictionary, preferences: Dictionary, handlers: Dictionary) -> void:
	_prepare_location_activity(shell_model, preferences)
	_show_choice(UiModels.job(raw_model), handlers)


func show_shelters(raw_shelters: Array, shell_model: Dictionary, preferences: Dictionary, handlers: Dictionary) -> void:
	_prepare_location_activity(shell_model, preferences)
	_show_choice(UiModels.shelters(raw_shelters), handlers)


func show_job_result(raw_model: Dictionary, shell_model: Dictionary, preferences: Dictionary, on_confirm: Callable) -> void:
	_prepare_location_activity(shell_model, preferences)
	show_result(UiModels.job_result(raw_model), on_confirm)


func show_summary(raw_model: Dictionary, shell_model: Dictionary, preferences: Dictionary, on_confirm: Callable) -> void:
	_prepare_location_activity(shell_model, preferences)
	show_result(UiModels.summary(raw_model), on_confirm)


func show_settings(model: Dictionary, handlers: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	var screen := _shell.show_screen(SettingsScene) as SettingsScreen
	screen.back_requested.connect(_handler(handlers, "back"))
	screen.preference_changed.connect(_handler(handlers, "change"))
	screen.present(model)


func apply_session_ambience(shell_model: Dictionary, preferences: Dictionary) -> void:
	_shell.set_psyche_intensity(
		UiModels.psyche_intensity(shell_model),
		String(preferences.get("psyche_effect_mode", "full"))
	)


func _show_choice(model: Dictionary, handlers: Dictionary) -> void:
	var screen := _shell.show_screen(ChoiceScene) as ChoiceScreen
	screen.action_requested.connect(_handler(handlers, "action"))
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.present(model)


func show_result(model: Dictionary, on_confirm: Callable) -> void:
	var screen := _shell.show_screen(ResultScene) as ResultScreen
	screen.confirmed.connect(on_confirm)
	screen.present(model)


func _prepare_location_activity(shell_model: Dictionary, preferences: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)


func _handler(handlers: Dictionary, key: String) -> Callable:
	var value: Variant = handlers.get(key, Callable())
	assert(value is Callable and value.is_valid(), "Missing UI handler: %s" % key)
	return value
