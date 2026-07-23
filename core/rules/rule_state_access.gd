class_name RuleStateAccess
extends RefCounted

## Compatibility helpers shared by the rule engine.
##
## Canonical M1 RunState names are characteristics, meters, money, inventory,
## stored_polarities, computed_profiles, skills, knowledge, mastery_points,
## calendar, journal and deferred_consequences. Aliases below keep the rules
## usable while the domain model evolves, without hiding malformed content.

const STAT_CONTAINERS := ["characteristics", "stats", "attributes"]
const STATE_CONTAINERS := ["meters", "states", "vitals", "needs"]
const INVENTORY_CONTAINERS := ["inventory", "items"]
const POLARITY_CONTAINERS := ["stored_polarities", "polarities"]
const PROFILE_CONTAINERS := ["computed_profiles", "polarity_profiles"]
const SKILL_CONTAINERS := ["skills"]
const KNOWLEDGE_CONTAINERS := ["knowledge", "knowledge_tags"]
const JOURNAL_CONTAINERS := ["journal", "history", "action_history"]
const DEFERRED_CONTAINERS := [
	"deferred_consequences",
	"deferred_effects",
	"pending_effects",
]


static func has_property(target: Object, property_name: StringName) -> bool:
	if target == null:
		return false
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func find_dictionary(target: Object, candidates: Array) -> Dictionary:
	for raw_name: Variant in candidates:
		var property_name := StringName(str(raw_name))
		if not has_property(target, property_name):
			continue
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			return {
				"found": true,
				"name": String(property_name),
				"value": value,
			}
	return {"found": false, "name": "", "value": {}}


static func lookup(dictionary: Dictionary, identifier: String) -> Dictionary:
	if dictionary.has(identifier):
		return {"found": true, "key": identifier, "value": dictionary[identifier]}
	var string_name := StringName(identifier)
	if dictionary.has(string_name):
		return {"found": true, "key": string_name, "value": dictionary[string_name]}
	return {"found": false, "key": identifier, "value": null}


static func stat_value(run_state: Object, identifier: String) -> Dictionary:
	return _dictionary_number(run_state, STAT_CONTAINERS, identifier, false)


static func meter_value(run_state: Object, identifier: String) -> Dictionary:
	return _dictionary_number(run_state, STATE_CONTAINERS, identifier, false)


static func money_value(run_state: Object) -> Dictionary:
	for raw_name: String in ["money", "cash"]:
		var property_name := StringName(raw_name)
		if has_property(run_state, property_name):
			var value: Variant = run_state.get(property_name)
			if value is int or value is float:
				return {"found": true, "value": float(value), "property": raw_name}
	var resources := find_dictionary(run_state, ["resources", "economy"])
	if bool(resources["found"]):
		var entry := lookup(resources["value"], "money")
		if bool(entry["found"]) and (entry["value"] is int or entry["value"] is float):
			return {
				"found": true,
				"value": float(entry["value"]),
				"property": String(resources["name"]),
			}
	return {"found": false, "value": 0.0, "property": ""}


static func item_value(run_state: Object, identifier: String) -> Dictionary:
	if run_state != null and run_state.has_method("get_item_count"):
		return {
			"found": true,
			"value": float(run_state.call("get_item_count", identifier)),
			"container": "inventory",
			"key": identifier,
			"structured": true,
		}
	return _dictionary_number(run_state, INVENTORY_CONTAINERS, identifier, true)


static func polarity_value(run_state: Object, identifier: String) -> Dictionary:
	var stored := _dictionary_number(run_state, POLARITY_CONTAINERS, identifier, false)
	if bool(stored["found"]):
		stored["formed"] = true
		stored["stored"] = true
		return stored

	var profiles := find_dictionary(run_state, PROFILE_CONTAINERS)
	if bool(profiles["found"]):
		var entry := lookup(profiles["value"], identifier)
		if bool(entry["found"]):
			var profile_value: Variant = entry["value"]
			if profile_value is Dictionary:
				var formed := bool(profile_value.get("formed", false))
				return {
					"found": true,
					"value": float(profile_value.get("value", 0)),
					"formed": formed,
					"stored": false,
					"container": String(profiles["name"]),
					"key": entry["key"],
				}
	return {
		"found": false,
		"value": 0.0,
		"formed": false,
		"stored": false,
		"container": "",
		"key": identifier,
	}


static func skill_value(run_state: Object, identifier: String) -> Dictionary:
	var container := find_dictionary(run_state, SKILL_CONTAINERS)
	if not bool(container["found"]):
		return {"found": false, "value": 0.0, "container": "", "key": identifier}
	var entry := lookup(container["value"], identifier)
	if not bool(entry["found"]):
		return {
			"found": false,
			"value": 0.0,
			"container": String(container["name"]),
			"key": identifier,
		}
	return {
		"found": true,
		"value": float(entry_level(entry["value"], "rank")),
		"container": String(container["name"]),
		"key": entry["key"],
	}


static func knowledge_value(run_state: Object, identifier: String) -> Dictionary:
	var container := find_dictionary(run_state, KNOWLEDGE_CONTAINERS)
	if not bool(container["found"]):
		return {"found": false, "value": 0.0, "container": "", "key": identifier}
	var entry := lookup(container["value"], identifier)
	# Knowledge tags are open-ended. An absent tag is valid level zero, not a
	# malformed identifier as it would be for a predefined stat or skill.
	if not bool(entry["found"]):
		return {
			"found": true,
			"value": 0.0,
			"container": String(container["name"]),
			"key": identifier,
		}
	return {
		"found": true,
		"value": float(entry_level(entry["value"], "level")),
		"container": String(container["name"]),
		"key": entry["key"],
	}


static func entry_level(entry: Variant, preferred_field: String = "level") -> float:
	if entry is bool:
		return 1.0 if entry else 0.0
	if entry is int or entry is float:
		return float(entry)
	if entry is Dictionary:
		for field: String in [preferred_field, "level", "rank", "value", "amount"]:
			var value: Variant = entry.get(field)
			if value is int or value is float:
				return float(value)
	return 0.0


static func time_snapshot(run_state: Object) -> Dictionary:
	for raw_name: String in ["calendar", "game_time", "clock", "time"]:
		var property_name := StringName(raw_name)
		if not has_property(run_state, property_name):
			continue
		var value: Variant = run_state.get(property_name)
		if value is Dictionary:
			return value.duplicate(true)
		if value is Object and value.has_method("current_stamp"):
			var stamp: Variant = value.call("current_stamp")
			if stamp is Dictionary:
				return stamp.duplicate(true)
		if value is Object and value.has_method("to_dict"):
			var serialized: Variant = value.call("to_dict")
			if serialized is Dictionary:
				return serialized.duplicate(true)
	return {}


static func validation_errors(run_state: Object) -> Array[String]:
	var errors: Array[String] = []
	if run_state == null:
		errors.append("RunState отсутствует")
		return errors
	if not run_state.has_method("validate"):
		errors.append("RunState не реализует validate()")
		return errors
	var validation: Variant = run_state.call("validate")
	if validation is bool:
		if not validation:
			errors.append("RunState не прошёл validate()")
		return errors
	if validation is String:
		if not validation.is_empty():
			errors.append(validation)
		return errors
	if validation is Array:
		for item: Variant in validation:
			errors.append(str(item))
		return errors
	if validation is Dictionary:
		if bool(validation.get("ok", false)):
			return errors
		var raw_errors: Variant = validation.get("errors", [])
		if raw_errors is Array:
			for item: Variant in raw_errors:
				errors.append(str(item))
		if errors.is_empty():
			errors.append(str(validation.get("message", "RunState не прошёл validate()")))
		return errors
	errors.append("validate() вернул неподдерживаемый результат")
	return errors


static func _dictionary_number(
		run_state: Object,
		containers: Array,
		identifier: String,
		missing_is_zero: bool
	) -> Dictionary:
	var container := find_dictionary(run_state, containers)
	if not bool(container["found"]):
		return {"found": false, "value": 0.0, "container": "", "key": identifier}
	var entry := lookup(container["value"], identifier)
	if not bool(entry["found"]):
		return {
			"found": missing_is_zero,
			"value": 0.0,
			"container": String(container["name"]),
			"key": identifier,
		}
	var value: Variant = entry["value"]
	if not (value is int or value is float or value is bool or value is Dictionary):
		return {
			"found": false,
			"value": 0.0,
			"container": String(container["name"]),
			"key": entry["key"],
		}
	return {
		"found": true,
		"value": entry_level(value, "value"),
		"container": String(container["name"]),
		"key": entry["key"],
	}
