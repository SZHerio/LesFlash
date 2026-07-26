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

## An axis reads as a phrase, never as a number. «Мощь 35» asks the player a
## question it does not answer — is 35 a lot? — so each axis carries nine
## phrases and the value only picks one.
##
## Every phrase keeps the root of the pole it belongs to («мощный» for Мощь,
## «выносливый» for Выносливость). Events name the pole directly, as in
## `[Мощь ≥ 35] поднять люк одному`, and the player has to be able to connect
## what an option demands with what the screen says about him. The far ends
## drop the root for an idiom, because at the edge the lean is the whole
## description and a plain adjective would understate it.
##
## Titles are questions about the person rather than the domain names in
## ROADMAP §5.2: «Поведение в неизвестности» describes the axis to a designer,
## «В новом месте» describes it to a player.
const BAND_MAX := [-76, -51, -26, -6, 5, 25, 50, 75]

const POLARITIES := {
	"physical_specialization": {
		"title": "Что может тело",
		"bands": [
			"Небывалая мощь", "Очень мощный", "Мощный", "Чуть мощнее",
			"Поровну",
			"Чуть выносливее", "Выносливый", "Очень выносливый", "Двужильный",
		],
	},
	"execution_style": {
		"title": "Как берётся за дело",
		"bands": [
			"Всё бегом", "Очень быстрый темп", "Быстрый темп", "Чуть быстрее",
			"Как придётся",
			"Чуть внимательнее", "Держит контроль", "Строгий контроль", "Семь раз отмерит",
		],
	},
	"influence_style": {
		"title": "Как добивается своего",
		"bands": [
			"Берёт горлом", "Сильно давит", "Давит", "Чуть напористее",
			"По-разному",
			"Чуть спокойнее", "Есть авторитет", "Крепкий авторитет", "Слово весит",
		],
	},
	"attention_distribution": {
		"title": "Куда смотрит",
		"bands": [
			"Не видит вокруг", "Уходит с головой", "Сосредоточен", "Чуть собраннее",
			"Поровну",
			"Чуть шире обзор", "Широкий обзор", "Замечает всё", "Глаза на затылке",
		],
	},
	"uncertainty_behavior": {
		"title": "В новом месте",
		"bands": [
			"Вечная разведка", "Тянет в новое", "Ходит в разведку", "Чуть любопытнее",
			"По настроению",
			"Чуть оседлее", "Осваивает место", "Обжил район", "Врос в район",
		],
	},
	"decision_priority": {
		"title": "Когда есть риск",
		"bands": [
			"Лезет на рожон", "Хватает любой шанс", "Идёт на риск", "Чуть смелее",
			"По обстоятельствам",
			"Чуть осторожнее", "Ищет безопасное", "Не рискует", "Дует на воду",
		],
	},
}
const PROFILES := {
	"relationship_investment": {
		"title": "Круг общения",
		"bands": [
			"Со всеми накоротке", "Широкий охват", "Много знакомых", "Круг чуть шире",
			"Поровну",
			"Круг чуть ближе", "Немного, но близко", "Несколько своих", "Держится за своих",
		],
	},
	"knowledge_profile": {
		"title": "Что знает",
		"bands": [
			"Одно дело назубок", "Узкая специализация", "Знает своё дело", "Чуть уже",
			"Поровну",
			"Чуть шире", "Знает понемногу", "Широкая эрудиция", "Обо всём слышал",
		],
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
	return String(Array(copy["bands"])[band_index(value)])


## The neutral band is deliberately narrow. A run starts with every axis at 0,
## and a hero who has done nothing yet must not already be described as leaning.
static func band_index(value: int) -> int:
	var clamped := clampi(value, GameRules.POLARITY_MIN, GameRules.POLARITY_MAX)
	for index: int in BAND_MAX.size():
		if clamped <= int(BAND_MAX[index]):
			return index
	return BAND_MAX.size()


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
