class_name EventDistributionSimulator
extends RefCounted

const Director := preload("res://game/events/event_director.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")


static func simulate(
	catalog: Dictionary,
	context: Dictionary,
	seed: int,
	samples: int
) -> Dictionary:
	if samples < 1 or samples > 100_000:
		return {"ok": false, "code": "invalid_samples", "counts": {}, "samples": 0}
	var rng: DeterministicRng = RngScript.new(seed)
	var counts: Dictionary = {}
	var tones := {"adverse": 0, "neutral": 0, "positive": 0, "none": 0}
	for _index: int in samples:
		var selection := Director.select(catalog, context, rng.to_dict())
		if not bool(selection.get("ok", false)):
			return {
				"ok": false,
				"code": String(selection.get("code", "selection_failed")),
				"counts": counts,
				"samples": _index,
			}
		rng = RngScript.from_dict(selection.get("rng", {}))
		var card: Dictionary = selection.get("card", {})
		var card_id := String(card.get("id", ""))
		if card_id.is_empty():
			tones["none"] = int(tones["none"]) + 1
			continue
		counts[card_id] = int(counts.get(card_id, 0)) + 1
		var tone := String(card.get("tone", "neutral"))
		tones[tone] = int(tones.get(tone, 0)) + 1
	return {
		"ok": true,
		"code": "ok",
		"samples": samples,
		"counts": counts,
		"tones": tones,
		"rng": rng.to_dict(),
	}
