class_name UiModelFactory
extends RefCounted

const CurrencyTextScript := preload("res://app/presentation/currency_text.gd")
const LocationActionCatalogScript := preload("res://game/location/location_action_catalog.gd")
const PsycheScaleScript := preload("res://core/state/psyche_scale.gd")
const SummaryViewModelScript := preload("res://app/summary/summary_view_model.gd")

const MONTHS := [
	"января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря",
]
const STATUS_TITLES := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"mental_state": "Психика",
}
const STATUS_DETAILS := {
	"health": "Общее физическое состояние. Травмы и болезни закрывают тяжёлые действия.",
	"hunger": "Потребность в еде. Чем больше значение, тем сильнее голод.",
	"energy": "Запас сил для работы, дороги и других нагрузок.",
	"tension": "Накопившийся стресс. Чем больше значение, тем труднее сохранять контроль.",
	"mental_state": "Устойчивое психическое состояние, которое меняется медленнее текущего напряжения.",
}
const CHANGE_TITLES := {
	"health": "Здоровье",
	"hunger": "Голод",
	"energy": "Энергия",
	"tension": "Напряжение",
	"mental_state": "Психика",
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
const CATEGORY_BY_ACTION_KIND := {
	"event": "observe",
	"local": "observe",
	"search": "search",
	"job": "work",
	"wait": "rest",
	"shelter": "shelter",
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
		var category_id := String(option.get("category_id", "observe"))
		options.append({
			"id": String(option.get("id", "")),
			"category_id": category_id,
			"category_icon_id": _resolved_category_icon(option, category_id),
			"title": String(option.get("text", "Продолжить")),
			"meta_tokens": _typed_meta_tokens(option.get("meta_tokens", [])),
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
		var category_id := String(choice.get("category_id", "work"))
		options.append({
			"id": String(choice.get("id", "")),
			"category_id": category_id,
			"category_icon_id": _resolved_category_icon(choice, category_id, &"action_work"),
			"title": String(choice.get("label", "Действовать")),
			"meta_tokens": _typed_meta_tokens(choice.get("meta_tokens", [])),
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
		var quality_text := "Качество: %d/5" % int(shelter.get("quality", 0))
		var risk_text := "Риск: %d/5" % int(shelter.get("risk", 0))
		options.append({
			"id": String(shelter.get("id", "")),
			"category_id": "shelter",
			"category_icon_id": &"action_shelter",
			"title": String(shelter.get("title", "Ночлег")),
			"description": String(shelter.get("description", "")),
			"meta_tokens": [
				{"icon_id": &"", "text": quality_text, "accessible_text": quality_text},
				{"icon_id": &"meta_risk", "text": risk_text, "accessible_text": risk_text},
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
		"leave_text": "Вернуться к месту",
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
	return SummaryViewModelScript.build(raw_model)


static func format_date(stamp: Dictionary, compact: bool = false) -> String:
	var month := clampi(int(stamp.get("month", 1)), 1, 12)
	if compact:
		return "%02d.%02d.%d" % [int(stamp.get("day", 1)), month, int(stamp.get("year", 1980))]
	return "%d %s %d" % [int(stamp.get("day", 1)), MONTHS[month - 1], int(stamp.get("year", 1980))]


static func format_time(stamp: Dictionary) -> String:
	var minute_of_day := clampi(int(stamp.get("minute_of_day", 0)), 0, 1439)
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


static func psyche_intensity(shell_model: Dictionary) -> float:
	var meters: Dictionary = Dictionary(Dictionary(shell_model.get("status", {})).get("meters", {}))
	return PsycheScaleScript.filter_for(int(meters.get("mental_state", 50)))


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
			if effect_type == "change_money":
				facts.append("%s: %s" % [title, CurrencyTextScript.signed_compact(delta)])
			else:
				facts.append("%s: %s%d" % [title, "+" if delta > 0 else "", delta])
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
	for status_id in ["health", "hunger", "energy", "tension", "mental_state"]:
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
			"search":
				description = "Обойти зону и решить, что здесь стоит забрать."
	var category_id := String(raw.get("category_id", "")).strip_edges()
	if category_id.is_empty():
		category_id = String(CATEGORY_BY_ACTION_KIND.get(kind, "observe"))
	return {
		"id": String(raw.get("id", "")),
		"kind": kind,
		"category_id": category_id,
		"category_icon_id": _resolved_category_icon(raw, category_id),
		"title": title,
		"description": description,
		"meta_tokens": _typed_meta_tokens(raw.get("meta_tokens", [])),
		"meta": Array(raw.get("meta", [])).duplicate(true),
		"intent": Dictionary(raw.get("intent", {})).duplicate(true),
		"confirmation_required": bool(raw.get("confirmation_required", false)),
		"enabled": enabled,
		"locked_reason": "Уже завершено" if completed else reason_text(raw.get("reasons", [])),
		"variant": "accent" if kind in ["local", "job", "shelter", "search"] and enabled else "normal",
	}


static func _typed_meta_tokens(raw_tokens: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_tokens is Array:
		return result
	for raw_token: Variant in raw_tokens:
		if not raw_token is Dictionary or String(raw_token.get("text", "")).strip_edges().is_empty():
			continue
		result.append(Dictionary(raw_token).duplicate(true))
	return result


static func _resolved_category_icon(
	raw: Dictionary,
	category_id: String,
	fallback: StringName = &"action_observe"
) -> StringName:
	var explicit := String(raw.get("category_icon_id", "")).strip_edges()
	if not explicit.is_empty():
		return StringName(explicit)
	var mapped := LocationActionCatalogScript.category_icon_id(category_id)
	return fallback if mapped.is_empty() else mapped
