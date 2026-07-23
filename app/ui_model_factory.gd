class_name UiModelFactory
extends RefCounted

const MONTHS := [
	"января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря",
]
const STATUS_TITLES := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"morale": "Мораль",
}
const STATUS_DETAILS := {
	"health": "Общее физическое состояние. Травмы и болезни закрывают тяжёлые действия.",
	"hunger": "Потребность в еде. Чем больше значение, тем сильнее голод.",
	"energy": "Запас сил для работы, дороги и других нагрузок.",
	"tension": "Накопившийся стресс. Чем больше значение, тем труднее сохранять контроль.",
	"morale": "Желание продолжать и способность видеть доступные возможности.",
}
const CHANGE_TITLES := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"morale": "Мораль",
	"money": "Деньги",
	"calendar": "Время",
	"city_navigation": "Ориентирование в городе",
	"cargo_handling": "Работа с грузом",
	"cooking": "Готовка",
	"repair": "Ремонт",
	"first_aid": "Первая помощь",
	"trade": "Торговля",
	"physical_specialization": "Физическая специализация",
	"execution_style": "Способ выполнения",
	"influence_style": "Способ влияния",
	"relationship_investment": "Отношения",
	"attention_distribution": "Распределение внимания",
	"knowledge_profile": "Профиль знаний",
	"uncertainty_behavior": "Поведение в неизвестности",
	"decision_priority": "Приоритет решений",
}


static func location(
	shell_model: Dictionary,
	reduced_motion: bool,
	font_scale: float = 1.0,
	psyche_effect_mode: String = "full",
	last_transaction: Dictionary = {},
	animate_status_delta: bool = true
) -> Dictionary:
	var location_model: Dictionary = Dictionary(shell_model.get("location", {})).duplicate(true)
	var status: Dictionary = Dictionary(shell_model.get("status", {})).duplicate(true)
	var meters: Dictionary = Dictionary(status.get("meters", {})).duplicate(true)
	var calendar: Dictionary = Dictionary(status.get("calendar", location_model.get("calendar", {}))).duplicate(true)
	var actions: Array = []
	for raw_action in Array(location_model.get("actions", [])):
		if raw_action is Dictionary:
			actions.append(_location_action(Dictionary(raw_action)))
	return {
		"header": {
			"district_title": "Приречный район",
			"location_title": String(location_model.get("title", "Неизвестное место")),
			"date_text": format_date(calendar, font_scale >= 1.5),
			"time_text": format_time(calendar),
			"money": int(status.get("money", 0)),
			"show_settings": true,
		},
		"description": String(location_model.get("description", "Осмотритесь и выберите занятие.")),
		"context_tags": Array(location_model.get("tags", [])).duplicate(true),
		"background_key": String(location_model.get("background_key", "")),
		"statuses": _statuses(meters, status_deltas(last_transaction), animate_status_delta),
		"actions": actions,
		"psyche_intensity": effective_psyche_intensity(shell_model, psyche_effect_mode),
		"reduced_motion": reduced_motion,
	}


static func event(raw_model: Dictionary) -> Dictionary:
	var options: Array = []
	for raw_option in Array(raw_model.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var locked := bool(option.get("locked", false))
		options.append({
			"id": String(option.get("id", "")),
			"title": String(option.get("text", "Продолжить")),
			"enabled": not locked,
			"locked_reason": reason_text(option.get("reasons", [])),
			"variant": "normal" if locked else "accent",
		})
	return {
		"eyebrow": "НАЧАЛО" if String(raw_model.get("kind", "")) == "start" else "СИТУАЦИЯ",
		"title": String(raw_model.get("title", "Событие")),
		"context": String(raw_model.get("location_title", "Город")),
		"body": String(raw_model.get("text", "")),
		"section_title": "Как поступить",
		"options": options,
	}


static func job(raw_model: Dictionary) -> Dictionary:
	var options: Array = []
	for raw_choice in Array(raw_model.get("choices", [])):
		if not raw_choice is Dictionary:
			continue
		var choice: Dictionary = raw_choice
		var locked := bool(choice.get("locked", false))
		options.append({
			"id": String(choice.get("id", "")),
			"title": String(choice.get("label", "Действовать")),
			"enabled": not locked,
			"locked_reason": reason_text(choice.get("reasons", [])),
			"variant": "normal" if locked else "accent",
		})
	var round := int(raw_model.get("round", 1))
	var total := int(raw_model.get("rounds_total", 6))
	return {
		"eyebrow": "РАБОЧАЯ МИНИ-ИГРА",
		"title": String(raw_model.get("job_title", "Рабочая смена")),
		"context": "Счёт: %d" % int(raw_model.get("score", 0)),
		"body": String(raw_model.get("text", "Выберите действие")),
		"section_title": "Ваше решение",
		"progress": {
			"label": "Раунд %d из %d" % [round, total],
			"value": round - 1,
			"maximum": total,
		},
		"options": options,
	}


static func shelters(raw_shelters: Array) -> Dictionary:
	var options: Array = []
	for raw_shelter in raw_shelters:
		if not raw_shelter is Dictionary:
			continue
		var shelter: Dictionary = raw_shelter
		var locked := bool(shelter.get("locked", false))
		options.append({
			"id": String(shelter.get("id", "")),
			"title": String(shelter.get("title", "Ночлег")),
			"description": String(shelter.get("description", "")),
			"meta": [
				"Качество: %d/5" % int(shelter.get("quality", 0)),
				"Риск: %d/5" % int(shelter.get("risk", 0)),
			],
			"enabled": not locked,
			"locked_reason": reason_text(shelter.get("reasons", [])),
			"variant": "normal" if locked else "accent",
		})
	return {
		"eyebrow": "ЗАВЕРШЕНИЕ ДНЯ",
		"title": "Где переночевать",
		"body": "Сравните безопасность и качество отдыха. Выбор переведёт время к следующему утру.",
		"section_title": "Доступные места",
		"options": options,
	}


static func job_result(raw_model: Dictionary) -> Dictionary:
	var result: Dictionary = Dictionary(raw_model.get("result", {})).duplicate(true)
	return {
		"eyebrow": "СМЕНА ЗАВЕРШЕНА",
		"title": String(result.get("label", "Работа окончена")),
		"body": "Итоговый счёт: %d" % int(result.get("score", raw_model.get("score", 0))),
		"facts": transaction_facts(raw_model.get("transaction", {})),
		"confirm_text": "Вернуться к месту",
	}


static func summary(raw_model: Dictionary) -> Dictionary:
	var biography: Dictionary = {}
	var entries: Array = raw_model.get("biography", [])
	if not entries.is_empty() and entries.back() is Dictionary:
		biography = Dictionary(entries.back()).duplicate(true)
	var facts: Array = []
	var final_state: Dictionary = Dictionary(biography.get("final_state", {})).duplicate(true)
	if not final_state.is_empty():
		facts.append("Деньги к утру: %d ₽" % int(final_state.get("money", 0)))
		var meters: Dictionary = Dictionary(final_state.get("meters", {})).duplicate(true)
		for status_id in ["health", "hunger", "energy", "tension", "morale"]:
			facts.append("%s: %d/100" % [STATUS_TITLES[status_id], int(meters.get(status_id, 0))])
	return {
		"eyebrow": "ЛИЧНАЯ ХРОНИКА",
		"title": "Первый день прожит",
		"body": String(biography.get("summary", "Герой пережил свой первый день в городе.")),
		"facts": facts,
		"confirm_text": "В главное меню",
	}


static func format_date(stamp: Dictionary, compact: bool = false) -> String:
	var month := clampi(int(stamp.get("month", 1)), 1, 12)
	if compact:
		return "%02d.%02d.%d" % [int(stamp.get("day", 1)), month, int(stamp.get("year", 1970))]
	return "%d %s %d" % [int(stamp.get("day", 1)), MONTHS[month - 1], int(stamp.get("year", 1970))]


static func format_time(stamp: Dictionary) -> String:
	var minute_of_day := clampi(int(stamp.get("minute_of_day", 0)), 0, 1439)
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


static func psyche_intensity(shell_model: Dictionary) -> float:
	var meters: Dictionary = Dictionary(Dictionary(shell_model.get("status", {})).get("meters", {}))
	var tension := float(meters.get("tension", 0)) / 100.0
	var low_morale := 1.0 - float(meters.get("morale", 100)) / 100.0
	return clampf(tension * 0.55 + low_morale * 0.45, 0.0, 1.0)


static func effective_psyche_intensity(shell_model: Dictionary, mode: String) -> float:
	var intensity := psyche_intensity(shell_model)
	match mode:
		"off":
			return 0.0
		"reduced":
			return intensity * 0.45
		_:
			return intensity


static func reason_text(raw_reasons: Variant) -> String:
	if raw_reasons is String:
		return String(raw_reasons)
	var messages := PackedStringArray()
	if raw_reasons is Array:
		for raw_reason in raw_reasons:
			if raw_reason is Dictionary:
				var message := String(raw_reason.get("message", raw_reason.get("code", "Недоступно")))
				if not message.is_empty():
					messages.append(message)
	return "\n".join(messages)


static func transaction_facts(raw_transaction: Variant) -> Array:
	var facts: Array = []
	if not raw_transaction is Dictionary:
		return facts
	for raw_change in Array(raw_transaction.get("changes", [])):
		if not raw_change is Dictionary:
			continue
		var change: Dictionary = raw_change
		var target_id := String(change.get("target_id", ""))
		var title := String(CHANGE_TITLES.get(target_id, target_id.replace("_", " ").capitalize()))
		var effect_type := String(change.get("effect_type", ""))
		if effect_type == "advance_time":
			facts.append("Время: +%d мин" % int(change.get("delta", 0)))
		elif change.has("delta") and change.get("delta") is int:
			var delta := int(change.get("delta", 0))
			var suffix := " ₽" if effect_type == "change_money" else ""
			facts.append("%s: %s%d%s" % [title, "+" if delta > 0 else "", delta, suffix])
		elif change.has("after"):
			facts.append("%s: %s" % [title, str(change.get("after"))])
	return facts


static func status_deltas(raw_transaction: Variant) -> Dictionary:
	var deltas: Dictionary = {}
	if not raw_transaction is Dictionary:
		return deltas
	for raw_change in Array(raw_transaction.get("changes", [])):
		if not raw_change is Dictionary:
			continue
		var change: Dictionary = raw_change
		var target_id := String(change.get("target_id", ""))
		if target_id not in STATUS_TITLES or not change.has("delta"):
			continue
		var raw_delta: Variant = change.get("delta")
		if raw_delta is int or raw_delta is float:
			deltas[target_id] = int(deltas.get(target_id, 0)) + int(round(float(raw_delta)))
	return deltas


static func _statuses(
	meters: Dictionary,
	deltas: Dictionary = {},
	animate_status_delta: bool = true
) -> Array:
	var result: Array = []
	for status_id in ["health", "hunger", "energy", "tension", "morale"]:
		var value := int(meters.get(status_id, 0))
		result.append({
			"id": status_id,
			"title": STATUS_TITLES[status_id],
			"value": value,
			"maximum": 100,
			"delta": int(deltas.get(status_id, 0)),
			"animate_delta": animate_status_delta,
			"detail": STATUS_DETAILS[status_id],
			"forecast": _status_forecast(status_id, value),
		})
	return result


static func _status_forecast(status_id: String, value: int) -> String:
	if status_id in ["hunger", "tension"]:
		return "Опасный уровень — ищите способ восстановиться." if value >= 75 else "Пока состояние управляемо."
	return "Опасный уровень — часть действий скоро закроется." if value <= 25 else "Пока состояние позволяет действовать свободно."


static func _location_action(raw: Dictionary) -> Dictionary:
	var kind := String(raw.get("kind", "event"))
	var completed := bool(raw.get("completed", false))
	var enabled := bool(raw.get("available", true)) and not completed
	var title := String(raw.get("title", "Действие"))
	if completed:
		title += " · завершено"
	var description := String(raw.get("description", ""))
	if description.is_empty():
		match kind:
			"event":
				description = "Осмотреть место и разобраться в ситуации."
			"local":
				description = "Заняться делом в текущем месте."
			"job":
				description = "Короткая рабочая смена с отдельной мини-игрой."
			"wait":
				description = "Осознанно пропустить часть дня."
			"shelter":
				description = "Сравнить доступные варианты ночлега."
	var meta: Array = Array(raw.get("meta", [])).duplicate(true)
	if int(raw.get("minutes", 0)) > 0:
		meta.append("%d мин" % int(raw.get("minutes", 0)))
	if int(raw.get("price", 0)) > 0:
		meta.append("%d ₽" % int(raw.get("price", 0)))
	if int(raw.get("risk", 0)) > 0:
		meta.append("Риск %d/5" % clampi(int(raw.get("risk", 0)), 1, 5))
	return {
		"id": String(raw.get("id", "")),
		"kind": kind,
		"title": title,
		"description": description,
		"meta": meta,
		"enabled": enabled,
		"locked_reason": "Уже завершено" if completed else reason_text(raw.get("reasons", [])),
		"variant": "accent" if kind in ["local", "job", "shelter"] and enabled else "normal",
	}
