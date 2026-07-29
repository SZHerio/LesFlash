extends SceneTree

## Balance probe for housing and obligations, run as its own pass.
##
## Two questions were written down before it was built. Can he actually meet
## what he takes on, and is sleeping rough simply the better play — because if
## the street always wins, every room in the game is decoration.

const Housing = preload("res://game/housing/housing_catalog.gd")
const ShelterCatalog = preload("res://game/shelter/shelter_catalog.gd")
const JobCatalog = preload("res://game/jobs/job_shift_catalog.gd")
const Ladder = preload("res://game/jobs/job_ladder.gd")


func _init() -> void:
	var loaded := Housing.load_default()
	if not bool(loaded.get("ok", false)):
		print("HOUSING BALANCE PROBE: каталог не грузится — %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var casual := _sorter_pay()
	var master := casual * Ladder.pay_basis_points(Ladder.MASTER) / 10_000

	print("HOUSING BALANCE PROBE")
	print("  день подённого %d ард, день мастера %d" % [casual, master])
	print("  за ночь в платном номере: %d" % Housing.NIGHTLY_ROOM_PRICE)
	for raw_room: Variant in Array(Dictionary(loaded["catalog"]).get("rooms", [])):
		var room: Dictionary = raw_room
		var days := int(room["rent_every_days"])
		@warning_ignore("integer_division")
		var nightly := int(room["rent_ard"]) / days
		var share := int(room["rent_ard"]) * 100 / maxi(casual * days, 1)
		print("  %-24s вперёд %3d, %3d за %d дн. = %2d за ночь; %d%% дохода подённого" % [
			String(room["title"]),
			int(room["deposit_ard"]) + int(room["rent_ard"]),
			int(room["rent_ard"]),
			days,
			nightly,
			share,
		])

	print("  --")
	print("  чем платит улица:")
	var shelters := ShelterCatalog.load_default()
	if bool(shelters.get("ok", false)):
		for raw_option: Variant in Array(Dictionary(shelters.get("catalog", {})).get("options", [])):
			var option: Dictionary = raw_option
			var effects: Dictionary = Dictionary(option.get("meter_effects", {}))
			var parts: Array[String] = []
			for meter_id: String in effects:
				parts.append("%s %+d" % [meter_id, int(effects[meter_id])])
			print("    %-30s %s ард — %s" % [
				String(option.get("shelter_id", "")),
				str(option.get("price_arden", 0)),
				", ".join(parts) if not parts.is_empty() else "без последствий",
			])
	print("HOUSING BALANCE PROBE WRITTEN")
	quit(0)


func _sorter_pay() -> int:
	var loaded := JobCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return 0
	for raw_job: Variant in Array(Dictionary(loaded["catalog"]).get("jobs", [])):
		if String(Dictionary(raw_job).get("id", "")) == "job_recycling_sorter":
			return int(Dictionary(raw_job).get("base_payout_ard", 0))
	return 0
