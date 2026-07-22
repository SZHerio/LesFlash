extends Control

const FirstDaySessionScript = preload("res://game/first_day/first_day_session.gd")
const FirstDaySaveScript = preload("res://game/first_day/first_day_save.gd")
const FirstDayContentScript = preload("res://game/first_day/first_day_content.gd")
const DistrictMapView = preload("res://ui/components/district_map.gd")

const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_BACKGROUND := "riverside_station_square_day"
const MAX_CONTENT_WIDTH := 680.0
const MIN_TOUCH_HEIGHT := 60.0

const COLOUR_INK := Color("#18201e")
const COLOUR_TEXT := Color("#f4efe4")
const COLOUR_MUTED := Color("#b9c0b9")
const COLOUR_PANEL := Color("#202b28e8")
const COLOUR_PANEL_LIGHT := Color("#293633f2")
const COLOUR_BORDER := Color("#66766f")
const COLOUR_GREEN := Color("#72977e")
const COLOUR_GREEN_HOVER := Color("#86ad91")
const COLOUR_RUST := Color("#b96f49")
const COLOUR_RUST_HOVER := Color("#d1845b")
const COLOUR_GOLD := Color("#d6a95f")
const COLOUR_DANGER := Color("#b85e58")

const STAT_TITLES := {
	"strength": "Сила",
	"charisma": "Харизма",
	"intelligence": "Интеллект",
	"luck": "Удача",
}
const STAT_DESCRIPTIONS := {
	"strength": "Тяжёлая работа, выносливость тела и прямые физические решения.",
	"charisma": "Разговоры, доверие, торг и возможность договориться без конфликта.",
	"intelligence": "Анализ, обучение, осторожные решения и понимание сложных правил.",
	"luck": "Стартовая ситуация и частота неблагоприятных случайностей.",
}
const METER_TITLES := {
	"health": "ЗДР",
	"hunger": "ГОЛ",
	"energy": "ЭН",
	"tension": "НАП",
	"morale": "ДУХ",
}
const METER_LONG_TITLES := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"morale": "Настроение",
}
const SKILL_TITLES := {
	"city_navigation": "Ориентирование в городе",
	"cargo_handling": "Работа с грузом",
	"cooking": "Готовка",
	"repair": "Ремонт",
	"first_aid": "Первая помощь",
	"trade": "Торговля",
}
const POLARITY_TITLES := {
	"physical_specialization": "Физическая специализация",
	"execution_style": "Способ выполнения",
	"influence_style": "Способ влияния",
	"relationship_investment": "Вложение в отношения",
	"attention_distribution": "Распределение внимания",
	"knowledge_profile": "Профиль знаний",
	"uncertainty_behavior": "Поведение в неизвестности",
	"decision_priority": "Приоритет решения",
}
const ITEM_TITLES := {
	"cardboard_sheet": "Лист сухого картона",
}
const KNOWLEDGE_TITLES := {
	"clinic_back_gate": "Расписание служебной калитки",
}

@onready var _backdrop: TextureRect = $BackgroundLayer/BackdropRoot/Backdrop
@onready var _safe_area: MarginContainer = $UILayer/SafeArea
@onready var _content_root: VBoxContainer = $UILayer/SafeArea/Center/ContentRoot
@onready var _screen_host: VBoxContainer = $UILayer/SafeArea/Center/ContentRoot/ScreenHost
@onready var _overlay_layer: Control = $UILayer/OverlayLayer

var _session: FirstDaySession = null
var _preferences := {
	"show_locked_options": false,
	"psyche_effect_mode": "full",
	"font_scale": 1.0,
}
var _creation_stats := {
	"strength": 1,
	"charisma": 1,
	"intelligence": 1,
	"luck": 1,
}
var _screen_kind := "menu"
var _settings_return := "menu"
var _selected_destination := ""
var _last_background := ""
var _last_job_result: Dictionary = {}
var _ui_theme: Theme
var _save_in_progress := false


func _ready() -> void:
	_load_preferences()
	_apply_theme()
	resized.connect(_update_layout)
	call_deferred("_update_layout")
	_set_background(DEFAULT_BACKGROUND)
	_show_main_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_session(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _handle_back_request() -> void:
	match _screen_kind:
		"menu":
			get_tree().quit()
		"creation":
			_show_main_menu()
		"settings":
			_return_from_settings()
		"shelter", "job_result":
			_show_map_screen()
		"summary":
			_show_main_menu()
		_:
			_save_session(false)
			if _session != null and _session.phase == "map":
				_show_map_screen()


func _on_autosave_timeout() -> void:
	if _session == null:
		return
	var result := _save_session(false)
	if not bool(result.get("ok", false)):
		_toast("Автосохранение не выполнено: %s" % _result_message(result), true)


func _show_main_menu() -> void:
	_screen_kind = "menu"
	_session = null
	_selected_destination = ""
	_update_psyche_effect()
	_set_background(DEFAULT_BACKGROUND)
	var screen := _new_screen()

	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(top_space)

	var eyebrow := _make_label("ТЕКСТОВЫЙ SURVIVAL · ANDROID", 13, COLOUR_GOLD, false)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_menu_text_outline(eyebrow, 4)
	screen.add_child(eyebrow)
	var title := _make_label("БОМЖАРА", 40, COLOUR_TEXT, false)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_menu_text_outline(title, 7)
	screen.add_child(title)
	var subtitle := _make_label("Один человек. Один город.\nИстория, которую определяют ваши решения.", 17, COLOUR_MUTED, true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_menu_text_outline(subtitle, 5)
	screen.add_child(subtitle)
	screen.add_child(_vertical_gap(18.0))

	var menu := _card(screen, "light")
	menu.add_child(_make_button("Новая жизнь", _start_character_creation, "accent"))
	var continue_button := _make_button("Продолжить", _continue_game, "normal")
	continue_button.disabled = not _save_candidate_exists()
	menu.add_child(continue_button)
	menu.add_child(_make_button("Настройки", _open_settings_from_menu, "quiet"))
	menu.add_child(_make_button("Выйти", get_tree().quit, "quiet"))

	var bottom_space := Control.new()
	bottom_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(bottom_space)
	_animate_screen(screen)


func _start_character_creation() -> void:
	_creation_stats = {
		"strength": 1,
		"charisma": 1,
		"intelligence": 1,
		"luck": 1,
	}
	_show_character_creation()


func _show_character_creation() -> void:
	_screen_kind = "creation"
	_set_background("riverside_underpass_day")
	var screen := _new_screen()
	var header := _simple_header("Кем вы станете?", "Назад", _show_main_menu)
	screen.add_child(header)

	var scroll := _scroll_body(screen)
	var body: VBoxContainer = scroll.get_meta("body")
	var intro_card := _card(body, "normal")
	intro_card.add_child(_make_label(
		"Все характеристики начинаются с 1. Распределите ещё 14 очков. Сильных во всём людей не бывает — выбранные пределы откроют одну историю и закроют другие.",
		16,
		COLOUR_MUTED,
		true
	))

	var remaining := _remaining_creation_points()
	var points_card := _card(body, "accent")
	var points_label := _make_label("Осталось очков: %d" % remaining, 22, COLOUR_TEXT, false)
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_card.add_child(points_label)

	for stat_id in ["strength", "charisma", "intelligence", "luck"]:
		var stat_card := _card(body, "normal")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		stat_card.add_child(row)
		var name_box := VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_box)
		name_box.add_child(_make_label(STAT_TITLES[stat_id], 20, COLOUR_TEXT, false))
		name_box.add_child(_make_label(STAT_DESCRIPTIONS[stat_id], 13, COLOUR_MUTED, true))

		var minus := _make_button("−", _change_creation_stat.bind(stat_id, -1), "quiet")
		minus.custom_minimum_size = Vector2(56.0, 56.0)
		minus.disabled = int(_creation_stats[stat_id]) <= 1
		row.add_child(minus)
		var value := _make_label(str(_creation_stats[stat_id]), 27, COLOUR_GOLD, false)
		value.custom_minimum_size = Vector2(36.0, 56.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := _make_button("+", _change_creation_stat.bind(stat_id, 1), "accent")
		plus.custom_minimum_size = Vector2(56.0, 56.0)
		plus.disabled = int(_creation_stats[stat_id]) >= 10 or remaining <= 0
		row.add_child(plus)

	body.add_child(_vertical_gap(6.0))
	var begin := _make_button("Начать историю", _create_new_session, "accent")
	begin.disabled = remaining != 0
	body.add_child(begin)
	body.add_child(_make_label("Сумма характеристик должна быть ровно 18.", 13, COLOUR_MUTED, false))
	_animate_screen(screen)


func _change_creation_stat(stat_id: String, delta: int) -> void:
	if not _creation_stats.has(stat_id):
		return
	var next_value := int(_creation_stats[stat_id]) + delta
	if next_value < 1 or next_value > 10:
		return
	if delta > 0 and _remaining_creation_points() <= 0:
		return
	_creation_stats[stat_id] = next_value
	_show_character_creation()


func _remaining_creation_points() -> int:
	var spent := 0
	for value in _creation_stats.values():
		spent += int(value)
	return 18 - spent


func _create_new_session() -> void:
	if _remaining_creation_points() != 0:
		_toast("Сначала распределите все 14 очков.", true)
		return
	var candidate := FirstDaySessionScript.new()
	var seed := int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())
	var result: Dictionary = candidate.start_new_run(_creation_stats.duplicate(true), seed)
	if not bool(result.get("ok", false)):
		_toast(_result_message(result), true)
		return
	var cleanup_result := _clear_save_candidates_for_new_run()
	if not bool(cleanup_result.get("ok", false)):
		_toast("Новая жизнь не начата: %s" % _result_message(cleanup_result), true)
		return
	_session = candidate
	_apply_preferences_to_session()
	var save_result := _save_session(true)
	if not bool(save_result.get("ok", false)):
		_session = null
		return
	_show_session_phase()


func _continue_game() -> void:
	var result: Dictionary = FirstDaySaveScript.load_session()
	if not bool(result.get("ok", false)):
		_toast("Сохранение не загружено: %s" % _result_message(result), true)
		return
	_session = result.get("session")
	if _session == null:
		_toast("Сохранение не содержит игровой сессии.", true)
		return
	_apply_preferences_to_session()
	_apply_theme()
	_update_layout()
	var preference_save := _save_session(false)
	_show_session_phase()
	if not bool(preference_save.get("ok", false)):
		_toast("Настройки применены, но сохранение не обновлено: %s" % _result_message(preference_save), true)
	elif bool(result.get("recovered_from_temporary", false)) or bool(result.get("recovered_from_backup", false)):
		_toast("Сессия восстановлена после прерванного сохранения.", false)


func _open_settings_from_menu() -> void:
	_settings_return = "menu"
	_show_settings_screen()


func _open_settings_from_game() -> void:
	_settings_return = _screen_kind
	_show_settings_screen()


func _show_settings_screen() -> void:
	_screen_kind = "settings"
	var screen := _new_screen()
	screen.add_child(_simple_header("Настройки", "Назад", _return_from_settings))
	var scroll := _scroll_body(screen)
	var body: VBoxContainer = scroll.get_meta("body")

	var locked_card := _card(body, "normal")
	locked_card.add_child(_make_label("Закрытые ответы", 19, COLOUR_TEXT, false))
	locked_card.add_child(_make_label("Показывать недоступные варианты вместе с причиной блокировки.", 14, COLOUR_MUTED, true))
	var locked_toggle := CheckButton.new()
	locked_toggle.text = "Показывать закрытые варианты"
	locked_toggle.button_pressed = bool(_preferences["show_locked_options"])
	_style_base_button(locked_toggle, "quiet")
	locked_toggle.toggled.connect(_on_locked_options_changed)
	locked_card.add_child(locked_toggle)

	var psyche_card := _card(body, "normal")
	psyche_card.add_child(_make_label("Влияние психики на фон", 19, COLOUR_TEXT, false))
	psyche_card.add_child(_make_label("Интерфейс всегда остаётся чётким. Меняются только насыщенность, свет и виньетка изображения локации.", 14, COLOUR_MUTED, true))
	var psyche_option := OptionButton.new()
	psyche_option.add_item("Полный эффект")
	psyche_option.set_item_metadata(0, "full")
	psyche_option.add_item("Ослабленный эффект")
	psyche_option.set_item_metadata(1, "reduced")
	psyche_option.add_item("Выключено")
	psyche_option.set_item_metadata(2, "off")
	for index in range(psyche_option.item_count):
		if String(psyche_option.get_item_metadata(index)) == String(_preferences["psyche_effect_mode"]):
			psyche_option.select(index)
	_style_base_button(psyche_option, "normal")
	psyche_option.item_selected.connect(_on_psyche_mode_selected.bind(psyche_option))
	psyche_card.add_child(psyche_option)

	var text_card := _card(body, "normal")
	text_card.add_child(_make_label("Размер текста", 19, COLOUR_TEXT, false))
	text_card.add_child(_make_label("Все экраны прокручиваются и сохраняют крупные зоны нажатия.", 14, COLOUR_MUTED, true))
	var font_option := OptionButton.new()
	var font_choices := [
		["Компактный · 90%", 0.9],
		["Обычный · 100%", 1.0],
		["Крупный · 120%", 1.2],
		["Очень крупный · 140%", 1.4],
	]
	for choice in font_choices:
		font_option.add_item(String(choice[0]))
		font_option.set_item_metadata(font_option.item_count - 1, float(choice[1]))
	for index in range(font_option.item_count):
		if is_equal_approx(float(font_option.get_item_metadata(index)), float(_preferences["font_scale"])):
			font_option.select(index)
	_style_base_button(font_option, "normal")
	font_option.item_selected.connect(_on_font_scale_selected.bind(font_option))
	text_card.add_child(font_option)
	_animate_screen(screen)


func _on_locked_options_changed(enabled: bool) -> void:
	_apply_preference("show_locked_options", enabled)


func _on_psyche_mode_selected(index: int, option: OptionButton) -> void:
	_apply_preference("psyche_effect_mode", String(option.get_item_metadata(index)))


func _on_font_scale_selected(index: int, option: OptionButton) -> void:
	_apply_preference("font_scale", float(option.get_item_metadata(index)))
	_apply_theme()
	_update_layout()
	call_deferred("_show_settings_screen")


func _apply_preference(key: String, value: Variant) -> void:
	_preferences[key] = value
	if _session != null and not _session.set_setting(key, value):
		_toast("Настройка не принята игровой сессией.", true)
		return
	_save_preferences()
	_update_psyche_effect()
	_save_session(false)


func _return_from_settings() -> void:
	if _session == null or _settings_return == "menu":
		_show_main_menu()
		return
	var return_screen := _settings_return
	_settings_return = "menu"
	match return_screen:
		"shelter":
			_show_shelter_screen()
		"job_result":
			_show_job_result_screen()
		_:
			_show_session_phase()


func _show_session_phase() -> void:
	if _session == null:
		_show_main_menu()
		return
	match _session.phase:
		"start", "event":
			_show_event_screen()
		"map":
			_show_map_screen()
		"job":
			_show_job_screen()
		"completed":
			_show_day_summary()
		_:
			_toast("Неизвестное состояние сессии: %s" % _session.phase, true)
			_show_main_menu()


func _show_map_screen() -> void:
	if _session == null:
		_show_main_menu()
		return
	_screen_kind = "map"
	var model: Dictionary = _session.get_map_model()
	_set_background(_background_from_map(model))
	var shell := _new_game_shell("Карта района", true)
	var body: VBoxContainer = shell["body"]

	var location_title := _location_title(model, String(model.get("current_location_id", "")))
	var location_card := _card(body, "normal")
	location_card.add_child(_make_label(location_title, 25, COLOUR_TEXT, true))
	location_card.add_child(_make_label("Коснитесь точки на карте или выберите маршрут ниже.", 14, COLOUR_MUTED, true))

	var map_card := _card(body, "map")
	var map_view := DistrictMapView.new()
	map_view.set_map_model(model)
	map_view.set_selected_location(_selected_destination)
	map_view.location_selected.connect(_on_map_location_selected)
	map_card.add_child(map_view)

	_build_route_section(body, model)
	_build_location_actions(body, model)
	_animate_screen(shell["screen"])


func _build_route_section(body: VBoxContainer, model: Dictionary) -> void:
	body.add_child(_section_heading("Маршруты"))
	var routes: Array = model.get("routes", [])
	var visible_routes: Array = []
	for raw_route in routes:
		if not raw_route is Dictionary:
			continue
		if _selected_destination.is_empty() or String(raw_route.get("destination_id", "")) == _selected_destination:
			visible_routes.append(raw_route)
	if not _selected_destination.is_empty() and visible_routes.is_empty():
		var unavailable := _card(body, "normal")
		unavailable.add_child(_make_label("Прямого маршрута сюда сейчас нет.", 15, COLOUR_MUTED, true))
		unavailable.add_child(_make_button("Показать все маршруты", _clear_map_selection, "quiet"))
		return
	for raw_route in visible_routes:
		var route: Dictionary = raw_route
		var available := bool(route.get("available", false))
		var route_card := _card(body, "normal")
		var caption := "%s · %s" % [
			String(route.get("destination_title", "Другая локация")),
			String(route.get("mode_title", "Пешком")),
		]
		route_card.add_child(_make_label(caption, 18, COLOUR_TEXT if available else COLOUR_MUTED, true))
		route_card.add_child(_make_label("В пути: %d мин." % int(route.get("minutes", 0)), 14, COLOUR_GOLD, false))
		if String(route.get("mode", "walk")) == "bus":
			var fare := _route_fare(String(route.get("destination_id", "")))
			var fare_text := "Цена проезда: %d" % fare if fare >= 0 else "Цена проезда не указана"
			route_card.add_child(_make_label(fare_text, 14, COLOUR_GOLD, false))
		var button := _make_button(
			"Отправиться",
			_on_travel.bind(String(route.get("destination_id", "")), String(route.get("mode", "walk"))),
			"accent"
		)
		button.disabled = not available
		route_card.add_child(button)
		if not available:
			route_card.add_child(_make_label(_reason_text(route.get("reasons", [])), 13, COLOUR_DANGER, true))
	if not _selected_destination.is_empty():
		body.add_child(_make_button("Показать все направления", _clear_map_selection, "quiet"))


func _build_location_actions(body: VBoxContainer, model: Dictionary) -> void:
	body.add_child(_section_heading("Что сделать здесь"))
	var events: Array = model.get("events", [])
	var random_event_button := _make_button("Осмотреться", _on_select_event, "accent")
	random_event_button.disabled = not _has_selectable_event(events)
	body.add_child(random_event_button)
	for raw_event in events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var completed := bool(event.get("completed", false))
		var available := bool(event.get("available", false)) and not completed
		var suffix := " · завершено" if completed else (" · уже замечено" if bool(event.get("seen", false)) else "")
		var button := _make_button(
			String(event.get("title", "Событие")) + suffix,
			_on_enter_event.bind(String(event.get("id", ""))),
			"normal"
		)
		button.disabled = not available
		body.add_child(button)

	var job_finished := _session.job_state.get("result", {}) is Dictionary and not Dictionary(_session.job_state.get("result", {})).is_empty()
	var at_job_location := _is_job_location()
	if bool(model.get("job_available", false)) and not job_finished:
		var job_card := _card(body, "accent")
		job_card.add_child(_make_label("Есть короткая смена", 19, COLOUR_TEXT, false))
		job_card.add_child(_make_label("Шесть рабочих ситуаций. Оплата и усталость зависят от решений.", 14, COLOUR_MUTED, true))
		job_card.add_child(_make_button("Начать работу", _on_begin_job, "accent"))
	elif at_job_location and job_finished:
		var finished := _card(body, "normal")
		finished.add_child(_make_label("Сегодняшняя смена завершена.", 14, COLOUR_MUTED, true))

	var evening_wait: Dictionary = model.get("wait_until_evening", {}) if model.get("wait_until_evening", {}) is Dictionary else {}
	if bool(evening_wait.get("visible", false)):
		var wait_card := _card(body, "normal")
		wait_card.add_child(_make_label("Скоротать время", 19, COLOUR_TEXT, false))
		var wait_available := bool(evening_wait.get("available", false))
		var wait_minutes := int(evening_wait.get("minutes", 0))
		var wait_description := (
			"До вечера около %d мин. Ожидание восстановит немного сил, но усилит голод." % wait_minutes
			if wait_available
			else String(evening_wait.get("reason", "Сейчас это действие недоступно"))
		)
		wait_card.add_child(_make_label(wait_description, 14, COLOUR_MUTED, true))
		var wait_button := _make_button("Дождаться 18:00", _on_wait_until_evening, "normal")
		wait_button.disabled = not wait_available
		wait_card.add_child(wait_button)

	var shelters := _session.available_shelters()
	if not shelters.is_empty():
		var shelter_card := _card(body, "normal")
		shelter_card.add_child(_make_label("Завершить день", 19, COLOUR_TEXT, false))
		shelter_card.add_child(_make_label("Выбор ночлега завершит первый день. Некоторые места требуют подготовки.", 14, COLOUR_MUTED, true))
		shelter_card.add_child(_make_button("Выбрать ночлег", _show_shelter_screen, "normal"))


func _on_map_location_selected(location_id: String) -> void:
	if _session == null:
		return
	if location_id == _session.location:
		_selected_destination = ""
	else:
		_selected_destination = location_id
	_show_map_screen()


func _clear_map_selection() -> void:
	_selected_destination = ""
	_show_map_screen()


func _on_travel(destination: String, mode: String) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.travel(destination, mode)
	if not _require_success(result):
		return
	_selected_destination = ""
	_save_session(true)
	_show_map_screen()
	_toast("Вы прибыли в новую локацию.", false)


func _on_select_event() -> void:
	if _session == null:
		return
	var result: Dictionary = _session.select_event()
	if not _require_success(result):
		return
	_save_session(true)
	_show_event_screen()


func _on_enter_event(event_id: String) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.enter_event(event_id)
	if not _require_success(result):
		return
	_save_session(true)
	_show_event_screen()


func _show_event_screen() -> void:
	if _session == null:
		return
	_screen_kind = "event"
	var model: Dictionary = _session.get_current_event_model()
	if model.is_empty():
		_toast("Событие не удалось открыть.", true)
		return
	_set_background(String(model.get("background_key", DEFAULT_BACKGROUND)))
	var start_data := _selected_start_data()
	var is_opening_event := (
		String(model.get("kind", "")) == "event"
		and not start_data.is_empty()
		and String(model.get("id", "")) == String(start_data.get("opening_event_id", start_data.get("opening_card_id", "")))
	)
	var shell := _new_game_shell("Начало истории" if is_opening_event else "Событие", false)
	var body: VBoxContainer = shell["body"]

	var location_chip := _make_label(String(model.get("location_title", "Город")), 13, COLOUR_GOLD, false)
	body.add_child(location_chip)
	if is_opening_event:
		var start_card := _card(body, "accent")
		start_card.add_child(_make_label("ВАШ СТАРТ", 12, COLOUR_GOLD, false))
		start_card.add_child(_make_label(String(start_data.get("title", "Начало пути")), 23, COLOUR_TEXT, true))
		start_card.add_child(_make_label(String(start_data.get("text", "")), 15, COLOUR_MUTED, true))
	var event_card := _card(body, "light")
	event_card.add_child(_make_label(String(model.get("title", "Событие")), 27, COLOUR_TEXT, true))
	event_card.add_child(_make_label(String(model.get("text", "")), 17, COLOUR_TEXT, true))

	body.add_child(_section_heading("Ваше решение"))
	for raw_option in model.get("options", []):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var locked := bool(option.get("locked", false))
		var option_card := _card(body, "normal")
		var button := _make_button(
			String(option.get("text", "Продолжить")),
			_on_event_choice.bind(String(option.get("id", ""))),
			"accent" if not locked else "quiet"
		)
		button.disabled = locked
		option_card.add_child(button)
		if locked:
			option_card.add_child(_make_label(_reason_text(option.get("reasons", [])), 13, COLOUR_DANGER, true))
	_animate_screen(shell["screen"])


func _on_event_choice(choice_id: String) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.resolve_choice(choice_id)
	if not _require_success(result):
		return
	var outcome := String(result.get("outcome", ""))
	_save_session(true)
	_show_session_phase()
	if not outcome.is_empty():
		_toast(outcome, false)


func _on_begin_job() -> void:
	if _session == null:
		return
	var result: Dictionary = _session.begin_job("standard")
	if not _require_success(result):
		return
	_save_session(true)
	_show_job_screen()


func _on_wait_until_evening() -> void:
	if _session == null:
		return
	var result: Dictionary = _session.wait_until_evening()
	if not _require_success(result):
		return
	_save_session(true)
	_show_map_screen()
	_toast(String(result.get("outcome", "Наступил вечер.")), false)


func _show_job_screen() -> void:
	if _session == null:
		return
	_screen_kind = "job"
	var model: Dictionary = _session.current_job_prompt()
	if model.is_empty():
		_toast("Рабочий раунд не найден.", true)
		return
	_set_background(_current_background_key())
	var shell := _new_game_shell("Рабочая смена", false)
	var body: VBoxContainer = shell["body"]

	var progress_card := _card(body, "normal")
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 12)
	progress_card.add_child(progress_row)
	var round_label := _make_label("Раунд %d из %d" % [int(model.get("round", 1)), int(model.get("rounds_total", 6))], 17, COLOUR_TEXT, false)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.add_child(round_label)
	progress_row.add_child(_make_label("Счёт: %d" % int(model.get("score", 0)), 17, COLOUR_GOLD, false))
	var progress := ProgressBar.new()
	progress.max_value = float(model.get("rounds_total", 6))
	progress.value = float(model.get("round", 1)) - 1.0
	progress.show_percentage = false
	progress.custom_minimum_size.y = 9.0
	progress.add_theme_stylebox_override("background", _flat_box(Color("#111816"), 5))
	progress.add_theme_stylebox_override("fill", _flat_box(COLOUR_GREEN, 5))
	progress_card.add_child(progress)

	var task_card := _card(body, "light")
	task_card.add_child(_make_label(String(model.get("job_title", "Работа")), 14, COLOUR_GOLD, true))
	task_card.add_child(_make_label(String(model.get("text", "Выберите действие")), 23, COLOUR_TEXT, true))
	body.add_child(_section_heading("Как поступить"))
	for raw_choice in model.get("choices", []):
		if not raw_choice is Dictionary:
			continue
		var choice: Dictionary = raw_choice
		var locked := bool(choice.get("locked", false))
		var choice_card := _card(body, "normal")
		var button := _make_button(
			String(choice.get("label", "Действовать")),
			_on_job_answer.bind(String(choice.get("id", ""))),
			"accent" if not locked else "quiet"
		)
		button.disabled = locked
		choice_card.add_child(button)
		if locked:
			choice_card.add_child(_make_label(_reason_text(choice.get("reasons", [])), 13, COLOUR_DANGER, true))
	_animate_screen(shell["screen"])


func _on_job_answer(choice_id: String) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.answer_job(choice_id)
	if not _require_success(result):
		return
	_save_session(true)
	if bool(result.get("completed", false)):
		_last_job_result = Dictionary(result.get("result", {})).duplicate(true)
		_show_job_result_screen()
		return
	var gained := int(result.get("round_score", 0))
	_show_job_screen()
	_toast("Результат раунда: +%d" % gained, false)


func _show_job_result_screen() -> void:
	if _session == null:
		return
	_screen_kind = "job_result"
	_set_background(_current_background_key())
	var shell := _new_game_shell("Смена завершена", false)
	var body: VBoxContainer = shell["body"]
	var result := _last_job_result
	if result.is_empty() and _session.job_state.get("result", {}) is Dictionary:
		result = Dictionary(_session.job_state.get("result", {})).duplicate(true)
	var result_card := _card(body, "accent")
	result_card.add_child(_make_label(String(result.get("label", "Работа окончена")), 28, COLOUR_TEXT, true))
	result_card.add_child(_make_label("Итоговый счёт: %d из 18" % int(result.get("score", 0)), 18, COLOUR_GOLD, false))
	var transaction: Dictionary = result.get("transaction", {}) if result.get("transaction", {}) is Dictionary else {}
	var changes := _format_changes(transaction.get("changes", []))
	if not changes.is_empty():
		result_card.add_child(_make_label(changes, 15, COLOUR_MUTED, true))
	body.add_child(_make_button("Вернуться на карту", _show_map_screen, "accent"))
	_animate_screen(shell["screen"])


func _show_shelter_screen() -> void:
	if _session == null:
		return
	_screen_kind = "shelter"
	_set_background(_current_background_key())
	var shell := _new_game_shell("Выбор ночлега", false)
	var body: VBoxContainer = shell["body"]
	body.add_child(_make_label("Ночь завершит первый день", 25, COLOUR_TEXT, true))
	body.add_child(_make_label("Оцените риск и качество отдыха. После подтверждения время перейдёт к следующему утру.", 15, COLOUR_MUTED, true))

	var shelters := _session.available_shelters()
	if shelters.is_empty():
		var empty_card := _card(body, "normal")
		empty_card.add_child(_make_label("В этой локации подходящего места нет. Вернитесь на карту и поищите в другом месте.", 16, COLOUR_MUTED, true))
	else:
		for raw_shelter in shelters:
			if not raw_shelter is Dictionary:
				continue
			var shelter: Dictionary = raw_shelter
			var locked := bool(shelter.get("locked", false))
			var shelter_card := _card(body, "light" if not locked else "normal")
			shelter_card.add_child(_make_label(String(shelter.get("title", "Ночлег")), 22, COLOUR_TEXT if not locked else COLOUR_MUTED, true))
			shelter_card.add_child(_make_label(String(shelter.get("description", "")), 15, COLOUR_MUTED, true))
			shelter_card.add_child(_make_label(
				"Качество: %s   Риск: %s" % [
					_rating_dots(int(shelter.get("quality", 0))),
					_rating_dots(int(shelter.get("risk", 0))),
				],
				14,
				COLOUR_GOLD,
				true
			))
			var choose := _make_button("Ночевать здесь", _on_choose_shelter.bind(String(shelter.get("id", ""))), "accent")
			choose.disabled = locked
			shelter_card.add_child(choose)
			if locked:
				shelter_card.add_child(_make_label(_reason_text(shelter.get("reasons", [])), 13, COLOUR_DANGER, true))
	body.add_child(_make_button("Вернуться на карту", _show_map_screen, "quiet"))
	_animate_screen(shell["screen"])


func _on_choose_shelter(shelter_id: String) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.choose_shelter(shelter_id)
	if not _require_success(result):
		return
	_save_session(true)
	_show_day_summary()


func _show_day_summary() -> void:
	if _session == null:
		return
	_screen_kind = "summary"
	_set_background(_current_background_key())
	var shell := _new_game_shell("Итог дня", false)
	var body: VBoxContainer = shell["body"]
	var biography: Dictionary = {}
	if not _session.biography.is_empty() and _session.biography.back() is Dictionary:
		biography = Dictionary(_session.biography.back()).duplicate(true)

	var summary_card := _card(body, "accent")
	summary_card.add_child(_make_label("Первый день прожит", 30, COLOUR_TEXT, true))
	summary_card.add_child(_make_label(String(biography.get("summary", "Герой пережил свой первый день в городе.")), 17, COLOUR_TEXT, true))

	var final_state: Dictionary = biography.get("final_state", {}) if biography.get("final_state", {}) is Dictionary else {}
	var facts_card := _card(body, "normal")
	facts_card.add_child(_make_label("Что осталось к утру", 20, COLOUR_TEXT, false))
	facts_card.add_child(_make_label("Деньги: %d" % int(final_state.get("money", _session.run_state.money)), 17, COLOUR_GOLD, false))
	var meters: Dictionary = final_state.get("meters", _session.run_state.meters) if final_state.get("meters", _session.run_state.meters) is Dictionary else {}
	for meter_id in ["health", "hunger", "energy", "tension", "morale"]:
		facts_card.add_child(_make_label("%s: %d / 100" % [METER_LONG_TITLES[meter_id], int(meters.get(meter_id, 0))], 15, COLOUR_MUTED, false))

	var job_result: Dictionary = biography.get("job_result", {}) if biography.get("job_result", {}) is Dictionary else {}
	if not job_result.is_empty():
		var work_card := _card(body, "normal")
		work_card.add_child(_make_label("Работа", 20, COLOUR_TEXT, false))
		work_card.add_child(_make_label("%s · счёт %d" % [String(job_result.get("label", "Смена завершена")), int(job_result.get("score", 0))], 15, COLOUR_MUTED, true))

	var story_card := _card(body, "normal")
	story_card.add_child(_make_label("Личная история", 20, COLOUR_TEXT, false))
	story_card.add_child(_make_label(
		"Увидено событий: %d\nЗавершено событий: %d" % [
			Array(biography.get("seen_events", [])).size(),
			Array(biography.get("completed_events", [])).size(),
		],
		15,
		COLOUR_MUTED,
		true
	))
	body.add_child(_make_button("В главное меню", _leave_completed_run, "normal"))
	body.add_child(_make_button("Начать новую жизнь", _start_character_creation, "accent"))
	_animate_screen(shell["screen"])


func _leave_completed_run() -> void:
	_save_session(false)
	_show_main_menu()


func _new_game_shell(title: String, include_navigation: bool) -> Dictionary:
	var screen := _new_screen()
	screen.add_child(_game_header(title))
	screen.add_child(_meters_panel())
	var scroll := _scroll_body(screen)
	var body: VBoxContainer = scroll.get_meta("body")
	if include_navigation:
		screen.add_child(_game_navigation())
	return {"screen": screen, "body": body, "scroll": scroll}


func _game_header(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box(COLOUR_PANEL_LIGHT, 16))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var first_row := HBoxContainer.new()
	first_row.add_theme_constant_override("separation", 8)
	content.add_child(first_row)
	var title_label := _make_label(title, 20, COLOUR_TEXT, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first_row.add_child(title_label)
	var settings_button := _make_button("Настр.", _open_settings_from_game, "quiet")
	settings_button.custom_minimum_size = Vector2(76.0, 56.0)
	first_row.add_child(settings_button)
	if _session != null:
		var map_model := _session.get_map_model()
		var location_name := _location_title(map_model, _session.location)
		var stamp := _session.run_state.calendar.current_stamp()
		var minute := int(stamp.get("minute_of_day", 0))
		var info := "%s · %02d.%02d.%04d · %02d:%02d" % [
			location_name,
			int(stamp.get("day", 1)),
			int(stamp.get("month", 1)),
			int(stamp.get("year", 1970)),
			int(minute / 60),
			minute % 60,
		]
		content.add_child(_make_label(info, 13, COLOUR_MUTED, true))
		content.add_child(_make_label("Деньги: %d" % _session.run_state.money, 14, COLOUR_GOLD, false))
	return panel


func _meters_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box(COLOUR_PANEL, 14))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	if _session == null:
		return panel
	for meter_id in ["health", "hunger", "energy", "tension", "morale"]:
		var value := _session.run_state.get_meter(meter_id)
		var meter_box := VBoxContainer.new()
		meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter_box.tooltip_text = METER_LONG_TITLES[meter_id]
		grid.add_child(meter_box)
		var meter_label := _make_label("%s %d" % [METER_TITLES[meter_id], value], 12, COLOUR_TEXT, false)
		meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meter_box.add_child(meter_label)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.value = value
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(42.0, 7.0)
		bar.add_theme_stylebox_override("background", _flat_box(Color("#101614"), 4))
		bar.add_theme_stylebox_override("fill", _flat_box(_meter_colour(meter_id, value), 4))
		meter_box.add_child(bar)
	return panel


func _game_navigation() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box(COLOUR_PANEL_LIGHT, 15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 7)
	panel.add_child(grid)
	var map_button := _make_button("Карта", _show_map_screen, "normal")
	map_button.disabled = _session == null or _session.phase != "map"
	grid.add_child(map_button)
	var explore_button := _make_button("Осмотреться", _on_select_event, "normal")
	explore_button.disabled = _session == null or _session.phase != "map" or not _has_selectable_event(_session.get_map_model().get("events", []))
	grid.add_child(explore_button)
	var shelter_button := _make_button("Ночлег", _show_shelter_screen, "normal")
	shelter_button.disabled = _session == null or _session.phase != "map" or _session.available_shelters().is_empty()
	grid.add_child(shelter_button)
	return panel


func _new_screen() -> VBoxContainer:
	_clear_screen()
	var screen := VBoxContainer.new()
	screen.name = "ActiveScreen"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_theme_constant_override("separation", 10)
	_screen_host.add_child(screen)
	return screen


func _clear_screen() -> void:
	for child in _screen_host.get_children():
		_screen_host.remove_child(child)
		child.queue_free()


func _scroll_body(screen: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 12
	screen.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body.custom_minimum_size.x = 1.0
	scroll.add_child(body)
	scroll.set_meta("body", body)
	return scroll


func _simple_header(title: String, back_text: String, callback: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box(COLOUR_PANEL_LIGHT, 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var heading := _make_label(title, 23, COLOUR_TEXT, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var back := _make_button(back_text, callback, "quiet")
	back.custom_minimum_size.x = 88.0
	row.add_child(back)
	return panel


func _card(parent: Container, tone: String = "normal") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var colour := COLOUR_PANEL
	match tone:
		"light":
			colour = COLOUR_PANEL_LIGHT
		"accent":
			colour = Color("#31443beF")
		"map":
			colour = Color("#121918e8")
	panel.add_theme_stylebox_override("panel", _panel_box(colour, 17))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)
	return content


func _section_heading(text_value: String) -> Label:
	var label := _make_label(text_value.to_upper(), 14, COLOUR_GOLD, true)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(COLOUR_INK, 0.7))
	return label


func _add_menu_text_outline(label: Label, size: int) -> void:
	label.add_theme_constant_override("outline_size", size)
	label.add_theme_color_override("font_outline_color", Color(COLOUR_INK, 0.92))


func _make_label(
	text_value: String,
	font_size: int,
	colour: Color = COLOUR_TEXT,
	wrap: bool = true
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", _scaled_font(font_size))
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if not wrap else TextServer.OVERRUN_NO_TRIMMING
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_button(
	text_value: String,
	callback: Callable = Callable(),
	variant: String = "normal"
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_base_button(button, variant)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _style_base_button(button: BaseButton, variant: String) -> void:
	button.custom_minimum_size.y = MIN_TOUCH_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", _scaled_font(16))
	var normal := Color("#3a4844")
	var hover := Color("#4b5c57")
	var pressed := Color("#2f3b38")
	match variant:
		"accent":
			normal = COLOUR_GREEN
			hover = COLOUR_GREEN_HOVER
			pressed = Color("#5f816a")
		"danger":
			normal = COLOUR_RUST
			hover = COLOUR_RUST_HOVER
			pressed = Color("#945739")
		"quiet":
			normal = Color("#283330d9")
			hover = Color("#394641ed")
			pressed = Color("#202a27")
	button.add_theme_stylebox_override("normal", _button_box(normal, COLOUR_BORDER))
	button.add_theme_stylebox_override("hover", _button_box(hover, Color("#99aa9f")))
	button.add_theme_stylebox_override("pressed", _button_box(pressed, COLOUR_GOLD))
	button.add_theme_stylebox_override("focus", _button_box(hover, COLOUR_GOLD, 2))
	button.add_theme_stylebox_override("disabled", _button_box(Color("#242c2a"), Color("#46504d")))
	button.add_theme_color_override("font_color", Color("#fbf7ed"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#7f8985"))
	button.resized.connect(_update_button_pivot.bind(button))
	button.button_down.connect(_animate_button.bind(button, 0.975))
	button.button_up.connect(_animate_button.bind(button, 1.0))
	button.mouse_entered.connect(_animate_button.bind(button, 1.012))
	button.mouse_exited.connect(_animate_button.bind(button, 1.0))


func _update_button_pivot(button: BaseButton) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _animate_button(button: BaseButton, target_scale: float) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.11)


func _animate_screen(screen: Control) -> void:
	screen.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := screen.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "modulate", Color.WHITE, 0.22)


func _vertical_gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap


func _panel_box(colour: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = Color(COLOUR_BORDER, 0.68)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 15.0
	style.content_margin_right = 15.0
	style.content_margin_top = 13.0
	style.content_margin_bottom = 13.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _button_box(colour: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(13)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _flat_box(colour: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(radius)
	return style


func _apply_theme() -> void:
	_ui_theme = Theme.new()
	_ui_theme.default_font_size = _scaled_font(16)
	_ui_theme.set_color("font_color", "Label", COLOUR_TEXT)
	_ui_theme.set_color("font_color", "Button", COLOUR_TEXT)
	_ui_theme.set_constant("separation", "VBoxContainer", 8)
	theme = _ui_theme


func _scaled_font(base_size: int) -> int:
	return maxi(int(round(float(base_size) * float(_preferences.get("font_scale", 1.0)))), 11)


func _update_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	var left := maxf(12.0, viewport_size.x * 0.032)
	var right := left
	var top := 12.0
	var bottom := 12.0
	if OS.has_feature("android") or OS.has_feature("ios"):
		var screen_size := Vector2(DisplayServer.screen_get_size())
		var safe := DisplayServer.get_display_safe_area()
		if screen_size.x > 0.0 and screen_size.y > 0.0 and safe.size.x > 0:
			var scale := Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)
			left = maxf(left, float(safe.position.x) * scale.x + 6.0)
			top = maxf(top, float(safe.position.y) * scale.y + 6.0)
			right = maxf(right, float(screen_size.x - safe.end.x) * scale.x + 6.0)
			bottom = maxf(bottom, float(screen_size.y - safe.end.y) * scale.y + 6.0)
	_safe_area.add_theme_constant_override("margin_left", int(round(left)))
	_safe_area.add_theme_constant_override("margin_right", int(round(right)))
	_safe_area.add_theme_constant_override("margin_top", int(round(top)))
	_safe_area.add_theme_constant_override("margin_bottom", int(round(bottom)))
	var available_width := maxf(viewport_size.x - left - right, 280.0)
	var available_height := maxf(viewport_size.y - top - bottom, 320.0)
	_content_root.custom_minimum_size = Vector2(minf(available_width, MAX_CONTENT_WIDTH), available_height)


func _set_background(background_key: String) -> void:
	var resolved_key := background_key if not background_key.is_empty() else DEFAULT_BACKGROUND
	if resolved_key != _last_background:
		var path := "res://assets/backgrounds/%s.png" % resolved_key
		if ResourceLoader.exists(path):
			var loaded := ResourceLoader.load(path)
			if loaded is Texture2D:
				_backdrop.texture = loaded
				_last_background = resolved_key
	_update_psyche_effect()


func _update_psyche_effect() -> void:
	if not is_instance_valid(_backdrop):
		return
	var intensity := 0.0
	if _session != null:
		intensity = _session.psyche_intensity()
	var material := _backdrop.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("psyche_intensity", intensity)


func _background_from_map(model: Dictionary) -> String:
	var current_id := String(model.get("current_location_id", ""))
	for raw_location in model.get("locations", []):
		if raw_location is Dictionary and String(raw_location.get("id", "")) == current_id:
			return String(raw_location.get("background_key", DEFAULT_BACKGROUND))
	return DEFAULT_BACKGROUND


func _current_background_key() -> String:
	return DEFAULT_BACKGROUND if _session == null else _background_from_map(_session.get_map_model())


func _location_title(model: Dictionary, location_id: String) -> String:
	for raw_location in model.get("locations", []):
		if raw_location is Dictionary and String(raw_location.get("id", "")) == location_id:
			return String(raw_location.get("title", location_id))
	return location_id if not location_id.is_empty() else "Город"


func _has_selectable_event(events: Array) -> bool:
	for raw_event in events:
		if raw_event is Dictionary and bool(raw_event.get("available", false)) and not bool(raw_event.get("completed", false)):
			return true
	return false


func _meter_colour(meter_id: String, value: int) -> Color:
	var wellbeing := float(value) / 100.0
	if meter_id in ["hunger", "tension"]:
		wellbeing = 1.0 - wellbeing
	return COLOUR_DANGER.lerp(COLOUR_GREEN_HOVER, clampf(wellbeing, 0.0, 1.0))


func _reason_text(raw_reasons: Variant) -> String:
	if not raw_reasons is Array:
		return "Вариант сейчас недоступен."
	var messages: PackedStringArray = []
	for raw_reason in raw_reasons:
		if raw_reason is Dictionary:
			var message := _localized_reason_message(raw_reason)
			if not message.is_empty():
				messages.append(message)
		elif not String(raw_reason).is_empty():
			messages.append(String(raw_reason))
	return "Недоступно: %s" % "; ".join(messages) if not messages.is_empty() else "Вариант сейчас недоступен."


func _localized_reason_message(reason: Dictionary) -> String:
	var message := String(reason.get("message", ""))
	var kind := String(reason.get("kind", ""))
	var identifier := String(reason.get("id", ""))
	var title := _requirement_title(kind, identifier)
	var condition: Dictionary = reason.get("condition", {}) if reason.get("condition", {}) is Dictionary else {}
	var custom_reason := String(condition.get("blocked_reason", ""))
	var code := String(reason.get("code", ""))
	var required: Variant = reason.get("required", null)
	var actual: Variant = reason.get("actual", null)
	var comparison_failure := code.ends_with("_too_low") or code.ends_with("_too_high") or code.ends_with("_mismatch")
	if custom_reason.is_empty() and comparison_failure and (required is int or required is float) and (actual is int or actual is float):
		return "%s: нужно %s, сейчас %s" % [
			title,
			_requirement_phrase(String(reason.get("operator", ">=")), float(required)),
			_format_ui_number(float(actual)),
		]
	if not identifier.is_empty() and title != identifier:
		message = message.replace(identifier, title)
	return message


func _requirement_title(kind: String, identifier: String) -> String:
	match kind:
		"stat":
			return String(STAT_TITLES.get(identifier, _humanize_identifier(identifier, "Характеристика")))
		"state":
			return String(METER_LONG_TITLES.get(identifier, _humanize_identifier(identifier, "Состояние")))
		"money":
			return "Деньги"
		"skill":
			return String(SKILL_TITLES.get(identifier, _humanize_identifier(identifier, "Навык")))
		"polarity":
			return String(POLARITY_TITLES.get(identifier, _humanize_identifier(identifier, "Полярность")))
		"item":
			return String(ITEM_TITLES.get(identifier, _humanize_identifier(identifier, "Предмет")))
		"knowledge":
			return String(KNOWLEDGE_TITLES.get(identifier, _humanize_identifier(identifier, "Знание")))
	return _humanize_identifier(identifier, "Условие")


func _humanize_identifier(identifier: String, fallback: String) -> String:
	return fallback if identifier.is_empty() else identifier.replace("_", " ").capitalize()


func _requirement_phrase(operator: String, required: float) -> String:
	var value := _format_ui_number(required)
	match operator:
		">=":
			return "не меньше %s" % value
		">":
			return "больше %s" % value
		"<=":
			return "не больше %s" % value
		"<":
			return "меньше %s" % value
		"==":
			return "ровно %s" % value
		"!=":
			return "не %s" % value
	return value


func _format_ui_number(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else "%.2f" % value


func _rating_dots(value: int) -> String:
	return "%d / 5" % clampi(value, 0, 5)


func _format_changes(raw_changes: Variant) -> String:
	if not raw_changes is Array:
		return ""
	var lines: PackedStringArray = []
	for raw_change in raw_changes:
		if not raw_change is Dictionary:
			continue
		var change: Dictionary = raw_change
		var target_id := String(change.get("target_id", change.get("target_kind", "")))
		var title: String = String(METER_LONG_TITLES.get(
			target_id,
			_change_title(target_id)
		))
		var effect_type := String(change.get("effect_type", ""))
		var delta: Variant = change.get("delta", null)
		if effect_type == "advance_time":
			lines.append("Время: +%d мин." % int(delta))
		elif delta is int or delta is float:
			var number := int(round(float(delta)))
			lines.append("%s: %s%d" % [title, "+" if number >= 0 else "", number])
		elif not String(change.get("description", "")).is_empty():
			lines.append(String(change.get("description", "")))
		if lines.size() >= 8:
			break
	return "\n".join(lines)


func _change_title(identifier: String) -> String:
	match identifier:
		"money":
			return "Деньги"
		"mastery_points":
			return "Очки освоения"
		"cargo_handling":
			return "Работа с грузом"
		"calendar":
			return "Время"
		_:
			return identifier.replace("_", " ").capitalize()


func _require_success(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		return true
	_toast(_result_message(result), true)
	return false


func _result_message(result: Dictionary) -> String:
	var message := String(result.get("message", result.get("error", "")))
	return message if not message.is_empty() else "Неизвестная ошибка"


func _save_session(show_failure: bool) -> Dictionary:
	if _session == null:
		return {"ok": true, "code": "no_session"}
	if _save_in_progress:
		return {"ok": false, "code": "save_in_progress", "error": "Сохранение уже выполняется"}
	_save_in_progress = true
	var result: Dictionary = FirstDaySaveScript.save_session(_session)
	_save_in_progress = false
	if show_failure and not bool(result.get("ok", false)):
		_toast("Не удалось сохранить игру: %s" % _result_message(result), true)
	return result


func _save_candidate_exists() -> bool:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(FirstDaySaveScript.DEFAULT_SAVE_PATH + suffix):
			return true
	return false


func _clear_save_candidates_for_new_run() -> Dictionary:
	# Delete the pending temporary file last. If cleanup fails part-way through,
	# either the primary or the newest temporary revision remains recoverable.
	for suffix in [".bak", "", ".tmp"]:
		var virtual_path: String = FirstDaySaveScript.DEFAULT_SAVE_PATH + suffix
		if not FileAccess.file_exists(virtual_path):
			continue
		var absolute_path := ProjectSettings.globalize_path(virtual_path)
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK or FileAccess.file_exists(virtual_path):
			return {
				"ok": false,
				"code": "save_cleanup_failed",
				"message": "Не удалось безопасно очистить прежнее сохранение",
				"path": virtual_path,
				"engine_error": remove_error,
			}
	return {"ok": true}


func _apply_preferences_to_session() -> void:
	if _session == null:
		return
	for key in ["show_locked_options", "psyche_effect_mode", "font_scale"]:
		_session.set_setting(key, _preferences[key])


func _selected_start_data() -> Dictionary:
	if _session == null:
		return {}
	for raw_start in FirstDayContentScript.start_situations():
		if raw_start is Dictionary and String(raw_start.get("id", "")) == _session.start:
			return Dictionary(raw_start).duplicate(true)
	return {}


func _route_fare(destination_id: String) -> int:
	if _session == null:
		return -1
	for raw_route in FirstDayContentScript.routes_from(_session.location):
		if not raw_route is Dictionary:
			continue
		var route_destination := String(raw_route.get("destination_id", raw_route.get("to", "")))
		if route_destination == destination_id:
			return int(raw_route.get("fare", -1))
	return -1


func _is_job_location() -> bool:
	if _session == null:
		return false
	var job: Dictionary = FirstDayContentScript.job()
	return String(job.get("location_id", "")) == _session.location


func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) != OK:
		return
	var show_locked: Variant = config.get_value("accessibility", "show_locked_options", false)
	var psyche_mode := String(config.get_value("visual", "psyche_effect_mode", "full"))
	var font_scale := float(config.get_value("accessibility", "font_scale", 1.0))
	_preferences["show_locked_options"] = bool(show_locked)
	_preferences["psyche_effect_mode"] = psyche_mode if psyche_mode in ["full", "reduced", "off"] else "full"
	_preferences["font_scale"] = clampf(font_scale, 0.8, 1.6)


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("accessibility", "show_locked_options", bool(_preferences["show_locked_options"]))
	config.set_value("accessibility", "font_scale", float(_preferences["font_scale"]))
	config.set_value("visual", "psyche_effect_mode", String(_preferences["psyche_effect_mode"]))
	config.save(UI_SETTINGS_PATH)


func _toast(message: String, is_error: bool) -> void:
	if not is_instance_valid(_overlay_layer) or message.is_empty():
		return
	for child in _overlay_layer.get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_left = 0.06
	panel.anchor_right = 0.94
	panel.anchor_top = 0.78
	panel.anchor_bottom = 0.96
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	panel.add_theme_stylebox_override("panel", _panel_box(Color("#582f2ded") if is_error else Color("#2f4439ed"), 15))
	var label := _make_label(message, 14, COLOUR_TEXT, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_overlay_layer.add_child(panel)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate", Color.WHITE, 0.16)
	tween.tween_interval(2.8 if is_error else 2.1)
	tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.24)
	tween.tween_callback(panel.queue_free)
