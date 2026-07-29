class_name ShelterSessionService
extends RefCounted

## Session-level night flow: pure options and one confirmed atomic sleep.

const CatalogScript := preload("res://game/shelter/shelter_catalog.gd")
const HousingScript := preload("res://game/housing/housing_catalog.gd")
const ResolverScript := preload("res://game/shelter/shelter_resolver.gd")
const CommandBuilderScript := preload("res://game/shelter/shelter_command_builder.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const WorldCatalogScript := preload("res://game/content/catalogs/world_definition_catalog.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")


## Beds the hero already pays rent on. Both the list and the confirmed sleep
## read this out of the context, so the screen and the command can never
## disagree about whether a night costs anything.
##
## The price in the catalog is left alone: a paid room that costs nothing is not
## a valid paid room, and the catalog is right to say so. What changes is not the
## price of the bed, it is who has already paid it.
static func _beds_already_paid(session: Object) -> Array[String]:
	var result: Array[String] = []
	var obligations: ObligationState = session.get("obligation_state")
	if obligations == null or obligations.records.is_empty():
		return result
	var housing := HousingScript.load_default()
	if not bool(housing.get("ok", false)):
		return result
	for raw_room: Variant in Array(Dictionary(housing["catalog"]).get("rooms", [])):
		var room: Dictionary = raw_room
		var obligation_id := HousingScript.rent_obligation_id(String(room.get("id", "")))
		if obligations.has(obligation_id) and not obligations.is_broken(obligation_id):
			result.append(String(room.get("shelter_id", "")))
	return result


static func options(session: Object) -> Dictionary:
	var context := _context(session)
	if not bool(context.get("ok", false)):
		return context
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("shelter_catalog_failed", "Каталог ночлега недоступен", {"errors": loaded.get("errors", [])})
	var resolved := ResolverScript.resolve_for_location(loaded["catalog"], context["context"])
	if not bool(resolved.get("ok", false)):
		return resolved
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"location_id": _location_id(session),
		"options": Array(resolved.get("options", [])).duplicate(true),
		"catalog_version": int(resolved.get("catalog_version", 0)),
	}


static func sleep(
	target: Object,
	shelter_id: String,
	command_id: String,
	confirmed: bool
) -> Dictionary:
	var context_result := _context(target)
	if not bool(context_result.get("ok", false)):
		return context_result
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("shelter_catalog_failed", "Каталог ночлега недоступен")
	var context: Dictionary = context_result["context"]
	var day_index := int(target.get("run_state").calendar.elapsed_minutes / 1440)
	if _slept_on_day(target.get("run_state"), day_index):
		return _failure("already_slept_today", "Герой уже завершил этот игровой день")
	var prepared := CommandBuilderScript.prepare(
		loaded["catalog"], shelter_id, context, command_id, confirmed
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	var command: Dictionary = Dictionary(prepared["command"]).duplicate(true)
	var expected: Dictionary = command.get("expected", {})
	if String(expected.get("location_id", "")) != _location_id(target):
		return _failure("location_conflict", "Место изменилось после показа вариантов")
	if Dictionary(expected.get("calendar_stamp", {})) != target.get("run_state").calendar.current_stamp():
		return _failure("calendar_conflict", "Время изменилось после показа вариантов")
	command["journal_message"] = "Ночлег: %s" % String(command.get("option_title", shelter_id))
	command["journal_payload"] = {
		"shelter_id": shelter_id,
		"sleep_day_index": day_index,
		"wake_at": Dictionary(Dictionary(command.get("result_preview", {})).get("wake_at", {})).duplicate(true),
	}
	var world_loaded := WorldCatalogScript.load_default()
	if not bool(world_loaded.get("ok", false)):
		return _failure("world_catalog_failed", "Каталог состояния мира недоступен")
	var result := SessionTransactionScript.execute(target, command, {
		"world_definitions": Dictionary(world_loaded.get("catalog", {})).duplicate(true),
	})
	if not bool(result.get("ok", false)):
		return result
	if _has_property(target, "phase"):
		target.set("phase", "map")
	if _has_property(target, "day_completed"):
		target.set("day_completed", false)
	result["shelter_id"] = shelter_id
	result["sleep_day_index"] = day_index
	result["lifecycle"] = target.get("survival_state").to_dict()
	result["result_preview"] = Dictionary(command.get("result_preview", {})).duplicate(true)
	return result


static func _context(session: Object) -> Dictionary:
	if session == null or not _has_property(session, "run_state") or session.get("run_state") == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	var run_state: RunState = session.get("run_state")
	if not _has_property(session, "survival_state") or session.get("survival_state") == null:
		return _failure("missing_survival", "Состояние недели отсутствует")
	if session.get("survival_state").is_terminal():
		return _failure("lifecycle_complete", "Эта недельная попытка уже завершена")
	return {
		"ok": true,
		"context": {
			"location_id": _location_id(session),
			"money": run_state.money,
			"rent_paid_shelter_ids": _beds_already_paid(session),
			"calendar": run_state.calendar.to_dict(),
			"warmth": EquipmentRulesScript.modifier(run_state.inventory, "warmth"),
		},
	}


static func _slept_on_day(run_state: RunState, day_index: int) -> bool:
	for raw_entry: Variant in run_state.journal:
		if not raw_entry is Dictionary:
			continue
		var payload: Variant = raw_entry.get("payload", {})
		if payload is Dictionary and int(payload.get("sleep_day_index", -1)) == day_index:
			return true
	return false


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		if _has_property(session, field):
			return String(session.get(field))
	return ""


static func _has_property(value: Object, name: String) -> bool:
	for raw_property: Variant in value.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == name:
			return true
	return false


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(extra, true)
	return result
