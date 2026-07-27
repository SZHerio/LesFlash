class_name EventHistory
extends RefCounted

## Reconstructs per-life event occurrences from the authoritative RunState
## journal. Duplicate facts are intentional: each resolved occurrence counts.


static func facts(run_state: RunState, legacy_facts: Array = []) -> Array:
	var result: Array = []
	if run_state == null:
		return legacy_facts.duplicate(true)
	for raw_entry: Variant in run_state.journal:
		if not raw_entry is Dictionary:
			continue
		var payload: Variant = Dictionary(raw_entry).get("payload", {})
		if not payload is Dictionary:
			continue
		var event_id := String(Dictionary(payload).get("event_id", ""))
		if event_id.is_empty():
			continue
		var option_id := String(Dictionary(payload).get("option_id", "resolved"))
		result.append("event:%s:%s" % [event_id, option_id])
	return result if not result.is_empty() else legacy_facts.duplicate(true)
