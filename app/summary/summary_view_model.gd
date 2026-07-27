class_name SummaryViewModel
extends RefCounted

const CurrencyTextScript := preload("res://app/presentation/currency_text.gd")

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


static func build(raw_model: Dictionary) -> Dictionary:
	var lifecycle: Dictionary = Dictionary(raw_model.get("lifecycle", {}))
	var lifecycle_status := String(lifecycle.get("status", ""))
	if lifecycle_status in ["dead", "week_complete"]:
		return _lifecycle_summary(raw_model, lifecycle_status)
	return _legacy_day_summary(raw_model)


static func _lifecycle_summary(raw_model: Dictionary, lifecycle_status: String) -> Dictionary:
	var status: Dictionary = Dictionary(raw_model.get("status", {}))
	var calendar: Dictionary = Dictionary(status.get("calendar", {}))
	var is_dead := lifecycle_status == "dead"
	return {
		"eyebrow": "ПОПЫТКА ЗАВЕРШЕНА" if is_dead else "ЛИЧНАЯ ХРОНИКА",
		"title": "История оборвалась" if is_dead else "Первая неделя прожита",
		"body": (
			"Организм не выдержал лишений. Следующая попытка начнётся с другим сочетанием решений."
			if is_dead
			else "Семь свободных дней сложились в первую главу жизни героя."
		),
		"facts": [
			"Дата: %s" % _format_date(calendar),
			"Деньги: %s" % CurrencyTextScript.compact(int(status.get("money", 0))),
		],
		"confirm_text": "В главное меню",
	}


static func _legacy_day_summary(raw_model: Dictionary) -> Dictionary:
	var biography: Dictionary = {}
	var entries: Array = raw_model.get("biography", [])
	if not entries.is_empty() and entries.back() is Dictionary:
		biography = Dictionary(entries.back()).duplicate(true)
	var facts: Array = []
	var final_state: Dictionary = Dictionary(biography.get("final_state", {}))
	if not final_state.is_empty():
		facts.append("Деньги к утру: %s" % CurrencyTextScript.compact(
			int(final_state.get("money", 0))
		))
		var meters: Dictionary = Dictionary(final_state.get("meters", {}))
		for status_id: String in ["health", "hunger", "energy", "tension", "mental_state"]:
			facts.append("%s: %d/100" % [
				STATUS_TITLES[status_id],
				int(meters.get(status_id, 0)),
			])
	return {
		"eyebrow": "ЛИЧНАЯ ХРОНИКА",
		"title": "Первый день прожит",
		"body": String(biography.get("summary", "Герой пережил свой первый день в городе.")),
		"facts": facts,
		"confirm_text": "В главное меню",
	}


static func _format_date(stamp: Dictionary) -> String:
	var month := clampi(int(stamp.get("month", 1)), 1, 12)
	return "%d %s %d" % [
		int(stamp.get("day", 1)),
		MONTHS[month - 1],
		int(stamp.get("year", 1980)),
	]
