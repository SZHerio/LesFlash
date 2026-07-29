extends SceneTree

## Balance probe for stage 7, run as its own pass.
##
## Two questions were written down first. Are the years visible at all over a
## game year, and is getting older simply worse — because if it is, the best
## move in a game about a life is to stop living it early.
##
## It also reports what lifting the seven-day ceiling did to two things that
## were stuck against it.

const Aging = preload("res://game/aging/aging_rules.gd")
const SurvivalStateScript = preload("res://game/survival/survival_state.gd")
const BusinessCatalog = preload("res://game/business/business_catalog.gd")
const HousingCatalog = preload("res://game/housing/housing_catalog.gd")

## What a day of ordinary work drains before the years touch it.
const BASE_ENERGY_UNITS_PER_MINUTE := 2
const WORKING_MINUTES_PER_DAY := 6 * 60


func _init() -> void:
	print("AGING BALANCE PROBE")
	@warning_ignore("integer_division")
	var horizon_days := SurvivalStateScript.new().horizon_minutes / 1440
	print("  горизонт забега: %d дней (было 7)" % horizon_days)

	print("  --")
	for raw_band: Variant in Aging.BANDS:
		var band: Dictionary = raw_band
		var drain := int(round(
			float(BASE_ENERGY_UNITS_PER_MINUTE * WORKING_MINUTES_PER_DAY)
			* 10_000.0 / float(band["stamina_basis_points"])
		))
		var base := BASE_ENERGY_UNITS_PER_MINUTE * WORKING_MINUTES_PER_DAY
		print("  %-10s с %2d лет: рабочий день стоит %+d%% сил, вес слова %+d — %s" % [
			String(band["title"]),
			int(band["age_from"]),
			(drain - base) * 100 / maxi(base, 1),
			int(band["regard"]),
			String(band["note"]),
		])

	print("  --")
	print("  что снятие потолка вернуло:")
	var business := BusinessCatalog.load_default()
	if bool(business.get("ok", false)):
		var bench := BusinessCatalog.find(Dictionary(business["catalog"]), "business_repair_bench")
		var reckoning := BusinessCatalog.reckon(bench, 999, int(bench.get("max_hands", 0)), 1)
		var net := int(reckoning["revenue"]) - int(reckoning["costs"]) - int(reckoning["units"]) * int(bench.get("stock_price_ard", 0))
		if net > 0:
			var payback := int(bench.get("price_ard", 0)) / net
			print("    верстак окупается за %d дней — теперь внутри забега" % payback)
	var housing := HousingCatalog.load_default()
	if bool(housing.get("ok", false)):
		for raw_room: Variant in Array(Dictionary(housing["catalog"]).get("rooms", [])):
			var room: Dictionary = raw_room
			var times := horizon_days / maxi(int(room["rent_every_days"]), 1)
			print("    %s: срок наступит %d раз за забег (было не больше одного)" % [
				String(room["title"]), times,
			])
	print("AGING BALANCE PROBE WRITTEN")
	quit(0)
