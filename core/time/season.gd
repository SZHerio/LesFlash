class_name Season
extends RefCounted

## Time of year, and what it does to a night outdoors.
##
## Derived from the month, never stored — the same way an age band comes from an
## age and a work grade from a record. A save written before seasons existed
## reads its season from the date it already has, and needs no migration.
##
## The whole point is that the difference between the street and a room stops
## being a matter of comfort. A summer night under the pipes is survivable and a
## January one is not, and every coat, blanket and hundred ard spent on a bed
## becomes a decision rather than a habit.

const WINTER := "winter"
const SPRING := "spring"
const SUMMER := "summer"
const AUTUMN := "autumn"

const ORDER := [WINTER, SPRING, SUMMER, AUTUMN]

## `cold_basis_points` multiplies what a night exposed to the weather takes out
## of a person. A place that shelters him completely feels none of it — that is
## what makes the room worth its price in February and not in July.
const SEASONS := {
	WINTER: {
		"months": [12, 1, 2],
		"title": "зима",
		"cold_basis_points": 20_000,
		"note": "Ночь длинная, и от труб греет только вплотную.",
	},
	SPRING: {
		"months": [3, 4, 5],
		"title": "весна",
		"cold_basis_points": 10_500,
		"note": "Днём отпускает, к утру всё ещё берёт своё.",
	},
	SUMMER: {
		"months": [6, 7, 8],
		"title": "лето",
		"cold_basis_points": 6_000,
		"note": "Можно спать где придётся, и все это знают.",
	},
	AUTUMN: {
		"months": [9, 10, 11],
		"title": "осень",
		# Забег начинается в сентябре. Осень, которая убивает сама по себе, делает
		# смертельным вступление, а зубы у года должны быть зимой — приёмочный
		# гейт поймал это на четвёртом дне переоткрытого сохранения.
		"cold_basis_points": 11_500,
		"note": "Сыро. Промокшее не высыхает до следующего дня.",
	},
}


static func of_month(month: int) -> String:
	for season_id: String in ORDER:
		if month in Array(Dictionary(SEASONS[season_id])["months"]):
			return season_id
	return SUMMER


static func of_calendar(calendar: GameCalendar) -> String:
	return SUMMER if calendar == null else of_month(int(calendar.month))


static func title_of(season_id: String) -> String:
	return String(Dictionary(SEASONS.get(season_id, {})).get("title", ""))


static func note_of(season_id: String) -> String:
	return String(Dictionary(SEASONS.get(season_id, {})).get("note", ""))


## How much harder the weather makes an exposed night, in basis points. Ten
## thousand would be neutral; nothing here is, because there is no month in this
## city when sleeping outside is free.
static func cold_basis_points(season_id: String) -> int:
	return int(Dictionary(SEASONS.get(season_id, {})).get("cold_basis_points", 10_000))


static func is_cold(season_id: String) -> bool:
	return cold_basis_points(season_id) > 10_000


## Whether the year is described completely and gets worse than it gets better.
## A season list with a gap would silently hand some month the wrong weather, and
## one where nothing is harsh makes every coat in the game pointless.
static func validate() -> Dictionary:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for season_id: String in ORDER:
		var season: Dictionary = SEASONS[season_id]
		if String(season.get("title", "")).strip_edges().is_empty():
			errors.append("%s: нет названия" % season_id)
		if String(season.get("note", "")).strip_edges().is_empty():
			errors.append("%s: нечего сказать о времени года" % season_id)
		for raw_month: Variant in Array(season.get("months", [])):
			var month := int(raw_month)
			if month < 1 or month > 12:
				errors.append("%s: месяц %d вне года" % [season_id, month])
				continue
			if seen.has(month):
				errors.append("месяц %d принадлежит двум временам года" % month)
			seen[month] = true
	for month: int in range(1, 13):
		if not seen.has(month):
			errors.append("месяц %d не принадлежит ни одному времени года" % month)
	var harshest := 0
	for season_id: String in ORDER:
		harshest = maxi(harshest, cold_basis_points(season_id))
	if harshest <= 10_000:
		errors.append("ни одно время года не тяжелее прочих — снаряжение теряет смысл")
	return {"ok": errors.is_empty(), "errors": errors}
