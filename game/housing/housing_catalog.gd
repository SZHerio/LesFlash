class_name HousingCatalog
extends RefCounted

## Somewhere to come back to.
##
## A paid room is bought one night at a time and forgotten by morning. A rented
## one is an arrangement: cheaper by the night, and it holds the hero to a date
## whether the week went well or badly. That difference is the whole reason this
## exists — it is the first thing in the game he cannot simply stop doing.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")
const ShelterCatalogScript := preload("res://game/shelter/shelter_catalog.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "housing_catalog_v1"
const DEFAULT_PATH := "res://game/housing/data/housing_catalog_v1.json"

## What a night in a paid room costs, for comparison. A rented place that is not
## cheaper by the night than paying nightly is a worse deal with a due date
## attached, and nobody would take it.
const NIGHTLY_ROOM_PRICE := 100


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
	var entries := Rules.index_entries(catalog.get("rooms", null), "rooms", "room_", errors)
	for room_id: String in entries:
		var entry: Dictionary = entries[room_id]
		var path := "rooms.%s" % room_id
		for field: String in ["title", "description"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		if String(entry.get("location_id", "")) not in CityPlaces.PLACES:
			errors.append("%s.location_id неизвестен" % path)
		Rules.validate_int_range(entry.get("deposit_ard", null), 0, 2_000, "%s.deposit_ard" % path, errors)
		Rules.validate_int_range(entry.get("rent_ard", null), 1, 2_000, "%s.rent_ard" % path, errors)
		Rules.validate_int_range(entry.get("rent_every_days", null), 1, 30, "%s.rent_every_days" % path, errors)
		_validate_the_bed_is_here(entry, path, errors)
		_validate_it_beats_the_street(entry, path, errors)
	return {"ok": errors.is_empty(), "errors": errors}


## A room has to be worth taking and worth losing.
##
## Cheaper by the night than paying nightly, or the arrangement is strictly
## worse than the thing it replaces. And not free, or there is nothing to miss
## and no reason a date would ever matter.
static func _validate_it_beats_the_street(
	entry: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var days := int(entry.get("rent_every_days", 0))
	var rent := int(entry.get("rent_ard", 0))
	if days <= 0:
		return
	@warning_ignore("integer_division")
	var nightly := rent / days
	if nightly >= NIGHTLY_ROOM_PRICE:
		errors.append("%s: снимать не дешевле, чем платить за ночь" % path)
	if rent <= 0:
		errors.append("%s: за это нечего не платить, значит нечего и терять" % path)


## The bed has to be where the room is. Renting a corner in one district and
## being handed somewhere to sleep in another is not a room, and the mistake is
## invisible until a player has paid for it and finds nowhere to lie down — which
## is exactly how it was found.
static func _validate_the_bed_is_here(
	entry: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var shelter_id := String(entry.get("shelter_id", "")).strip_edges()
	if shelter_id.is_empty():
		errors.append("%s.shelter_id не задан: комната должна давать где спать" % path)
		return
	var shelters := ShelterCatalogScript.load_default()
	if not bool(shelters.get("ok", false)):
		return
	for raw_option: Variant in Array(Dictionary(shelters["catalog"]).get("options", [])):
		var option: Dictionary = raw_option
		if String(option.get("shelter_id", "")) != shelter_id:
			continue
		if String(entry.get("location_id", "")) not in Array(option.get("location_ids", [])):
			errors.append("%s: ночлег %s находится не там, где комната" % [path, shelter_id])
		return
	errors.append("%s.shelter_id ссылается на несуществующий ночлег" % path)


static func find(catalog: Dictionary, room_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("rooms", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == room_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


static func at_location(catalog: Dictionary, location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_entry: Variant in Array(catalog.get("rooms", [])):
		if raw_entry is Dictionary and String(Dictionary(raw_entry).get("location_id", "")) == location_id:
			result.append(Dictionary(raw_entry).duplicate(true))
	return result


## The id under which a room's rent lives in the obligation ledger. One room,
## one standing debt, so taking the same room twice cannot double the rent.
static func rent_obligation_id(room_id: String) -> String:
	return "rent:%s" % room_id
