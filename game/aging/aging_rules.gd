class_name AgingRules
extends RefCounted

## What years do to a man, and what they give him back.
##
## The requirement was written down before any of this: ageing must not be pure
## decline. A game where every birthday is a loss teaches the player to end runs
## early, and a game about a life cannot be one where the best move is to stop
## living it.
##
## So a band takes something the body does and gives something the body cannot:
## the young are strong and nobody listens to them; the old are slow and are
## taken at their word. Both are true of the street, and both are playable.
##
## Nothing here is stored. A band is read from the hero's age the same way a job
## grade is read from his record — derive it, and it can never drift.

## age_from is inclusive; the last band runs to the end of a life.
const BANDS := [
	{
		"id": "young",
		"age_from": 0,
		"title": "молодой",
		## Multiplies what the body can do, in basis points.
		"stamina_basis_points": 11_000,
		## Added to how much a day of hard work takes out of him.
		"exertion_extra": -1,
		## What people concede to him without being asked. Standing, in the sense
		## the yard and the counters use.
		"regard": 0,
		"note": "Сил больше, чем понимания, куда их деть.",
	},
	{
		"id": "settled",
		"age_from": 30,
		"title": "в силах",
		"stamina_basis_points": 10_000,
		"exertion_extra": 0,
		"regard": 1,
		"note": "Уже знают в лицо, ещё берут на любую работу.",
	},
	{
		"id": "greying",
		"age_from": 45,
		"title": "в летах",
		"stamina_basis_points": 9_000,
		"exertion_extra": 1,
		"regard": 2,
		"note": "Тяжёлое даётся хуже, слово весит больше.",
	},
	{
		"id": "old",
		"age_from": 60,
		"title": "старый",
		"stamina_basis_points": 7_500,
		"exertion_extra": 2,
		"regard": 3,
		"note": "На разгрузку не ставят, но и не гонят ниоткуда.",
	},
]


static func band_for(age_years: int) -> Dictionary:
	var found: Dictionary = BANDS[0]
	for raw_band: Variant in BANDS:
		var band: Dictionary = raw_band
		if age_years >= int(band["age_from"]):
			found = band
	return found.duplicate(true)


static func band_of(run_state: RunState) -> Dictionary:
	if run_state == null:
		return band_for(0)
	return band_for(int(run_state.get_age_years()))


## How much of a day's exertion the body actually absorbs, in basis points. A
## young man spends less on the same shift than an old one.
static func stamina_basis_points(run_state: RunState) -> int:
	return int(band_of(run_state).get("stamina_basis_points", 10_000))


## What the years have earned him with people, over and above anything he has
## done. Never negative: age does not cost a man respect on this street.
static func regard(run_state: RunState) -> int:
	return maxi(int(band_of(run_state).get("regard", 0)), 0)


## Whether the ledger balances at every band — something taken, something given.
## A band that only takes is the failure this whole design is meant to avoid,
## and it should be impossible to author rather than merely unlikely.
static func validate() -> Dictionary:
	var errors: Array[String] = []
	var previous_age := -1
	var previous_stamina := 0
	var previous_regard := -1
	for index: int in BANDS.size():
		var band: Dictionary = BANDS[index]
		var path := "aging.%s" % String(band.get("id", index))
		if int(band["age_from"]) <= previous_age:
			errors.append("%s: полосы возраста должны идти по возрастанию" % path)
		if String(band.get("title", "")).strip_edges().is_empty():
			errors.append("%s: нет названия" % path)
		if String(band.get("note", "")).strip_edges().is_empty():
			errors.append("%s: нечего сказать о возрасте" % path)
		if index > 0:
			# Each band after the first must trade: less body, more standing.
			if int(band["stamina_basis_points"]) >= previous_stamina:
				errors.append("%s: тело не слабеет — полоса ничего не берёт" % path)
			if int(band["regard"]) <= previous_regard:
				errors.append("%s: годы ничего не дают взамен" % path)
		previous_age = int(band["age_from"])
		previous_stamina = int(band["stamina_basis_points"])
		previous_regard = int(band["regard"])
	return {"ok": errors.is_empty(), "errors": errors}
