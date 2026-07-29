class_name BusinessCatalog
extends RefCounted

## What can be owned, what it costs to keep, and what a day at it is worth.
##
## One entry so far, and deliberately so: a bench of one's own has to be worth
## having before a second kind of place means anything. Everything here is
## per-day, because the place is reckoned by the day whether the hero comes or
## not.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "business_catalog_v1"
const DEFAULT_PATH := "res://game/business/data/business_catalog_v1.json"

## Most people one bench can hold. Past this they are in each other's way, which
## is a truth about workshops and also stops hiring from being a money printer.
const MAX_HANDS := 3


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var entries := Rules.index_entries(
		catalog.get("businesses", null), "businesses", "business_", errors
	)
	for business_id: String in entries:
		var entry: Dictionary = entries[business_id]
		var path := "businesses.%s" % business_id
		for field: String in ["title", "description"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		if String(entry.get("location_id", "")) not in CityPlaces.PLACES:
			errors.append("%s.location_id неизвестен" % path)
		Rules.validate_int_range(entry.get("price_ard", null), 100, 20_000, "%s.price_ard" % path, errors)
		Rules.validate_int_range(entry.get("rent_per_day_ard", null), 1, 500, "%s.rent_per_day_ard" % path, errors)
		Rules.validate_int_range(entry.get("wage_per_day_ard", null), 1, 500, "%s.wage_per_day_ard" % path, errors)
		Rules.validate_int_range(entry.get("stock_price_ard", null), 1, 500, "%s.stock_price_ard" % path, errors)
		Rules.validate_int_range(entry.get("revenue_per_unit_ard", null), 1, 1_000, "%s.revenue_per_unit_ard" % path, errors)
		Rules.validate_int_range(entry.get("units_per_hand_per_day", null), 1, 20, "%s.units_per_hand_per_day" % path, errors)
		Rules.validate_int_range(entry.get("max_hands", null), 1, MAX_HANDS, "%s.max_hands" % path, errors)
		_validate_it_can_pay_and_can_fail(entry, path, errors)
	return {"ok": errors.is_empty(), "errors": errors}


## Two ways a business entry can be nonsense, and both have to be refused.
##
## If a unit of work earns no more than the material it consumes, the place can
## never pay for itself and owning it is a punishment. If rent and wages can
## never exceed the takings, it can never fail, and a venture that cannot fail
## is not a venture — it is an allowance that makes work and craft pointless.
static func _validate_it_can_pay_and_can_fail(
	entry: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var margin := int(entry.get("revenue_per_unit_ard", 0)) - int(entry.get("stock_price_ard", 0))
	if margin <= 0:
		errors.append("%s: единица работы не окупает материал" % path)
		return
	var best_day := margin * int(entry.get("units_per_hand_per_day", 0)) * (int(entry.get("max_hands", 0)) + 1)
	var worst_day := int(entry.get("rent_per_day_ard", 0)) + int(entry.get("wage_per_day_ard", 0)) * int(entry.get("max_hands", 0))
	if worst_day <= 0:
		errors.append("%s: содержание не стоит ничего, разориться невозможно" % path)
	if best_day <= worst_day:
		errors.append("%s: полный день не покрывает содержания даже в лучшем случае" % path)


static func find(catalog: Dictionary, business_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("businesses", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == business_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


static func at_location(catalog: Dictionary, location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry: Variant in Array(catalog.get("businesses", [])):
		if raw_entry is Dictionary and String(Dictionary(raw_entry).get("location_id", "")) == location_id:
			result.append(Dictionary(raw_entry).duplicate(true))
	return result


## What the place did over a stretch of days without anyone watching.
##
## The hero counts as a pair of hands only on the days he was there, and the
## runner does not track that, so he does not count at all: a bench left to
## itself works at the speed of the people paid to be there. That is the honest
## reading of "it works without him" — it works, but not as well.
static func reckon(entry: Dictionary, stock: int, hands: int, days: int) -> Dictionary:
	if entry.is_empty() or days <= 0:
		return {"days": 0, "units": 0, "revenue": 0, "costs": 0, "net": 0, "stock_left": stock, "idle_days": 0}
	var per_day := int(entry.get("units_per_hand_per_day", 0)) * maxi(hands, 0)
	var units := 0
	var idle := 0
	var left := stock
	for _day: int in days:
		var made := mini(per_day, left)
		if made <= 0:
			idle += 1
		units += made
		left -= made
	var revenue := units * int(entry.get("revenue_per_unit_ard", 0))
	var costs := days * (
		int(entry.get("rent_per_day_ard", 0))
		+ int(entry.get("wage_per_day_ard", 0)) * maxi(hands, 0)
	)
	return {
		"days": days,
		"units": units,
		"revenue": revenue,
		"costs": costs,
		"net": revenue - costs,
		"stock_left": left,
		"idle_days": idle,
	}
