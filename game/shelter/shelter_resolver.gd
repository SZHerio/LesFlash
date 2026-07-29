class_name ShelterResolver
extends RefCounted

## Pure availability and wake-time resolver.
##
## Input is a detached calendar snapshot and scalar actor context. The resolver
## never consumes RNG and never writes to the catalog, calendar or session.

const Catalog := preload("res://game/shelter/shelter_catalog.gd")
const Validator := preload("res://game/shelter/shelter_catalog_validator.gd")
const CalendarScript := preload("res://core/time/game_calendar.gd")

## How much of the night the place itself leaves to the weather. A paid room
## shields completely, so equipment changes nothing there; a niche under the
## underpass shields nothing, which is where a coat is worth its price.
const EXPOSURE_BY_CATEGORY := {
	"street": 100,
	"night_shelter": 40,
	"paid_room": 0,
}
const SHIELDED_ENERGY_BONUS := 12
## What a fully exposed night in the harshest month takes out of a person before
## anything he is wearing gives it back. Worn warmth still shields it.
const COLD_BITE := 9


static func resolve_for_location(catalog: Dictionary, context: Dictionary) -> Dictionary:
	var prepared := _prepare(catalog, context)
	if not bool(prepared.get("ok", false)):
		return prepared
	var result: Array[Dictionary] = []
	for option: Dictionary in Catalog.options_for_location(catalog, String(context["location_id"])):
		result.append(_resolve_definition(option, context, prepared["calendar"]))
	return {
		"ok": true,
		"code": "ok",
		"options": result,
		"catalog_version": int(catalog["catalog_version"]),
	}


static func resolve_one(catalog: Dictionary, shelter_id: String, context: Dictionary) -> Dictionary:
	var prepared := _prepare(catalog, context)
	if not bool(prepared.get("ok", false)):
		return prepared
	var definition := Catalog.find_option(catalog, shelter_id)
	if definition.is_empty():
		return _failure("unknown_shelter", "Такого варианта ночлега нет.")
	return {
		"ok": true,
		"code": "ok",
		"option": _resolve_definition(definition, context, prepared["calendar"]),
		"catalog_version": int(catalog["catalog_version"]),
	}


static func _prepare(catalog: Dictionary, context: Dictionary) -> Dictionary:
	var catalog_validation := Validator.validate(catalog)
	if not bool(catalog_validation.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_catalog",
			"error": "Каталог ночлега повреждён.",
			"errors": Array(catalog_validation.get("errors", [])).duplicate(),
		}
	var context_errors: Array[String] = []
	var location_id: Variant = context.get("location_id", null)
	if typeof(location_id) != TYPE_STRING or String(location_id).strip_edges().is_empty():
		context_errors.append("Не указано текущее место героя.")
	var money: Variant = context.get("money", null)
	if typeof(money) != TYPE_INT or int(money) < 0 or int(money) > GameRules.MONEY_MAX:
		context_errors.append("Количество арденов задано неверно.")
	var calendar_value: Variant = context.get("calendar", null)
	var calendar: GameCalendar = null
	if calendar_value is Dictionary:
		calendar = CalendarScript.from_dict(calendar_value)
	if calendar == null:
		context_errors.append("Снимок игрового календаря задан неверно.")
	if not context_errors.is_empty():
		return {
			"ok": false,
			"code": "invalid_context",
			"error": "Нельзя рассчитать ночлег по текущим данным.",
			"errors": context_errors,
		}
	return {"ok": true, "calendar": calendar}


static func _resolve_definition(
	definition: Dictionary,
	context: Dictionary,
	calendar: GameCalendar
) -> Dictionary:
	var current_stamp := calendar.current_stamp()
	var current_minute := int(current_stamp["minute_of_day"])
	var price := int(definition["price_arden"])
	# A bed he already rents is not bought again tonight.
	if String(definition.get("shelter_id", "")) in Array(context.get("rent_paid_shelter_ids", [])):
		price = 0
	var reasons: Array[Dictionary] = []
	if String(context["location_id"]) not in Array(definition["location_ids"]):
		reasons.append({
			"code": "wrong_location",
			"message": "Этот ночлег находится в другом месте.",
		})
	if not _inside_check_in_window(current_minute, Array(definition["check_in_windows"])):
		reasons.append({
			"code": "outside_check_in_window",
			"message": "Сейчас сюда нельзя устроиться на ночлег.",
		})
	var shortfall := maxi(price - int(context["money"]), 0)
	if shortfall > 0:
		reasons.append({
			"code": "not_enough_money",
			"message": "Не хватает %s." % _arden_text(shortfall),
			"shortfall_arden": shortfall,
		})
	var duration := _minutes_until_wake(
		current_minute,
		int(definition["wake_minute"]),
		int(definition["minimum_sleep_minutes"]),
		calendar.minutes_per_day
	)
	var wake_at := calendar.future_stamp(duration)
	var result := definition.duplicate(true)
	# What the night actually costs him, which is nothing on a bed he rents.
	result["price_arden"] = price
	# What the place leaves to the weather, and what the weather does with it. A
	# paid room is exposed to nothing, so February costs it nothing; the niche
	# under the avenue is exposed to everything, which is where the difference
	# between a bed and a corner stops being about comfort.
	var exposure := int(EXPOSURE_BY_CATEGORY.get(String(definition.get("category_id", "street")), 100))
	var season := String(context.get("season", Season.SUMMER))
	var weather := Season.cold_basis_points(season)
	var shielded := clampi(mini(int(context.get("warmth", 0)), exposure), 0, 100)
	result["exposure"] = exposure
	result["warmth"] = clampi(int(context.get("warmth", 0)), 0, 100)
	result["shielded"] = shielded
	result["season"] = season
	result["meter_effects"] = _shielded_meter_effects(
		_weathered_meter_effects(Dictionary(definition.get("meter_effects", {})), exposure, weather),
		shielded
	)
	result["available"] = reasons.is_empty()
	result["blocked_reasons"] = reasons
	result["duration_minutes"] = duration
	result["wake_at"] = wake_at
	result["wake_time_text"] = _minute_text(int(definition["wake_minute"]))
	result["crosses_date"] = _date_changed(current_stamp, wake_at)
	result["currency_code"] = "ARD"
	return result


## The season reaches only the part of the night the place left uncovered. Under
## a roof the month does not matter; in the open it is most of what matters.
static func _weathered_meter_effects(
	authored: Dictionary,
	exposure: int,
	weather_basis_points: int
) -> Dictionary:
	var result := authored.duplicate(true)
	if exposure <= 0 or weather_basis_points == 10_000:
		return result
	# How much of the weather actually lands, given how open the place is.
	var extra := (weather_basis_points - 10_000) * clampi(exposure, 0, 100) / 100
	var factor := 10_000 + extra

	# Cold does not merely make an unpleasant night worse — it makes a tolerable
	# one cost something. Scaling alone left the free municipal room untouched all
	# winter, because nothing harmful was written into it, and a January that can
	# be walked away from is not a January.
	var bite := extra * COLD_BITE / 10_000
	if bite > 0:
		result["health"] = int(result.get("health", 0)) - bite
		result["tension"] = int(result.get("tension", 0)) + bite

	for meter_id: String in ["health", "mental_state"]:
		var value := int(result.get(meter_id, 0))
		if value < 0:
			result[meter_id] = -maxi(-value * factor / 10_000, 1)
	var tension := int(result.get("tension", 0))
	if tension > 0:
		result["tension"] = maxi(tension * factor / 10_000, 1)
	# A cold night gives back less rest than a mild one, even for the same hours.
	var energy := int(result.get("energy", 0))
	if energy > 0:
		result["energy"] = maxi(energy * 10_000 / factor, 1)
	return result


## Worn warmth does not invent a better bed; it only takes back the part of the
## night the place left to the cold, and adds the rest a person sleeps through.
static func _shielded_meter_effects(authored: Dictionary, shielded: int) -> Dictionary:
	var result := authored.duplicate(true)
	if shielded <= 0:
		return result
	for meter_id: String in ["health", "mental_state"]:
		var value := int(result.get(meter_id, 0))
		if value < 0:
			result[meter_id] = -_scaled_down(-value, shielded)
	var tension := int(result.get("tension", 0))
	if tension > 0:
		result["tension"] = _scaled_down(tension, shielded)
	if result.has("energy") and int(result["energy"]) > 0:
		@warning_ignore("integer_division")
		var bonus: int = SHIELDED_ENERGY_BONUS * shielded / 100
		result["energy"] = int(result["energy"]) + bonus
	return result


static func _scaled_down(value: int, shielded: int) -> int:
	@warning_ignore("integer_division")
	var remaining: int = value * (100 - shielded) / 100
	return remaining


static func _inside_check_in_window(minute: int, windows: Array) -> bool:
	for raw_window: Variant in windows:
		var window: Dictionary = raw_window
		var opens := int(window["opens_minute"])
		var closes := int(window["closes_minute"])
		if opens < closes and minute >= opens and minute < closes:
			return true
		if opens > closes and (minute >= opens or minute < closes):
			return true
	return false


static func _minutes_until_wake(
	current_minute: int,
	wake_minute: int,
	minimum_sleep_minutes: int,
	minutes_per_day: int
) -> int:
	var duration := wake_minute - current_minute
	if duration <= 0:
		duration += minutes_per_day
	while duration < minimum_sleep_minutes:
		duration += minutes_per_day
	return duration


static func _date_changed(before: Dictionary, after: Dictionary) -> bool:
	return (
		int(before.get("year", 0)) != int(after.get("year", 0))
		or int(before.get("month", 0)) != int(after.get("month", 0))
		or int(before.get("day", 0)) != int(after.get("day", 0))
	)


static func _minute_text(minute: int) -> String:
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minute / 60, minute % 60]


static func _arden_text(amount: int) -> String:
	var last_two := amount % 100
	var last := amount % 10
	if last_two >= 11 and last_two <= 14:
		return "%d арденов" % amount
	if last == 1:
		return "%d арден" % amount
	if last >= 2 and last <= 4:
		return "%d ардена" % amount
	return "%d арденов" % amount


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "errors": [message]}
