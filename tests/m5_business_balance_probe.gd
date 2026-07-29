extends SceneTree

## Balance probe for the bench, run as its own pass after the mechanics.
##
## Two questions were written down before any of it was built, and this answers
## both with numbers: can the place ruin a man, and can it become an income that
## makes working and making things pointless.

const Catalog = preload("res://game/business/business_catalog.gd")
const Ladder = preload("res://game/jobs/job_ladder.gd")
const JobCatalog = preload("res://game/jobs/job_shift_catalog.gd")

const BENCH := "business_repair_bench"


func _init() -> void:
	var loaded := Catalog.load_default()
	if not bool(loaded.get("ok", false)):
		print("BUSINESS BALANCE PROBE: каталог не грузится — %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var entry := Catalog.find(Dictionary(loaded["catalog"]), BENCH)
	var price := int(entry.get("price_ard", 0))
	var margin := int(entry.get("revenue_per_unit_ard", 0)) - int(entry.get("stock_price_ard", 0))

	print("BUSINESS BALANCE PROBE")
	print("  %s: покупка %d ард, маржа с единицы %d" % [String(entry.get("title", "")), price, margin])
	for hands: int in range(0, int(entry.get("max_hands", 0)) + 1):
		var working := Catalog.reckon(entry, 999, hands, 1)
		var idle := Catalog.reckon(entry, 0, hands, 1)
		var materials := int(working["units"]) * int(entry.get("stock_price_ard", 0))
		var net := int(working["revenue"]) - int(working["costs"]) - materials
		print("  %d рук: рабочий день %+d, простой %+d, материала в день %d" % [
			hands, net, int(idle["net"]), materials,
		])

	var best_hands := int(entry.get("max_hands", 0))
	var best := Catalog.reckon(entry, 999, best_hands, 1)
	var best_net := int(best["revenue"]) - int(best["costs"]) - int(best["units"]) * int(entry.get("stock_price_ard", 0))
	print("  --")
	if best_net > 0:
		print("  окупаемость покупки при полном штате: %d дней" % (price / best_net))
	# The comparison that decides whether it eats the rest of the game: a day at
	# the bench against a day of the best work a man can get.
	var shift := _sorter_pay() * Ladder.pay_basis_points(Ladder.MASTER) / 10_000
	print("  день мастера на площадке: %d ард против %d у верстака" % [shift, best_net])
	if best_net >= shift:
		print("  ВНИМАНИЕ: верстак платит не меньше лучшей работы — работа обесценена")
	print("BUSINESS BALANCE PROBE WRITTEN")
	quit(0)


func _sorter_pay() -> int:
	var loaded := JobCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return 0
	for raw_job: Variant in Array(Dictionary(loaded["catalog"]).get("jobs", [])):
		if String(Dictionary(raw_job).get("id", "")) == "job_recycling_sorter":
			return int(Dictionary(raw_job).get("base_payout_ard", 0))
	return 0
