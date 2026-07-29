extends SceneTree

## Balance probe for the seasons, run as its own pass.
##
## Three questions were written down before it was built. Is winter visible in
## decisions rather than only in numbers; can a build without strength live
## through it; and does the gear people currently buy "just in case" finally pay
## for itself.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const ShelterService = preload("res://game/shelter/shelter_session_service.gd")

const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
## Each bed is only offered where it is. Standing in one place and asking about
## all three reported nothing at all, which read as "winter does not bite".
const SHELTERS := {
	"shelter_underpass_niche": "underpass",
	"shelter_municipal_night_room": "station_square",
	"shelter_station_safe_room": "station_square",
}


func _init() -> void:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		print("SEASONS BALANCE PROBE: песочница не стартовала")
		quit(1)
		return
	var session = adapter.get("_session")
	session.phase = "map"

	print("SEASONS BALANCE PROBE")
	print("  что ночь отнимает, по временам года (здоровье + рассудок + напряжение):")
	print("  %-30s %6s %6s %6s %6s" % ["ночлег", "лето", "весна", "осень", "зима"])
	for shelter_id: String in SHELTERS:
		var row := "  %-30s" % shelter_id
		for month: int in [7, 4, 10, 1]:
			row += " %6d" % _harm(session, month, shelter_id)
		print(row)

	print("  --")
	print("  цена тепла против цены ночи:")
	var niche_summer := _harm(session, 7, "shelter_underpass_niche")
	var niche_winter := _harm(session, 1, "shelter_underpass_niche")
	var room_winter := _harm(session, 1, "shelter_station_safe_room")
	print("    ниша: лето %d -> зима %d (+%d за ночь)" % [
		niche_summer, niche_winter, niche_winter - niche_summer,
	])
	print("    номер зимой: %d — разница с нишей %d за ночь при цене 100 ард" % [
		room_winter, niche_winter - room_winter,
	])
	print("  --")
	print("  что зима даёт взамен: работа, которой летом нет —")
	print("    расчистка площадки, разгребание перрона; пункт обогрева в холода")
	print("SEASONS BALANCE PROBE WRITTEN")
	quit(0)


func _harm(session: Object, month: int, shelter_id: String) -> int:
	session.run_state.calendar.month = month
	session.location = String(SHELTERS.get(shelter_id, "underpass"))
	if "base_location" in session:
		session.base_location = session.location
	var resolved: Dictionary = ShelterService.options(session)
	if not bool(resolved.get("ok", false)):
		return -1
	for raw_option: Variant in Array(resolved.get("options", [])):
		var option: Dictionary = raw_option
		if String(option.get("shelter_id", "")) != shelter_id:
			continue
		var effects: Dictionary = Dictionary(option.get("meter_effects", {}))
		var harm := 0
		for meter_id: String in ["health", "mental_state"]:
			harm += maxi(-int(effects.get(meter_id, 0)), 0)
		harm += maxi(int(effects.get("tension", 0)), 0)
		return harm
	return -1
