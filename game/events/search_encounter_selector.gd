class_name SearchEncounterSelector
extends RefCounted

## Deterministic one-shot card choice for a search encounter.
##
## The card is chosen at the moment the encounter is created and then stored in
## the zone snapshot, so reopening the zone or reloading a save never re-rolls
## it. The seed is derived from immutable data, so selection touches neither the
## run RNG nor the zone stream.

const CatalogScript := preload("res://game/events/event_catalog.gd")
const Director := preload("res://game/events/event_director.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")

const MODULUS := 2_147_483_647
const MULTIPLIER := 131


static func derive_seed(zone_seed: int, encounter_id: String) -> int:
	var accumulator := 17
	var material := "zone:%d|%s|search-encounter" % [zone_seed, encounter_id]
	for byte_value: int in material.to_utf8_buffer():
		accumulator = (accumulator * MULTIPLIER + byte_value + 17) % MODULUS
	return accumulator if accumulator != 0 else 1


static func select(
	zone_seed: int,
	encounter_id: String,
	context: Dictionary
) -> Dictionary:
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return {}
	var rng: DeterministicRng = RngScript.new(derive_seed(zone_seed, encounter_id))
	var selection := Director.select(loaded["catalog"], context, rng.to_dict())
	if not bool(selection.get("ok", false)):
		return {}
	var card_id := String(selection.get("card_id", ""))
	if card_id.is_empty():
		return {}
	var card: Dictionary = selection.get("card", {})
	return {
		"card_id": card_id,
		"tone": String(card.get("tone", "neutral")),
		"cooldown_minutes": int(card.get("cooldown_minutes", 0)),
	}


## Reads the zone seed recorded in a snapshot without advancing that stream.
static func zone_seed(snapshot: Dictionary) -> int:
	var rng: DeterministicRng = RngScript.from_dict(snapshot.get("rng", {}))
	return rng.seed if rng != null else 0
