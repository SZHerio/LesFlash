extends SceneTree

## Balance probe for the professional arc, run as its own pass.
##
## The ladder can be provably reachable and still not be worth climbing. This
## measures what each rung costs in shifts and what it returns in wages, and
## prints both, so "is the top worth the road" is answered with numbers rather
## than with confidence.

const Ladder = preload("res://game/jobs/job_ladder.gd")
const JobCatalog = preload("res://game/jobs/job_shift_catalog.gd")
const QualificationCatalog = preload("res://game/content/catalogs/qualification_catalog.gd")

const JOB := "job_recycling_sorter"


func _init() -> void:
	var base := _base_pay()
	var fee := _certificate_fee()
	print("LADDER BALANCE PROBE")
	print("  смена сортировщика стоит %d ард, свидетельство — %d ард" % [base, fee])
	var previous_shifts := 0
	var previous_pay := base
	var previous_paper := ""
	for grade_id: String in Ladder.ORDER:
		var grade: Dictionary = Ladder.GRADES[grade_id]
		var pay := base * Ladder.pay_basis_points(grade_id) / 10_000
		var shifts := int(grade["shifts"])
		var extra := pay - previous_pay
		var line := "  %-10s с %2d смены: %3d ард за смену" % [
			String(grade["title"]), shifts, pay,
		]
		if extra > 0:
			line += "  (+%d к смене" % extra
			# The paper is only paid for once, at the rung that first asks for
			# it. Repeating the payback at every rung above would read as if it
			# were bought again.
			if String(grade["qualification_id"]) != previous_paper and not String(grade["qualification_id"]).is_empty():
				line += ", бумага окупается за %d смены" % int(ceil(float(fee) / float(extra)))
			line += ")"
		print(line)
		previous_shifts = shifts
		previous_pay = pay
		previous_paper = String(grade["qualification_id"])
	var top := base * Ladder.pay_basis_points(Ladder.MASTER) / 10_000
	print("  --")
	print("  путь до верха: %d смен, разница с подённым: +%d ард за смену (+%d%%)" % [
		int(Dictionary(Ladder.GRADES[Ladder.MASTER])["shifts"]),
		top - base,
		(top - base) * 100 / maxi(base, 1),
	])
	print("LADDER BALANCE PROBE WRITTEN")
	quit(0)


func _base_pay() -> int:
	var loaded := JobCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return 0
	for raw_job: Variant in Array(Dictionary(loaded["catalog"]).get("jobs", [])):
		if String(Dictionary(raw_job).get("id", "")) == JOB:
			return int(Dictionary(raw_job).get("base_payout_ard", 0))
	return 0


func _certificate_fee() -> int:
	var loaded := QualificationCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return 0
	var entry := QualificationCatalog.find(Dictionary(loaded["catalog"]), "qual_repair_certificate")
	return int(entry.get("fee_ard", 0))
