class_name UiScreenPresenter
extends RefCounted

const UiModels := preload("res://app/ui_model_factory.gd")
const CityMapModels := preload("res://app/map/city_map_view_model.gd")
const MainMenuScene := preload("res://ui/screens/main_menu/main_menu.tscn")
const CharacterCreationScene := preload("res://ui/screens/character_creation/character_creation.tscn")
const SettingsScene := preload("res://ui/screens/settings/settings_screen.tscn")
const LocationScene := preload("res://ui/screens/location/location_screen.tscn")
const CityMapScene := preload("res://ui/screens/city_map/city_map_screen.tscn")
const InventoryScene := preload("res://ui/screens/inventory/inventory_screen.tscn")
const ShopScene := preload("res://ui/screens/shop/shop_screen.tscn")
const NpcScene := preload("res://ui/screens/npc/npc_screen.tscn")
const HeroScene := preload("res://ui/screens/hero/hero_screen.tscn")
const RoutineScene := preload("res://ui/screens/routine/routine_screen.tscn")
const JobShiftScene := preload("res://ui/screens/job/job_screen.tscn")
const HeroModels := preload("res://app/hero/hero_view_model.gd")
const InventoryModels := preload("res://app/inventory/inventory_view_model.gd")
const SearchScene := preload("res://ui/screens/search/search_screen.tscn")
const SearchModels := preload("res://app/search/search_view_model.gd")
const EncounterModels := preload("res://app/events/encounter_view_model.gd")
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
	_show_session_navigation("place")
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


func show_city_map(
	raw_model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> CityMapScreen:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_session_navigation("map")
	var screen := _shell.show_screen(CityMapScene) as CityMapScreen
	screen.travel_requested.connect(_handler(handlers, "travel"))
	screen.back_requested.connect(_handler(handlers, "back"))
	screen.present(CityMapModels.build(
		raw_model,
		bool(preferences.get("reduced_motion", false))
	))
	return screen


func show_hero(
	raw_model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> HeroScreen:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_session_navigation("hero")
	var screen := _shell.show_screen(HeroScene) as HeroScreen
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.present(HeroModels.build(
		raw_model,
		shell_model,
		bool(preferences.get("reduced_motion", false)),
		float(preferences.get("font_scale", 1.0))
	))
	return screen


func show_routine(
	model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> RoutineScreen:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_session_navigation("routine")
	var screen := _shell.show_screen(RoutineScene) as RoutineScreen
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.block_selected.connect(_handler(handlers, "block_selected"))
	screen.following_toggled.connect(_handler(handlers, "following_toggled"))
	screen.clear_requested.connect(_handler(handlers, "clear"))
	var full := model.duplicate(true)
	full["shell"] = shell_model
	screen.present(full, bool(preferences.get("reduced_motion", false)))
	return screen


func show_inventory(
	raw_model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> InventoryScreen:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_shell.set_background(String(location_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_session_navigation("items")
	var screen := _shell.show_screen(InventoryScene) as InventoryScreen
	screen.action_requested.connect(_handler(handlers, "action"))
	screen.settings_requested.connect(_handler(handlers, "settings"))
	screen.present(InventoryModels.build(
		raw_model,
		shell_model,
		bool(preferences.get("reduced_motion", false)),
		float(preferences.get("font_scale", 1.0))
	))
	return screen


func show_shop(
	model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> ShopScreen:
	_prepare_location_activity(shell_model, preferences)
	var screen := _shell.show_screen(ShopScene) as ShopScreen
	screen.back_requested.connect(_handler(handlers, "back"))
	screen.purchase_requested.connect(_handler(handlers, "purchase"))
	screen.sale_requested.connect(_handler(handlers, "sale"))
	screen.present(model)
	return screen


## A shift is an interruptible activity like the search, not a navigation tab,
## so the bottom navigation steps aside until the hero leaves the yard.
func show_job_shift(
	model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> JobScreen:
	_prepare_location_activity(shell_model, preferences)
	var screen := _shell.show_screen(JobShiftScene) as JobScreen
	screen.choice_requested.connect(
		func(choice_id: String, _revision: int) -> void:
			_handler(handlers, "choice").call(choice_id)
	)
	screen.quick_resolve_requested.connect(
		func(_revision: int) -> void:
			_handler(handlers, "quick_resolve").call()
	)
	screen.present(model)
	return screen


func show_npc(
	model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> NpcScreen:
	_prepare_location_activity(shell_model, preferences)
	var screen := _shell.show_screen(NpcScene) as NpcScreen
	screen.back_requested.connect(_handler(handlers, "back"))
	screen.interaction_requested.connect(_handler(handlers, "interaction"))
	screen.topic_requested.connect(_handler(handlers, "topic"))
	screen.present(model)
	return screen


## The search is an interruptible activity, not a navigation tab, so the bottom
## navigation steps aside until the player leaves the zone.
func show_search(
	raw_model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> SearchScreen:
	_prepare_location_activity(shell_model, preferences)
	var screen := _shell.show_screen(SearchScene) as SearchScreen
	screen.move_requested.connect(_handler(handlers, "move"))
	screen.movement_checkpoint.connect(_handler(handlers, "checkpoint"))
	screen.interaction_requested.connect(_handler(handlers, "interact"))
	screen.pickup_requested.connect(_handler(handlers, "pick_up"))
	screen.replacement_requested.connect(_handler(handlers, "replace"))
	screen.capacity_recovery_requested.connect(_handler(handlers, "recover"))
	screen.quick_search_requested.connect(_handler(handlers, "quick_search"))
	screen.finish_requested.connect(_handler(handlers, "finish"))
	screen.present(build_search_model(raw_model, shell_model, preferences))
	return screen


func build_search_model(
	raw_model: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary
) -> Dictionary:
	return SearchModels.build(
		raw_model,
		shell_model,
		bool(preferences.get("reduced_motion", false)),
		float(preferences.get("font_scale", 1.0)),
		String(preferences.get("psyche_effect_mode", "full"))
	)


func show_encounter(
	preview: Dictionary,
	shell_model: Dictionary,
	preferences: Dictionary,
	handlers: Dictionary
) -> void:
	_prepare_location_activity(shell_model, preferences)
	var location_model: Dictionary = Dictionary(shell_model.get("location", {}))
	_show_choice(
		EncounterModels.build(
			preview,
			String(location_model.get("title", "Город")),
			bool(preferences.get("show_locked_options", false))
		),
		handlers
	)


func show_event(raw_model: Dictionary, shell_model: Dictionary, preferences: Dictionary, handlers: Dictionary) -> void:
	_shell.set_navigation_visible(false)
	_shell.set_background(String(raw_model.get("background_key", DEFAULT_BACKGROUND)))
	apply_session_ambience(shell_model, preferences)
	_show_choice(UiModels.event(raw_model), handlers)


func show_shelters(raw_shelters: Array, shell_model: Dictionary, preferences: Dictionary, handlers: Dictionary) -> void:
	_prepare_location_activity(shell_model, preferences)
	_show_choice(UiModels.shelters(raw_shelters), handlers)


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
	var calendar: Dictionary = Dictionary(
		Dictionary(shell_model.get("status", {})).get("calendar", {})
	)
	_shell.set_month(int(calendar.get("month", 9)))
	_shell.set_psyche_intensity(
		UiModels.psyche_intensity(shell_model),
		String(preferences.get("psyche_effect_mode", "full"))
	)


func _show_choice(model: Dictionary, handlers: Dictionary) -> void:
	var screen := _shell.show_screen(ChoiceScene) as ChoiceScreen
	screen.action_requested.connect(_handler(handlers, "action"))
	screen.settings_requested.connect(_handler(handlers, "settings"))
	var leave: Variant = handlers.get("leave", null)
	if leave is Callable and leave.is_valid():
		screen.leave_requested.connect(leave)
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


func _show_session_navigation(active_tab: String) -> void:
	_shell.set_navigation_visible(true)
	_shell.present_navigation({
		"active_tab": active_tab,
		"enabled_tabs": {
			"place": true,
			"map": true,
			"hero": true,
			"routine": true,
			"items": true,
			"tasks": false,
		},
	})
