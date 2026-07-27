class_name WorldReadModel
extends RefCounted

## Pure projections over WorldState. No projection consumes RNG or mutates the
## state. `rules` is for deterministic systems; `observed` is safe for UI.


static func build(
	state: WorldState,
	visibility: Dictionary = {},
	causes: Dictionary = {}
) -> Dictionary:
	if state == null or not bool(state.validate().get("ok", false)):
		return {}
	return {
		"schema_version": 1,
		"revision": state.revision,
		"rules": rules_projection(state),
		"observed": observed_projection(state, visibility, causes),
	}


static func rules_projection(state: WorldState) -> Dictionary:
	if state == null:
		return {}
	var facts: Dictionary = {}
	for raw_id: Variant in state.facts:
		facts[String(raw_id)] = bool(Dictionary(state.facts[raw_id]).get("value", false))
	var processes: Dictionary = {}
	for raw_id: Variant in state.processes:
		processes[String(raw_id)] = String(Dictionary(state.processes[raw_id]).get("stage", ""))
	return {
		"revision": state.revision,
		"facts": facts,
		"metrics": state.metrics.duplicate(true),
		"processes": processes,
	}


static func observed_projection(
	state: WorldState,
	visibility: Dictionary,
	causes: Dictionary = {}
) -> Dictionary:
	if state == null:
		return {}
	var rules := rules_projection(state)
	var result := {"revision": state.revision, "facts": {}, "metrics": {}, "processes": {}, "causes": {}}
	for section: String in ["facts", "metrics", "processes"]:
		var allowed: Array = Array(visibility.get(section, []))
		for raw_id: Variant in allowed:
			var identifier := String(raw_id)
			if Dictionary(rules.get(section, {})).has(identifier):
				result[section][identifier] = rules[section][identifier]
				if causes.has(identifier):
					result["causes"][identifier] = causes[identifier]
	return result.duplicate(true)
