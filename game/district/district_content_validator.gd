class_name DistrictContentValidator
extends RefCounted

## Everything that checks the district catalog, kept away from the catalog itself.
##
## The content is a literal a designer reads; this is the machine that refuses it
## when it lies — an event pointing at a place that does not exist, a cost with
## no guard in front of it, a job whose shift never ends. The two lived in one
## file for a long time and the file grew to the point where finding the catalog
## meant scrolling past eight hundred lines of assertions.
##
## The dependency runs one way only: the checker knows the catalog, the catalog
## does not know the checker.

const Content := preload("res://game/district/district_content.gd")


static func _array_copy(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


static func validate_condition_packet(
	raw_conditions: Variant,
	context: String = "content"
) -> Dictionary:
	var errors: Array = []
	if not raw_conditions is Array:
		errors.append("Условия в %s должны быть массивом" % context)
	else:
		_validate_conditions(raw_conditions, context, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func validate_effect_packet(
	raw_effects: Variant,
	context: String = "content"
) -> Dictionary:
	var errors: Array = []
	if not raw_effects is Array:
		errors.append("Эффекты в %s должны быть массивом" % context)
	else:
		_validate_effects(raw_effects, context, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static var _validation_cache: Dictionary = {}


## The first-day content is a static literal: it cannot change while the game
## runs, yet every session validation re-derived and re-checked all of it.
## The answer is computed once and handed out as a copy.
static func validate_content() -> Dictionary:
	if _validation_cache.is_empty():
		_validation_cache = _validate_content_uncached()
	return _validation_cache.duplicate(true)


static func reset_validation_cache_for_tests() -> void:
	_validation_cache = {}


static func _validate_content_uncached() -> Dictionary:
	var errors: Array = []
	var place_map := Content.locations()
	var cards := Content.event_cards()
	var starts := Content.start_situations()
	var shelter_map := Content.shelters()
	var family_ids: Dictionary = {}
	var choice_ids: Dictionary = {}
	var deferred_ids: Dictionary = {}
	var route_count := 0
	var choice_count := 0
	var deferred_count := 0

	var district_data := Content.district()
	if String(district_data.get("id", "")) != Content.DISTRICT_ID:
		errors.append("Район имеет неверный id")
	_validate_display_text(String(district_data.get("title", "")), "название района", errors)
	_validate_display_text(String(district_data.get("description", "")), "описание района", errors)
	# M4 grows the district to eight and allows twelve. The floor is what the
	# week needs; the ceiling is what one district can stay legible at.
	if place_map.size() < 6 or place_map.size() > 12:
		errors.append("В районе должно быть от 6 до 12 локаций")
	for required_id in Content.REQUIRED_LOCATION_IDS:
		if not place_map.has(required_id):
			errors.append("Отсутствует обязательная локация: %s" % required_id)

	for key in place_map:
		var place: Variant = place_map[key]
		if not place is Dictionary:
			errors.append("Локация %s должна быть Dictionary" % key)
			continue
		var place_id := String(place.get("id", ""))
		if place_id != String(key) or not _valid_identifier(place_id):
			errors.append("Некорректный id локации: %s" % key)
		if String(place.get("district_id", "")) != Content.DISTRICT_ID:
			errors.append("Локация %s относится к неизвестному району" % place_id)
		if String(place.get("title", "")).strip_edges().is_empty():
			errors.append("У локации %s нет названия" % place_id)
		_validate_display_text(String(place.get("title", "")), "название локации %s" % place_id, errors)
		_validate_display_text(String(place.get("description", "")), "описание локации %s" % place_id, errors)
		if String(place.get("background_id", "")).strip_edges().is_empty():
			errors.append("У локации %s нет background_id" % place_id)
		var routes := _array_copy(place.get("routes", []))
		route_count += routes.size()
		for route_value in routes:
			if not route_value is Dictionary:
				errors.append("Маршрут из %s должен быть Dictionary" % place_id)
				continue
			var destination_id := String(route_value.get("destination_id", ""))
			if not place_map.has(destination_id):
				errors.append("Маршрут из %s ведёт в неизвестную локацию %s" % [place_id, destination_id])
			if destination_id == place_id:
				errors.append("Маршрут %s не должен вести в исходную локацию" % place_id)
			if typeof(route_value.get("walk_minutes", null)) != TYPE_INT or int(route_value.get("walk_minutes", 0)) <= 0:
				errors.append("У маршрута %s -> %s неверное время пешком" % [place_id, destination_id])
			var has_fare: bool = route_value.has("fare")
			var has_bus_time: bool = route_value.has("bus_minutes")
			if has_fare != has_bus_time:
				errors.append("Автобусный маршрут %s -> %s должен содержать fare и bus_minutes вместе" % [place_id, destination_id])
			elif has_fare and (typeof(route_value["fare"]) != TYPE_INT or int(route_value["fare"]) < 0 or typeof(route_value["bus_minutes"]) != TYPE_INT or int(route_value["bus_minutes"]) <= 0):
				errors.append("У автобусного маршрута %s -> %s неверные параметры" % [place_id, destination_id])
	_validate_connected_map(place_map, errors)

	if starts.size() != 4:
		errors.append("Должно быть ровно 4 стартовые ситуации")
	var start_ids: Dictionary = {}
	var luck_totals: Dictionary = {}
	for luck in range(1, 11):
		luck_totals[str(luck)] = 0
	for start_value in starts:
		if not start_value is Dictionary:
			errors.append("Стартовая ситуация должна быть Dictionary")
			continue
		var start_id := String(start_value.get("id", ""))
		if not _valid_identifier(start_id) or start_ids.has(start_id):
			errors.append("Некорректный или повторный id старта: %s" % start_id)
		start_ids[start_id] = true
		_validate_display_text(String(start_value.get("title", "")), "название старта %s" % start_id, errors)
		_validate_display_text(String(start_value.get("text", "")), "текст старта %s" % start_id, errors)
		_validate_display_text(String(start_value.get("journal_message", "")), "запись старта %s" % start_id, errors)
		var start_location := String(start_value.get("location_id", ""))
		if not place_map.has(start_location):
			errors.append("Старт %s указывает неизвестную локацию" % start_id)
		var severity: Variant = start_value.get("severity", null)
		if typeof(severity) != TYPE_INT or int(severity) < 1 or int(severity) > 4:
			errors.append("Тяжесть старта %s должна быть от 1 до 4" % start_id)
		var opening_id := String(start_value.get("opening_event_id", ""))
		if not cards.has(opening_id):
			errors.append("Старт %s указывает неизвестную opening event" % start_id)
		elif String(cards[opening_id].get("location_id", "")) != start_location:
			errors.append("Старт %s и его opening event находятся в разных локациях" % start_id)
		var weights: Variant = start_value.get("weights_by_luck", {})
		if not weights is Dictionary or weights.size() != 10:
			errors.append("Старт %s должен иметь 10 весов Удачи" % start_id)
		else:
			for luck in range(1, 11):
				var luck_key := str(luck)
				var weight: Variant = weights.get(luck_key, null)
				if typeof(weight) != TYPE_INT or int(weight) < 0:
					errors.append("У старта %s неверный вес для Удачи %d" % [start_id, luck])
				else:
					luck_totals[luck_key] = int(luck_totals[luck_key]) + int(weight)
		var start_conditions := _array_copy(start_value.get("conditions", []))
		if not start_conditions.is_empty():
			errors.append("Старт %s не должен иметь условий: старт выбирается только весом Удачи" % start_id)
		var initial_effects := _array_copy(start_value.get("initial_effects", []))
		var session_effects := _array_copy(start_value.get("effects", []))
		if initial_effects != session_effects:
			errors.append("У старта %s расходятся initial_effects и effects" % start_id)
		_validate_effects(initial_effects, "старт %s" % start_id, errors)
		_validate_start_effects(initial_effects, start_id, errors)
		_validate_effect_packet_runtime(initial_effects, "старт %s" % start_id, errors)
	for luck in range(1, 11):
		if int(luck_totals[str(luck)]) <= 0:
			errors.append("Для Удачи %d нет доступного стартового веса" % luck)

	if cards.size() < 20 or cards.size() > 25:
		errors.append("Нужно от 20 до 25 карточек событий")
	for key in cards:
		var card_value: Variant = cards[key]
		if not card_value is Dictionary:
			errors.append("Карточка %s должна быть Dictionary" % key)
			continue
		var card_id := String(card_value.get("id", ""))
		if card_id != String(key) or not _valid_identifier(card_id):
			errors.append("Некорректный id карточки: %s" % key)
		var family_id := String(card_value.get("family_id", ""))
		if not _valid_identifier(family_id):
			errors.append("Карточка %s имеет неверный family_id" % card_id)
		else:
			family_ids[family_id] = true
		if not place_map.has(String(card_value.get("location_id", ""))):
			errors.append("Карточка %s относится к неизвестной локации" % card_id)
		if String(card_value.get("title", "")).strip_edges().is_empty() or String(card_value.get("text", "")).strip_edges().is_empty():
			errors.append("Карточка %s должна иметь название и текст" % card_id)
		_validate_display_text(String(card_value.get("title", "")), "название карточки %s" % card_id, errors)
		_validate_display_text(String(card_value.get("text", "")), "текст карточки %s" % card_id, errors)
		_validate_conditions(_array_copy(card_value.get("conditions", [])), "карточка %s" % card_id, errors)
		var choices: Variant = card_value.get("choices", [])
		if not choices is Array or choices.is_empty():
			errors.append("Карточка %s не содержит вариантов" % card_id)
			continue
		var has_unconditional := false
		choice_count += choices.size()
		for choice_value in choices:
			if not choice_value is Dictionary:
				errors.append("Вариант карточки %s должен быть Dictionary" % card_id)
				continue
			var choice_id := String(choice_value.get("id", ""))
			if not _valid_identifier(choice_id, true) or choice_ids.has(choice_id):
				errors.append("Некорректный или повторный id варианта: %s" % choice_id)
			choice_ids[choice_id] = true
			if not choice_id.begins_with(card_id + "."):
				errors.append("Id варианта %s не начинается с id карточки" % choice_id)
			if String(choice_value.get("label", "")).strip_edges().is_empty() or String(choice_value.get("outcome", "")).strip_edges().is_empty():
				errors.append("Вариант %s должен иметь label и outcome" % choice_id)
			_validate_display_text(String(choice_value.get("label", "")), "текст варианта %s" % choice_id, errors)
			_validate_display_text(String(choice_value.get("outcome", "")), "результат варианта %s" % choice_id, errors)
			var conditions := _array_copy(choice_value.get("conditions", []))
			if conditions.is_empty():
				has_unconditional = true
			_validate_conditions(conditions, "вариант %s" % choice_id, errors)
			var effects := _array_copy(choice_value.get("effects", []))
			_validate_effects(effects, "вариант %s" % choice_id, errors)
			_validate_guarded_costs(conditions, effects, "вариант %s" % choice_id, errors)
			_validate_deferred_references(effects, card_id, deferred_ids, errors)
			if conditions.is_empty():
				_validate_effect_packet_runtime(effects, "безусловный вариант %s" % choice_id, errors)
			deferred_count += _count_deferred(effects)
		if not has_unconditional:
			errors.append("Карточка %s не имеет безусловного выхода" % card_id)

	if family_ids.size() < 12 or family_ids.size() > 15:
		errors.append("Нужно от 12 до 15 семейств событий")
	if choice_count < 45 or choice_count > 70:
		errors.append("Нужно от 45 до 70 вариантов ответа")
	if deferred_count < 8 or deferred_count > 12:
		errors.append("Нужно от 8 до 12 отложенных эффектов")

	var job_data := Content.job()
	_validate_job(job_data, place_map, errors)
	_validate_skill_reachability(cards, job_data, errors)
	if shelter_map.size() != 4:
		errors.append("Должно быть ровно 4 варианта ночлега")
	var has_open_shelter := false
	for key in shelter_map:
		var shelter_value: Variant = shelter_map[key]
		if not shelter_value is Dictionary:
			errors.append("Ночлег %s должен быть Dictionary" % key)
			continue
		var shelter_id := String(shelter_value.get("id", ""))
		if shelter_id != String(key) or not _valid_identifier(shelter_id):
			errors.append("Некорректный id ночлега: %s" % key)
		if not place_map.has(String(shelter_value.get("location_id", ""))):
			errors.append("Ночлег %s находится в неизвестной локации" % shelter_id)
		_validate_display_text(String(shelter_value.get("title", "")), "название ночлега %s" % shelter_id, errors)
		_validate_display_text(String(shelter_value.get("description", "")), "описание ночлега %s" % shelter_id, errors)
		var shelter_conditions := _array_copy(shelter_value.get("conditions", []))
		if shelter_conditions.is_empty():
			has_open_shelter = true
		_validate_conditions(shelter_conditions, "ночлег %s" % shelter_id, errors)
		var shelter_effects := _array_copy(shelter_value.get("effects", []))
		_validate_effects(shelter_effects, "ночлег %s" % shelter_id, errors)
		_validate_guarded_costs(shelter_conditions, shelter_effects, "ночлег %s" % shelter_id, errors)
		_validate_effect_packet_runtime(shelter_effects, "ночлег %s" % shelter_id, errors)
	if not has_open_shelter:
		errors.append("Нужен хотя бы один безусловный ночлег")
	_validate_unlockable_references(cards, shelter_map, errors)
	_validate_start_reachability(starts, job_data, shelter_map, place_map, errors)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"counts": {
			"districts": 1,
			"locations": place_map.size(),
			"routes": route_count,
			"starts": starts.size(),
			"event_families": family_ids.size(),
			"event_cards": cards.size(),
			"event_choices": choice_count,
			"deferred_effects": deferred_count,
			"jobs": 1,
			"job_prompts": _array_copy(job_data.get("minigame", {}).get("prompts", [])).size(),
			"shelters": shelter_map.size(),
		},
	}


static func _validate_connected_map(place_map: Dictionary, errors: Array) -> void:
	if place_map.is_empty():
		return
	for origin_value in place_map.keys():
		var origin_id := String(origin_value)
		var visited := _reachable_locations(origin_id, place_map)
		if visited.size() != place_map.size():
			errors.append("Из локации %s нельзя добраться до всех точек района" % origin_id)


static func _validate_conditions(conditions: Array, context: String, errors: Array) -> void:
	const VALID_KINDS := ["stat", "state", "money", "item", "polarity", "skill", "knowledge"]
	const VALID_OPERATORS := [">=", ">", "==", "!=", "<", "<="]
	for condition_value in conditions:
		if not condition_value is Dictionary:
			errors.append("Условие в %s должно быть Dictionary" % context)
			continue
		var kind := String(condition_value.get("kind", condition_value.get("type", "")))
		var identifier := String(condition_value.get("id", ""))
		var operator := String(condition_value.get("operator", ">="))
		var raw_value: Variant = condition_value.get("value", null)
		if kind not in VALID_KINDS:
			errors.append("В %s используется неизвестный вид условия: %s" % [context, kind])
		if operator not in VALID_OPERATORS:
			errors.append("В %s используется неизвестный оператор: %s" % [context, operator])
		if kind != "money" and identifier.is_empty():
			errors.append("В %s условие %s не имеет id" % [context, kind])
		if condition_value.has("blocked_reason"):
			_validate_display_text(String(condition_value.get("blocked_reason", "")), "причина блокировки в %s" % context, errors)
		match kind:
			"stat":
				if not GameRules.is_known_characteristic(identifier):
					errors.append("В %s указана неизвестная характеристика: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.CHARACTERISTIC_MIN or float(raw_value) > GameRules.CHARACTERISTIC_MAX:
					errors.append("В %s порог характеристики вне диапазона 1..10" % context)
			"state":
				if not GameRules.is_known_meter(identifier):
					errors.append("В %s указана неизвестная шкала состояния: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.METER_MIN or float(raw_value) > GameRules.METER_MAX:
					errors.append("В %s порог состояния вне диапазона 0..100" % context)
			"money":
				if typeof(raw_value) != TYPE_INT or int(raw_value) < 0 or int(raw_value) > GameRules.MONEY_MAX:
					errors.append("В %s указан неверный денежный порог" % context)
			"item":
				if not _valid_identifier(identifier) or typeof(raw_value) != TYPE_INT or int(raw_value) < GameRules.INVENTORY_QUANTITY_MIN or int(raw_value) > GameRules.INVENTORY_QUANTITY_MAX:
					errors.append("В %s указано неверное условие предмета" % context)
			"polarity":
				if not GameRules.is_stored_polarity(identifier):
					errors.append("В %s указана неизвестная полярность: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.POLARITY_MIN or float(raw_value) > GameRules.POLARITY_MAX:
					errors.append("В %s порог полярности вне допустимого диапазона" % context)
			"skill":
				if not GameRules.is_known_skill(identifier):
					errors.append("В %s указан неизвестный навык: %s" % [context, identifier])
				if typeof(raw_value) != TYPE_INT or int(raw_value) < 1 or int(raw_value) > GameRules.SKILL_MAX_RANK:
					errors.append("В %s указан неверный ранг навыка" % context)
			"knowledge":
				# Zero is not a stored knowledge level, but it is a valid
				# requirement for data that must run only before discovery.
				if not _valid_identifier(identifier) or typeof(raw_value) != TYPE_INT or int(raw_value) < 0 or int(raw_value) > GameRules.KNOWLEDGE_LEVEL_MAX:
					errors.append("В %s указано неверное условие знания" % context)


static func _validate_effects(effects: Array, context: String, errors: Array) -> void:
	const VALID_TYPES := [
		"advance_time", "change_state", "change_money", "add_item", "remove_item",
		"shift_polarity", "unlock_skill", "advance_skill", "mastery", "deferred", "knowledge",
	]
	var total_advance_minutes := 0
	for effect_value in effects:
		if not effect_value is Dictionary:
			errors.append("Эффект в %s должен быть Dictionary" % context)
			continue
		var effect_type := String(effect_value.get("type", ""))
		var identifier := String(effect_value.get("id", ""))
		if effect_type not in VALID_TYPES:
			errors.append("В %s используется неизвестный эффект: %s" % [context, effect_type])
			continue
		match effect_type:
			"advance_time":
				var minutes: Variant = effect_value.get("minutes", null)
				if typeof(minutes) != TYPE_INT or int(minutes) <= 0 or int(minutes) > GameRules.MAX_TIME_ADVANCE_MINUTES:
					errors.append("В %s указано неверное изменение времени" % context)
				else:
					total_advance_minutes += int(minutes)
			"change_state":
				if not GameRules.is_known_meter(identifier) or typeof(effect_value.get("delta", null)) != TYPE_INT:
					errors.append("В %s указано неверное изменение состояния" % context)
			"change_money":
				var money_delta: Variant = effect_value.get("delta", null)
				if typeof(money_delta) != TYPE_INT or absi(int(money_delta)) > GameRules.MONEY_MAX:
					errors.append("В %s указано неверное изменение денег" % context)
			"add_item", "remove_item":
				if not _valid_identifier(identifier) or typeof(effect_value.get("quantity", null)) != TYPE_INT or int(effect_value.get("quantity", 0)) < GameRules.INVENTORY_QUANTITY_MIN or int(effect_value.get("quantity", 0)) > GameRules.INVENTORY_QUANTITY_MAX:
					errors.append("В %s указан неверный предметный эффект" % context)
			"shift_polarity":
				if not GameRules.is_stored_polarity(identifier) or typeof(effect_value.get("delta", null)) != TYPE_INT:
					errors.append("В %s указан неверный сдвиг полярности" % context)
			"unlock_skill":
				if not GameRules.is_known_skill(identifier) or typeof(effect_value.get("rank", null)) != TYPE_INT or int(effect_value.get("rank", 0)) < 1 or int(effect_value.get("rank", 0)) > GameRules.SKILL_MAX_RANK:
					errors.append("В %s указан неверный навык для открытия" % context)
			"advance_skill":
				if not GameRules.is_known_skill(identifier) or typeof(effect_value.get("ranks", null)) != TYPE_INT or int(effect_value.get("ranks", 0)) <= 0:
					errors.append("В %s указано неверное развитие навыка" % context)
			"mastery":
				if typeof(effect_value.get("delta", null)) != TYPE_INT or int(effect_value.get("delta", 0)) <= 0:
					errors.append("В %s указано неверное изменение мастерства" % context)
			"deferred":
				var effect_id := String(effect_value.get("effect_id", ""))
				var delay: Variant = effect_value.get("delay_minutes", null)
				if not _valid_identifier(effect_id):
					errors.append("Отложенный эффект в %s не имеет effect_id" % context)
				if typeof(delay) != TYPE_INT or int(delay) < 0 or int(delay) > GameRules.MAX_TIME_ADVANCE_MINUTES:
					errors.append("Отложенный эффект в %s имеет неверную задержку" % context)
				if not effect_value.get("payload", {}) is Dictionary:
					errors.append("Отложенный эффект в %s должен иметь payload-словарь" % context)
			"knowledge":
				var knowledge_mode := String(effect_value.get("mode", "add"))
				if not _valid_identifier(identifier) or typeof(effect_value.get("amount", null)) != TYPE_INT or int(effect_value.get("amount", 0)) <= 0 or knowledge_mode not in ["add", "advance", "unlock", "set", "remove"]:
					errors.append("В %s указано неверное изменение знания" % context)
	if total_advance_minutes > GameRules.MAX_TIME_ADVANCE_MINUTES:
		errors.append("Пакет эффектов в %s превышает предел изменения времени" % context)


static func _validate_job(job_data: Dictionary, place_map: Dictionary, errors: Array) -> void:
	var job_id := String(job_data.get("id", ""))
	if not _valid_identifier(job_id):
		errors.append("У работы неверный id")
	if not place_map.has(String(job_data.get("location_id", ""))):
		errors.append("Работа находится в неизвестной локации")
	_validate_display_text(String(job_data.get("title", "")), "название работы %s" % job_id, errors)
	_validate_display_text(String(job_data.get("description", "")), "описание работы %s" % job_id, errors)
	_validate_conditions(_array_copy(job_data.get("entry_conditions", [])), "работа %s" % job_id, errors)
	var minigame: Variant = job_data.get("minigame", {})
	if not minigame is Dictionary:
		errors.append("Мини-игра работы должна быть Dictionary")
		return
	var prompts := _array_copy(minigame.get("prompts", []))
	if not _valid_identifier(String(minigame.get("type", ""))):
		errors.append("Мини-игра работы имеет неверный type")
	if int(minigame.get("rounds_to_draw", 0)) != 6:
		errors.append("Смена первого дня должна состоять из 6 раундов")
	if prompts.size() < 6:
		errors.append("Для мини-игры нужно не менее 6 задач")
	var prompt_ids: Dictionary = {}
	var prompt_choice_ids: Dictionary = {}
	var maximum_total_score := 0
	for prompt_value in prompts:
		if not prompt_value is Dictionary:
			errors.append("Задача мини-игры должна быть Dictionary")
			continue
		var prompt_id := String(prompt_value.get("id", ""))
		if not _valid_identifier(prompt_id) or prompt_ids.has(prompt_id):
			errors.append("Некорректный или повторный id задачи: %s" % prompt_id)
		prompt_ids[prompt_id] = true
		_validate_display_text(String(prompt_value.get("text", "")), "текст задачи %s" % prompt_id, errors)
		var prompt_choices := _array_copy(prompt_value.get("choices", []))
		if prompt_choices.is_empty():
			errors.append("Задача %s не имеет вариантов" % prompt_id)
		var has_open_choice := false
		var prompt_max_score := -2_147_483_648
		for prompt_choice in prompt_choices:
			if not prompt_choice is Dictionary:
				errors.append("Вариант задачи %s должен быть Dictionary" % prompt_id)
				continue
			var prompt_choice_id := String(prompt_choice.get("id", ""))
			if not _valid_identifier(prompt_choice_id) or prompt_choice_ids.has(prompt_choice_id):
				errors.append("Некорректный или повторный id ответа мини-игры: %s" % prompt_choice_id)
			prompt_choice_ids[prompt_choice_id] = true
			_validate_display_text(String(prompt_choice.get("label", "")), "ответ мини-игры %s" % prompt_choice_id, errors)
			var conditions := _array_copy(prompt_choice.get("conditions", []))
			if conditions.is_empty():
				has_open_choice = true
			_validate_conditions(conditions, "задача %s" % prompt_id, errors)
			if typeof(prompt_choice.get("score", null)) != TYPE_INT:
				errors.append("Вариант задачи %s должен иметь целый score" % prompt_id)
			else:
				prompt_max_score = maxi(prompt_max_score, int(prompt_choice.get("score", 0)))
		if not has_open_choice:
			errors.append("Задача %s не имеет безусловного варианта" % prompt_id)
		if prompt_max_score == -2_147_483_648:
			errors.append("Задача %s не имеет корректного score" % prompt_id)
		else:
			maximum_total_score += prompt_max_score
	var tiers := _array_copy(job_data.get("result_tiers", []))
	if tiers.is_empty():
		errors.append("Работа не имеет уровней результата")
	for tier_value in tiers:
		if not tier_value is Dictionary:
			errors.append("Уровень результата работы должен быть Dictionary")
			continue
		var tier_id := String(tier_value.get("id", ""))
		if not _valid_identifier(tier_id):
			errors.append("Уровень результата работы имеет неверный id: %s" % tier_id)
		if typeof(tier_value.get("min_score", null)) != TYPE_INT or typeof(tier_value.get("max_score", null)) != TYPE_INT or int(tier_value.get("min_score", 0)) > int(tier_value.get("max_score", 0)):
			errors.append("Уровень результата %s имеет неверный диапазон" % tier_id)
		_validate_display_text(String(tier_value.get("label", "")), "название результата %s" % tier_id, errors)
		var tier_effects := _array_copy(tier_value.get("effects", []))
		_validate_effects(tier_effects, "результат %s" % tier_id, errors)
		_validate_guarded_costs([], tier_effects, "результат %s" % tier_id, errors)
		_validate_effect_packet_runtime(tier_effects, "результат %s" % tier_id, errors)
	for score in range(maximum_total_score + 1):
		var matching_tiers := 0
		for tier_value in tiers:
			if tier_value is Dictionary and score >= int(tier_value.get("min_score", 0)) and score <= int(tier_value.get("max_score", -1)):
				matching_tiers += 1
		if matching_tiers != 1:
			errors.append("Для результата работы %d должно существовать ровно одно итоговое состояние" % score)


static func _validate_start_effects(effects: Array, start_id: String, errors: Array) -> void:
	const RESOURCE_EFFECTS := [
		"change_money", "add_item", "remove_item", "unlock_skill",
		"advance_skill", "mastery", "knowledge",
	]
	for effect_value in effects:
		if effect_value is Dictionary and String(effect_value.get("type", "")) in RESOURCE_EFFECTS:
			errors.append("Старт %s не должен выдавать деньги, предметы, знания или навыки" % start_id)


static func _validate_guarded_costs(
	conditions: Array,
	effects: Array,
	context: String,
	errors: Array
) -> void:
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue
		var effect_type := String(effect_value.get("type", ""))
		if effect_type == "change_money":
			var delta := int(effect_value.get("delta", 0))
			if delta < 0 and not _has_sufficient_guard(conditions, "money", "", -delta):
				errors.append("Расход денег в %s не защищён достаточным условием money" % context)
		elif effect_type == "remove_item":
			var item_id := String(effect_value.get("id", ""))
			var quantity := int(effect_value.get("quantity", 0))
			if not _has_sufficient_guard(conditions, "item", item_id, quantity):
				errors.append("Расход предмета %s в %s не защищён достаточным условием item" % [item_id, context])


static func _has_sufficient_guard(
	conditions: Array,
	kind: String,
	identifier: String,
	required_amount: int
) -> bool:
	for condition_value in conditions:
		if not condition_value is Dictionary:
			continue
		if String(condition_value.get("kind", "")) != kind:
			continue
		if kind != "money" and String(condition_value.get("id", "")) != identifier:
			continue
		var value := int(condition_value.get("value", 0))
		var operator := String(condition_value.get("operator", ">="))
		if operator == ">=" and value >= required_amount:
			return true
		if operator == ">" and value + 1 >= required_amount:
			return true
		if operator == "==" and value >= required_amount:
			return true
	return false


static func _validate_deferred_references(
	effects: Array,
	card_id: String,
	deferred_ids: Dictionary,
	errors: Array
) -> void:
	for effect_value in effects:
		if not effect_value is Dictionary or String(effect_value.get("type", "")) != "deferred":
			continue
		var deferred_id := String(effect_value.get("deferred_id", ""))
		var effect_id := String(effect_value.get("effect_id", ""))
		var source_id := String(effect_value.get("source_id", ""))
		if not _valid_identifier(deferred_id):
			errors.append("Отложенное последствие %s должно иметь стабильный deferred_id" % effect_id)
		elif deferred_ids.has(deferred_id):
			errors.append("Повторный deferred_id: %s" % deferred_id)
		else:
			deferred_ids[deferred_id] = true
		if not _valid_identifier(effect_id):
			errors.append("Некорректный effect_id отложенного последствия в карточке %s" % card_id)
		if source_id != card_id:
			errors.append("Отложенное последствие %s должно ссылаться на исходную карточку %s" % [deferred_id, card_id])


static func _validate_effect_packet_runtime(effects: Array, context: String, errors: Array) -> void:
	var state := RunState.new(GameRules.DEFAULT_CHARACTERISTICS, GameRules.DEFAULT_RNG_SEED)
	var result := ActionTransaction.execute(state, {
		"id": "content_validation",
		"title": "Проверка контента",
		"conditions": [],
		"effects": effects,
	})
	if not result.success:
		errors.append("Пакет эффектов «%s» не исполняется: %s — %s" % [context, String(result.code), result.message])


static func _validate_skill_reachability(cards: Dictionary, job_data: Dictionary, errors: Array) -> void:
	var producers: Dictionary = {}
	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if not choice_value is Dictionary:
				continue
			var conditions := _array_copy(choice_value.get("conditions", []))
			for effect_value in _array_copy(choice_value.get("effects", [])):
				if not effect_value is Dictionary or String(effect_value.get("type", "")) != "unlock_skill":
					continue
				var skill_id := String(effect_value.get("id", ""))
				if _condition_requires_skill(conditions, skill_id):
					continue
				if not producers.has(skill_id):
					producers[skill_id] = []
				producers[skill_id].append(card_id)

	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var consumer_card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if choice_value is Dictionary:
				_validate_skill_conditions_have_producer(
					_array_copy(choice_value.get("conditions", [])),
					consumer_card_id,
					producers,
					errors
				)

	var minigame: Variant = job_data.get("minigame", {})
	if minigame is Dictionary:
		for prompt_value in _array_copy(minigame.get("prompts", [])):
			if not prompt_value is Dictionary:
				continue
			for choice_value in _array_copy(prompt_value.get("choices", [])):
				if choice_value is Dictionary:
					_validate_skill_conditions_have_producer(
						_array_copy(choice_value.get("conditions", [])),
						"@job",
						producers,
						errors
					)


static func _validate_skill_conditions_have_producer(
	conditions: Array,
	consumer_id: String,
	producers: Dictionary,
	errors: Array
) -> void:
	for condition_value in conditions:
		if not condition_value is Dictionary or String(condition_value.get("kind", "")) != "skill":
			continue
		var skill_id := String(condition_value.get("id", ""))
		var producer_cards := _array_copy(producers.get(skill_id, []))
		var reachable := false
		for producer_id in producer_cards:
			if consumer_id == "@job" or String(producer_id) != consumer_id:
				reachable = true
				break
		if not reachable:
			errors.append("Навык %s требуется в %s, но его нельзя освоить заранее в первом дне" % [skill_id, consumer_id])


static func _condition_requires_skill(conditions: Array, skill_id: String) -> bool:
	for condition_value in conditions:
		if condition_value is Dictionary and String(condition_value.get("kind", "")) == "skill" and String(condition_value.get("id", "")) == skill_id:
			return true
	return false


static func _validate_unlockable_references(cards: Dictionary, shelter_map: Dictionary, errors: Array) -> void:
	var item_producers: Dictionary = {}
	var knowledge_producers: Dictionary = {}
	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if not choice_value is Dictionary:
				continue
			for effect_value in _array_copy(choice_value.get("effects", [])):
				if not effect_value is Dictionary:
					continue
				var effect_type := String(effect_value.get("type", ""))
				var identifier := String(effect_value.get("id", ""))
				if effect_type == "add_item":
					_append_producer(item_producers, identifier, card_id)
				elif effect_type == "knowledge" and String(effect_value.get("mode", "add")) in ["add", "advance", "unlock", "set"] and int(effect_value.get("amount", 0)) > 0:
					_append_producer(knowledge_producers, identifier, card_id)

	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if choice_value is Dictionary:
				_validate_unlockable_conditions(
					_array_copy(choice_value.get("conditions", [])),
					card_id,
					item_producers,
					knowledge_producers,
					errors
				)
	for shelter_value in shelter_map.values():
		if shelter_value is Dictionary:
			_validate_unlockable_conditions(
				_array_copy(shelter_value.get("conditions", [])),
				"@shelter",
				item_producers,
				knowledge_producers,
				errors
			)


static func _validate_unlockable_conditions(
	conditions: Array,
	consumer_id: String,
	item_producers: Dictionary,
	knowledge_producers: Dictionary,
	errors: Array
) -> void:
	for condition_value in conditions:
		if not condition_value is Dictionary:
			continue
		var kind := String(condition_value.get("kind", ""))
		if kind not in ["item", "knowledge"]:
			continue
		var identifier := String(condition_value.get("id", ""))
		var producer_map := item_producers if kind == "item" else knowledge_producers
		var producer_cards := _array_copy(producer_map.get(identifier, []))
		var reachable := false
		for producer_id in producer_cards:
			if consumer_id.begins_with("@") or String(producer_id) != consumer_id:
				reachable = true
				break
		if not reachable:
			errors.append("Требование %s:%s в %s нельзя получить заранее в первом дне" % [kind, identifier, consumer_id])


static func _append_producer(producers: Dictionary, identifier: String, card_id: String) -> void:
	if not producers.has(identifier):
		producers[identifier] = []
	if card_id not in producers[identifier]:
		producers[identifier].append(card_id)


static func _validate_start_reachability(
	starts: Array,
	job_data: Dictionary,
	shelter_map: Dictionary,
	place_map: Dictionary,
	errors: Array
) -> void:
	var open_shelter_locations: Array = []
	for shelter_value in shelter_map.values():
		if shelter_value is Dictionary and _array_copy(shelter_value.get("conditions", [])).is_empty():
			open_shelter_locations.append(String(shelter_value.get("location_id", "")))
	var job_location := String(job_data.get("location_id", ""))
	var job_conditions := _array_copy(job_data.get("entry_conditions", []))
	for start_value in starts:
		if not start_value is Dictionary:
			continue
		var start_id := String(start_value.get("id", ""))
		var start_location := String(start_value.get("location_id", ""))
		var reachable := _reachable_locations(start_location, place_map)
		if not reachable.has(job_location):
			errors.append("Из старта %s географически недоступна работа" % start_id)
		var shelter_reachable := false
		for shelter_location in open_shelter_locations:
			if reachable.has(String(shelter_location)):
				shelter_reachable = true
				break
		if not shelter_reachable:
			errors.append("Из старта %s недоступен безусловный ночлег" % start_id)
		var state := RunState.new(GameRules.DEFAULT_CHARACTERISTICS, GameRules.DEFAULT_RNG_SEED)
		var start_result := ActionTransaction.execute(state, {
			"id": "validate_start_reachability",
			"title": "Проверка старта",
			"conditions": [],
			"effects": _array_copy(start_value.get("initial_effects", [])),
		})
		if not start_result.success:
			continue
		var job_check := CheckResolver.evaluate_all(state, job_conditions)
		if not bool(job_check.get("allowed", false)):
			errors.append("После старта %s базовые условия работы недостижимы без восстановления" % start_id)


static func _reachable_locations(origin_id: String, place_map: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array = [origin_id]
	while not queue.is_empty():
		var current_id := String(queue.pop_front())
		if visited.has(current_id) or not place_map.has(current_id):
			continue
		visited[current_id] = true
		for route_value in _array_copy(place_map[current_id].get("routes", [])):
			if route_value is Dictionary:
				var destination_id := String(route_value.get("destination_id", ""))
				if not visited.has(destination_id):
					queue.append(destination_id)
	return visited


static func _validate_display_text(value: String, context: String, errors: Array) -> void:
	var text := value.strip_edges()
	if text.is_empty():
		errors.append("Пустой пользовательский текст: %s" % context)
		return
	var has_cyrillic := false
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if (code >= 0x0410 and code <= 0x044f) or code == 0x0401 or code == 0x0451:
			has_cyrillic = true
		if code == 0xfffd or (code < 32 and code not in [9, 10, 13]):
			errors.append("Повреждённый пользовательский текст: %s" % context)
			return
	if not has_cyrillic:
		errors.append("Пользовательский текст должен быть на русском: %s" % context)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _count_deferred(effects: Array) -> int:
	var result := 0
	for effect_value in effects:
		if effect_value is Dictionary and String(effect_value.get("type", "")) == "deferred":
			result += 1
	return result


static func _valid_identifier(value: String, allow_dot: bool = false) -> bool:
	if value.is_empty():
		return false
	var first_code := value.unicode_at(0)
	if first_code < 97 or first_code > 122:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_lower_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := code == 95
		var is_dot := allow_dot and code == 46
		if not (is_lower_letter or is_digit or is_underscore or is_dot):
			return false
	return true
