extends SceneTree

## Balance probe for M5 stage 3, run as its own pass after the mechanics.
##
## A district is worth travelling to or it is scenery. This counts what is
## actually in each one against what getting there costs, and prints both. It
## asserts nothing: the answer is a design decision, and the point is to see it
## rather than assume it.

const Content = preload("res://game/district/district_content.gd")
const ActionCatalog = preload("res://game/sandbox/sandbox_action_catalog.gd")
const StoreCatalog = preload("res://game/commerce/store_catalog.gd")
const ShelterCatalog = preload("res://game/shelter/shelter_catalog.gd")


func _init() -> void:
	var actions := _by_location(ActionCatalog.load_default(), "actions", "location_id")
	var stores := _by_location(StoreCatalog.load_default(), "stores", "location_id")
	var shelters := _by_location(ShelterCatalog.load_default(), "shelters", "location_id")

	print("DISTRICTS BALANCE PROBE")
	for district: Dictionary in Content.districts():
		var district_id := String(district.get("id", ""))
		var counts := {"actions": 0, "stores": 0, "shelters": 0}
		for place_id: String in Array(district.get("location_ids", [])):
			counts["actions"] = int(counts["actions"]) + int(actions.get(place_id, 0))
			counts["stores"] = int(counts["stores"]) + int(stores.get(place_id, 0))
			counts["shelters"] = int(counts["shelters"]) + int(shelters.get(place_id, 0))
		print("  %-18s мест %d, занятий %d, магазинов %d, ночлегов %d%s" % [
			String(district.get("title", district_id)),
			Array(district.get("location_ids", [])).size(),
			int(counts["actions"]),
			int(counts["stores"]),
			int(counts["shelters"]),
			"" if String(district.get("knowledge_id", "")).is_empty() else "  (нужно узнать о нём)",
		])

	print("  --")
	for place_id: String in Content.locations():
		for raw_route: Variant in Content.routes_from(place_id):
			var route: Dictionary = raw_route
			if not route.has("transport"):
				continue
			var transport: Dictionary = route["transport"]
			print("  %s -> %s: %d ард, %d мин, ходит %s—%s" % [
				place_id,
				String(route.get("destination_id", "")),
				int(transport.get("fare", 0)),
				int(transport.get("minutes", 0)),
				_clock(int(transport.get("opens_minute", 0))),
				_clock(int(transport.get("closes_minute", 0))),
			])
	print("DISTRICTS BALANCE PROBE WRITTEN")
	quit(0)


func _by_location(loaded: Dictionary, key: String, field: String) -> Dictionary:
	var result: Dictionary = {}
	if not bool(loaded.get("ok", false)):
		return result
	for raw_entry: Variant in Array(Dictionary(loaded.get("catalog", {})).get(key, [])):
		if not raw_entry is Dictionary:
			continue
		var place_id := String(Dictionary(raw_entry).get(field, ""))
		result[place_id] = int(result.get(place_id, 0)) + 1
	return result


func _clock(minute: int) -> String:
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minute / 60, minute % 60]
