class_name RunStateMigration
extends RefCounted

## Bringing an old saved run up to the current version, one step at a time.
##
## Every released save format is still readable: a version 3 file walks through
## every intermediate shape until it is a version 6 file, and a file claiming a
## version this build has never heard of is refused outright rather than loaded
## half-understood. Migration never invents content — a field nobody wrote stays
## empty.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")

static func migrate(data: Dictionary) -> Dictionary:
	var source_version: Variant = SerializedValue.parse_integral(data.get("save_version", null))
	if source_version == null:
		return {
			"ok": false,
			"code": "invalid_run_state_version",
			"error": "RunState save_version must be an integer.",
		}
	if int(source_version) not in [
		GameRules.RUN_STATE_VERSION_V1,
		GameRules.RUN_STATE_VERSION_V2,
		GameRules.RUN_STATE_VERSION_V3,
		GameRules.RUN_STATE_VERSION_V4,
		GameRules.RUN_STATE_VERSION_V5,
		GameRules.RUN_STATE_VERSION_V6,
	]:
		return {
			"ok": false,
			"code": "unsupported_run_state_version",
			"error": "RunState save version is unsupported.",
			"actual": int(source_version),
		}
	var migrated := data.duplicate(true)
	var current_version := int(source_version)
	if current_version == GameRules.RUN_STATE_VERSION_V1:
		migrated["save_version"] = GameRules.RUN_STATE_VERSION_V2
		current_version = GameRules.RUN_STATE_VERSION_V2
	if current_version == GameRules.RUN_STATE_VERSION_V2:
		var legacy_inventory: Variant = migrated.get("inventory", null)
		if not legacy_inventory is Dictionary:
			return {
				"ok": false,
				"code": "invalid_legacy_inventory",
				"error": "Legacy inventory must be a dictionary.",
			}
		var parsed_legacy_inventory: Variant = SerializedValue.parse_string_int_map(
			legacy_inventory,
			GameRules.INVENTORY_QUANTITY_MIN,
			GameRules.INVENTORY_QUANTITY_MAX
		)
		if parsed_legacy_inventory == null:
			return {
				"ok": false,
				"code": "invalid_legacy_inventory",
				"error": "Legacy inventory contains invalid quantities.",
			}
		var legacy_skills: Variant = migrated.get("skills", null)
		var parsed_legacy_skills: Variant = SerializedValue.parse_int_map(
			legacy_skills,
			GameRules.LEGACY_SKILL_KEYS,
			GameRules.SKILL_MIN_RANK,
			GameRules.SKILL_MAX_RANK
		)
		if parsed_legacy_skills == null:
			return {
				"ok": false,
				"code": "invalid_legacy_skills",
				"error": "Legacy skills must contain exactly the six M1 skills.",
			}
		parsed_legacy_skills["search"] = 0
		migrated["skills"] = parsed_legacy_skills
		migrated["inventory"] = InventoryStateScript.migrate_legacy(parsed_legacy_inventory)
		migrated["save_version"] = GameRules.RUN_STATE_VERSION_V3
		current_version = GameRules.RUN_STATE_VERSION_V3
	if current_version == GameRules.RUN_STATE_VERSION_V3:
		var legacy_meters: Variant = migrated.get("meters", null)
		if not legacy_meters is Dictionary:
			return {
				"ok": false,
				"code": "invalid_legacy_meters",
				"error": "RunState v3 meters must be a dictionary.",
			}
		var meter_map: Dictionary = Dictionary(legacy_meters).duplicate(true)
		if meter_map.has("morale") and meter_map.has("mental_state"):
			return {
				"ok": false,
				"code": "ambiguous_mental_state",
				"error": "RunState v3 contains both morale and mental_state.",
			}
		if not meter_map.has("morale"):
			return {
				"ok": false,
				"code": "missing_legacy_morale",
				"error": "RunState v3 does not contain morale.",
			}
		meter_map["mental_state"] = meter_map["morale"]
		meter_map.erase("morale")
		migrated["meters"] = meter_map
		for field: String in ["journal", "deferred_consequences"]:
			var references := _rename_legacy_meter_references(
				migrated.get(field, null),
				field
			)
			if not bool(references.get("ok", false)):
				return references
			migrated[field] = references["data"]
		migrated["save_version"] = GameRules.RUN_STATE_VERSION_V4
		current_version = GameRules.RUN_STATE_VERSION_V4
	if current_version == GameRules.RUN_STATE_VERSION_V4:
		# Nothing was recorded about how a rank was earned before this version,
		# so practice starts empty. Ranks already held are kept: the hero does
		# not forget what he could do yesterday.
		migrated["skill_practice"] = GameRules.default_skill_practice()
		migrated["save_version"] = GameRules.RUN_STATE_VERSION_V5
		current_version = GameRules.RUN_STATE_VERSION_V5
	if current_version == GameRules.RUN_STATE_VERSION_V5:
		# Nobody held papers before they existed.
		migrated["qualifications"] = {}
		migrated["save_version"] = GameRules.RUN_STATE_VERSION_V6
		current_version = GameRules.RUN_STATE_VERSION_V6
	if current_version != GameRules.SAVE_VERSION:
		return {
			"ok": false,
			"code": "run_state_migration_incomplete",
			"error": "RunState migration did not reach the current version.",
		}
	migrated["save_version"] = GameRules.SAVE_VERSION
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"data": migrated,
		"migrated": int(source_version) != GameRules.SAVE_VERSION,
		"source_version": int(source_version),
	}


static func _rename_legacy_meter_references(value: Variant, path: String) -> Dictionary:
	if value is Array:
		var output: Array = []
		for index: int in value.size():
			var item := _rename_legacy_meter_references(value[index], "%s[%d]" % [path, index])
			if not bool(item.get("ok", false)):
				return item
			output.append(item["data"])
		return {"ok": true, "data": output}
	if value is Dictionary:
		var source: Dictionary = value
		var is_meter_map := path.ends_with(".meters") or path == "meters"
		if is_meter_map and source.has("morale") and source.has("mental_state"):
			return {
				"ok": false,
				"code": "ambiguous_mental_state_reference",
				"error": "%s contains both morale and mental_state." % path,
			}
		var output: Dictionary = {}
		for raw_key: Variant in source:
			var key: Variant = (
				"mental_state"
				if is_meter_map and String(raw_key) == "morale"
				else raw_key
			)
			var item := _rename_legacy_meter_references(source[raw_key], "%s.%s" % [path, String(raw_key)])
			if not bool(item.get("ok", false)):
				return item
			output[key] = item["data"]
		var effect_type := String(output.get("type", output.get("kind", ""))).to_lower()
		if String(output.get("id", "")) == "morale" and effect_type in ["change_state", "change_meter", "meter"]:
			output["id"] = "mental_state"
		if String(output.get("target_id", "")) == "morale" and String(output.get("target_kind", "")) == "state":
			output["target_id"] = "mental_state"
		return {"ok": true, "data": output}
	return {"ok": true, "data": value}
