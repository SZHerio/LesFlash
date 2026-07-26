class_name HeroViewModel
extends RefCounted

## Read model for the hero screen: everything the run knows about this person,
## in one place.
##
## Two steps, like the inventory. `raw()` pulls plain numbers out of RunState
## and nothing else; `build()` adds the Russian wording and the shared header.
## Neither touches the save or the RNG.
##
## Nothing the hero has not earned appears here. A skill with no rank and an
## unlearned topic are absent rather than greyed out, because a disabled row
## still announces that a mechanic exists.

const UiModels := preload("res://app/ui_model_factory.gd")
const PsycheScaleScript := preload("res://core/state/psyche_scale.gd")

const CHARACTERISTICS := {
	"strength": "Сила",
	"charisma": "Харизма",
	"intelligence": "Интеллект",
	"luck": "Удача",
}

## Negative values read as the strength of the left pole: −35 on the first axis
## is shown as «Мощь 35». The centre has its own wording, because standing in
## the middle is a state, not an absence of one.
const POLARITIES := {
	"physical_specialization": {
		"title": "Физическая специализация",
		"left": "Мощь", "right": "Выносливость", "centre": "Смешанная подготовка",
	},
	"execution_style": {
		"title": "Способ выполнения",
		"left": "Темп", "right": "Контроль", "centre": "Обычный ритм",
	},
	"influence_style": {
		"title": "Способ влияния",
		"left": "Давление", "right": "Авторитет", "centre": "Равноправный торг",
	},
	"attention_distribution": {
		"title": "Распределение внимания",
		"left": "Сосредоточение", "right": "Обзор", "centre": "Смешанный режим",
	},
	"uncertainty_behavior": {
		"title": "Поведение в неизвестности",
		"left": "Разведка", "right": "Освоение", "centre": "Чередование подходов",
	},
	"decision_priority": {
		"title": "Приоритет решения",
		"left": "Возможность", "right": "Безопасность", "centre": "Расчёт",
	},
}
const PROFILES := {
	"relationship_investment": {
		"title": "Вложение в отношения",
		"left": "Охват", "right": "Глубина", "centre": "Баланс",
	},
	"knowledge_profile": {
		"title": "Профиль знаний",
		"left": "Специализация", "right": "Эрудиция", "centre": "Баланс",
	},
}
const SKILLS := {
	"city_navigation": "Ориентирование по городу",
	"cargo_handling": "Работа с грузом",
	"cooking": "Приготовление пищи",
	"repair": "Ремонт",
	"first_aid": "Первая помощь",
	"trade": "Торговля",
	"search": "Поиск",
}
const SKILL_RANKS := ["не открыт", "основы", "уверенное владение", "мастерство"]


## Plain state, no wording. The adapter owns RunState; the presenter never sees
## it.
static func raw(run_state: RunState) -> Dictionary:
	if run_state == null:
		return {}
	var characteristics: Dictionary = {}
	for key: String in CHARACTERISTICS:
		characteristics[key] = run_state.get_characteristic(key)
	var skills: Dictionary = {}
	for key: String in SKILLS:
		var rank := run_state.get_skill_rank(key)
		if rank > 0:
			skills[key] = rank
	var knowledge: Array = run_state.knowledge.keys()
	knowledge.sort()
	return {
		"psyche_value": int(run_state.meters.get("morale", 0)),
		"age_years": run_state.get_age_years(),
		"characteristics": characteristics,
		"stored_polarities": run_state.stored_polarities.duplicate(true),
		"computed_profiles": run_state.computed_profiles.duplicate(true),
		"skills": skills,
		"knowledge": knowledge,
		"mastery_points": run_state.mastery_points,
	}


static func build(
	raw_model: Dictionary,
	shell_model: Dictionary,
	reduced_motion: bool,
	font_scale: float
) -> Dictionary:
	var status: Dictionary = Dictionary(shell_model.get("status", {}))
	var calendar: Dictionary = Dictionary(status.get("calendar", {}))
	return {
		"header": {
			"district_title": "ПРИРЕЧНЫЙ РАЙОН",
			"location_title": "Герой",
			"date_text": UiModels.format_date(calendar, font_scale >= 1.5),
			"time_text": UiModels.format_time(calendar),
			"money": int(status.get("money", 0)),
			"show_settings": true,
		},
		"psyche": {
			"step": PsycheScaleScript.title_for(int(raw_model.get("psyche_value", 0))),
		},
		"age_text": _age_text(int(raw_model.get("age_years", 0))),
		"characteristics": _characteristics(Dictionary(raw_model.get("characteristics", {}))),
		"polarities": _axes(Dictionary(raw_model.get("stored_polarities", {}))),
		"profiles": _profiles(Dictionary(raw_model.get("computed_profiles", {}))),
		"skills": _skills(Dictionary(raw_model.get("skills", {}))),
		"knowledge": Array(raw_model.get("knowledge", [])).duplicate(),
		"reduced_motion": reduced_motion,
	}


## 41 год, 42 года, 45 лет — Russian counts the last digit, except in the teens.
static func _age_text(years: int) -> String:
	var last := years % 10
	var teens := years % 100
	if teens >= 11 and teens <= 14:
		return "%d лет" % years
	if last == 1:
		return "%d год" % years
	if last >= 2 and last <= 4:
		return "%d года" % years
	return "%d лет" % years


static func _characteristics(values: Dictionary) -> Array:
	var result: Array = []
	for key: String in CHARACTERISTICS:
		result.append({
			"id": key,
			"title": String(CHARACTERISTICS[key]),
			"value": int(values.get(key, 1)),
		})
	return result


static func _axes(stored: Dictionary) -> Array:
	var result: Array = []
	for key: String in POLARITIES:
		var copy: Dictionary = POLARITIES[key]
		var value := int(stored.get(key, 0))
		result.append({
			"id": key,
			"title": String(copy["title"]),
			"value": value,
			"formed": true,
			"reading": _reading(value, copy, true),
		})
	return result


## A computed profile shows nothing until there is enough behind it: an empty
## address book is not a perfectly balanced circle of friends.
static func _profiles(computed: Dictionary) -> Array:
	var result: Array = []
	for key: String in PROFILES:
		var copy: Dictionary = PROFILES[key]
		var source: Variant = computed.get(key, {})
		var profile: Dictionary = source if source is Dictionary else {}
		var value := int(profile.get("value", 0))
		var formed := int(profile.get("evidence", 0)) >= GameRules.PROFILE_FORMATION_EVIDENCE
		result.append({
			"id": key,
			"title": String(copy["title"]),
			"value": value if formed else 0,
			"formed": formed,
			"reading": _reading(value, copy, formed),
		})
	return result


static func _reading(value: int, copy: Dictionary, formed: bool) -> String:
	if not formed:
		return "не сформирован"
	if value == 0:
		return String(copy["centre"])
	if value < 0:
		return "%s %d" % [String(copy["left"]), absi(value)]
	return "%s %d" % [String(copy["right"]), value]


static func _skills(ranks: Dictionary) -> Array:
	var result: Array = []
	for key: String in SKILLS:
		var rank := int(ranks.get(key, 0))
		if rank <= 0:
			continue
		result.append({
			"id": key,
			"title": String(SKILLS[key]),
			"rank": rank,
			"rank_title": String(SKILL_RANKS[clampi(rank, 0, SKILL_RANKS.size() - 1)]),
		})
	return result
