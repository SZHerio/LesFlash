class_name CityPlaces
extends RefCounted

## Every place in the city, and which district it belongs to — in one list.
##
## This existed in six copies, one per content catalog, all identical and all
## needing the same edit whenever a place was added. Six lists that must agree is
## five chances to forget, and the failure mode is a catalog that silently
## refuses to load because it does not recognise a place the map already shows.
##
## Districts are separate here because a district is a thing the hero may not
## know about yet. Riverside is where a run starts; the other two are reached by
## transport and do not appear on the map until he has heard of them.

const RIVERSIDE := "riverside_central"
const ZAVOKZALNY := "zavokzalny"
const SOBORNAYA := "sobornaya"

## district_id -> what the player must know before it appears on the map. The
## home district is known by standing in it.
const DISTRICT_KNOWLEDGE := {
	RIVERSIDE: "",
	ZAVOKZALNY: "district_zavokzalny",
	SOBORNAYA: "district_sobornaya",
}

const DISTRICT_TITLES := {
	RIVERSIDE: "Приречный район",
	ZAVOKZALNY: "Завокзальный",
	SOBORNAYA: "Соборная сторона",
}

## place_id -> district_id. Order matters only for readability.
const PLACES := {
	"underpass": RIVERSIDE,
	"market": RIVERSIDE,
	"station_square": RIVERSIDE,
	"recycling_point": RIVERSIDE,
	"clinic_yard": RIVERSIDE,
	"embankment": RIVERSIDE,
	"freight_yard": RIVERSIDE,
	"courtyard_blocks": RIVERSIDE,
	"bus_depot": ZAVOKZALNY,
	"night_canteen": ZAVOKZALNY,
	"workshop_row": ZAVOKZALNY,
	"almshouse": SOBORNAYA,
	"cathedral_steps": SOBORNAYA,
	"pawn_row": SOBORNAYA,
}

## The eight places a run opens with. Kept as its own list because the first
## district must be complete on its own — a run that starts unable to reach a
## shelter is not a harder game, it is a broken one.
const RIVERSIDE_PLACE_IDS := [
	"underpass", "market", "station_square", "recycling_point", "clinic_yard", "embankment",
	"freight_yard", "courtyard_blocks",
]


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for place_id: String in PLACES:
		result.append(place_id)
	return result


static func is_place(place_id: String) -> bool:
	return PLACES.has(place_id)


static func district_of(place_id: String) -> String:
	return String(PLACES.get(place_id, ""))


static func ids_in(district_id: String) -> Array[String]:
	var result: Array[String] = []
	for place_id: String in PLACES:
		if String(PLACES[place_id]) == district_id:
			result.append(place_id)
	return result


static func district_ids() -> Array[String]:
	var result: Array[String] = []
	for district_id: String in DISTRICT_TITLES:
		result.append(district_id)
	return result


static func district_title(district_id: String) -> String:
	return String(DISTRICT_TITLES.get(district_id, ""))


## What the hero has to know before this district is on his map. Empty means it
## needs nothing — he is standing in it.
static func knowledge_for(district_id: String) -> String:
	return String(DISTRICT_KNOWLEDGE.get(district_id, ""))


## Whether the hero knows this district exists. Rule 3.4: a district he has not
## heard of is absent from the map, not greyed out with an explanation.
static func is_known(run_state: RunState, district_id: String) -> bool:
	var knowledge_id := knowledge_for(district_id)
	if knowledge_id.is_empty():
		return true
	return run_state != null and run_state.has_knowledge(knowledge_id)
