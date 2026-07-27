class_name WeekSessionFacade
extends RefCounted

## Small application boundary for the seven-day sandbox vertical slice.
## Read models stay pure; every confirmed decision delegates to a session-level
## domain command and receives a unique, reproducible command identifier.

const WeekActions := preload("res://game/week/week_action_service.gd")
const WeekActionCommandScript := preload("res://game/week/week_action_command.gd")
const StoreServiceScript := preload("res://game/commerce/store_service.gd")
const CommerceCommandScript := preload("res://game/commerce/commerce_session_command.gd")
const ShelterServiceScript := preload("res://game/shelter/shelter_session_service.gd")
const RecyclingServiceScript := preload("res://game/recycling/recycling_service.gd")
const NpcInteractionServiceScript := preload("res://game/npc/npc_interaction_service.gd")
const NpcInteractionCommandScript := preload("res://game/npc/npc_interaction_command.gd")
const StoreViewModelScript := preload("res://app/commerce/store_view_model.gd")
const NpcInteractionViewModelScript := preload("res://app/npc/npc_interaction_view_model.gd")
const NpcPortraitRegistryScript := preload("res://app/npc/npc_portrait_registry.gd")


static func location_model(
	session: Object,
	base_model: Dictionary,
	include_blocked: bool
) -> Dictionary:
	var result := base_model.duplicate(true)
	var actions := WeekActions.actions(session, include_blocked)
	actions.append_array(NpcInteractionServiceScript.location_actions(
		session,
		include_blocked
	))
	result["actions"] = actions
	return result


static func execute_location_action(
	session: Object,
	action_id: String,
	flow_revision: int
) -> Dictionary:
	return WeekActionCommandScript.execute(
		session,
		action_id,
		_command_id(session, "action:%s" % action_id, flow_revision)
	)


static func store_model(
	session: Object,
	store_id: String,
	reduced_motion: bool = false
) -> Dictionary:
	var raw := StoreServiceScript.preview(session, store_id)
	return StoreViewModelScript.build(raw, reduced_motion) if bool(raw.get("ok", false)) else raw


static func buy(
	session: Object,
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	expected_revision: int,
	flow_revision: int
) -> Dictionary:
	return CommerceCommandScript.buy(
		session,
		store_id,
		offer_id,
		quantity,
		target_container_id,
		_command_id(session, "buy:%s:%s" % [store_id, offer_id], flow_revision),
		expected_revision
	)


static func shelters(session: Object) -> Array:
	var resolved := ShelterServiceScript.options(session)
	if not bool(resolved.get("ok", false)):
		return []
	var result: Array = []
	for raw_option: Variant in Array(resolved.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = Dictionary(raw_option)
		var category := String(option.get("category_id", "street"))
		result.append({
			"id": String(option.get("shelter_id", "")),
			"title": String(option.get("title", "Ночлег")),
			"description": _shelter_description(option),
			"locked": not bool(option.get("available", false)),
			"reasons": Array(option.get("blocked_reasons", [])).duplicate(true),
			"quality": {"street": 1, "night_shelter": 3, "paid_room": 5}.get(category, 2),
			"risk": {"street": 4, "night_shelter": 2, "paid_room": 1}.get(category, 3),
			"price_arden": int(option.get("price_arden", 0)),
			"wake_time_text": String(option.get("wake_time_text", "")),
		})
	return result


static func sleep(
	session: Object,
	shelter_id: String,
	flow_revision: int
) -> Dictionary:
	var result := ShelterServiceScript.sleep(
		session,
		shelter_id,
		_command_id(session, "sleep:%s" % shelter_id, flow_revision),
		true
	)
	if bool(result.get("ok", false)) and not result.has("transaction"):
		result["transaction"] = result.duplicate(true)
	return result


static func recycling_offers(session: Object) -> Array[Dictionary]:
	return RecyclingServiceScript.offers(session)


static func npc_model(
	session: Object,
	npc_id: String,
	include_blocked: bool = false,
	reduced_motion: bool = false
) -> Dictionary:
	var raw := NpcInteractionServiceScript.npc_model(session, npc_id, include_blocked)
	if not bool(raw.get("ok", false)):
		return raw
	var source := raw.duplicate(true)
	source["name"] = String(raw.get("display_name", ""))
	source["role"] = String(raw.get("role_title", ""))
	source.merge(NpcPortraitRegistryScript.entry(npc_id), true)
	source["presence_text"] = String(Dictionary(raw.get("presence", {})).get(
		"message",
		"Сейчас здесь"
	))
	source["relationship_label"] = "Отношение"
	source["relationship_value"] = _relationship_text(
		Dictionary(raw.get("relationship", {}))
	)
	var result := NpcInteractionViewModelScript.build(source, reduced_motion)
	result["ok"] = true
	result["code"] = String(raw.get("code", "ok"))
	result["error"] = ""
	return result


static func preview_npc_interaction(
	session: Object,
	npc_id: String,
	interaction_id: String
) -> Dictionary:
	return NpcInteractionServiceScript.preview(session, npc_id, interaction_id)


static func execute_npc_interaction(
	session: Object,
	npc_id: String,
	interaction_id: String,
	expected_flow_revision: int
) -> Dictionary:
	if session == null:
		return NpcInteractionCommandScript.execute(
			session,
			npc_id,
			interaction_id,
			""
		)
	var command_source := "npc:%s:%s" % [npc_id, interaction_id]
	var applied_command_id := _applied_command_id(
		session,
		command_source,
		expected_flow_revision
	)
	if not applied_command_id.is_empty():
		return NpcInteractionCommandScript.execute(
			session,
			npc_id,
			interaction_id,
			applied_command_id
		)
	var current_flow_revision := int(session.get("flow_revision"))
	if expected_flow_revision != current_flow_revision:
		return {
			"ok": false,
			"code": "stale_flow_revision",
			"error": "Сведения о месте устарели. Обновите экран и попробуйте снова.",
			"expected_flow_revision": expected_flow_revision,
			"current_flow_revision": current_flow_revision,
			"actual_flow_revision": current_flow_revision,
		}
	return NpcInteractionCommandScript.execute(
		session,
		npc_id,
		interaction_id,
		_command_id(
			session,
			command_source,
			expected_flow_revision
		)
	)


static func _shelter_description(option: Dictionary) -> String:
	var price := int(option.get("price_arden", 0))
	var price_text := "бесплатно" if price <= 0 else "%d арденов" % price
	return "%s\nПодъём в %s · %s" % [
		String(option.get("description", "")),
		String(option.get("wake_time_text", "—")),
		price_text,
	]


static func _relationship_text(relationship: Dictionary) -> String:
	var labels := {
		"trust": "Доверие",
		"respect": "Уважение",
		"affinity": "Симпатия",
		"fear": "Страх",
	}
	var parts := PackedStringArray()
	for field: String in ["trust", "respect", "affinity", "fear"]:
		var value := int(relationship.get(field, 0))
		if value == 0:
			continue
		parts.append("%s %s%d" % [labels[field], "+" if value > 0 else "", value])
	return "Пока нейтрально" if parts.is_empty() else " · ".join(parts)


static func _command_id(
	session: Object,
	source: String,
	flow_revision: int
) -> String:
	var elapsed := 0
	if session != null and session.get("run_state") is RunState:
		elapsed = session.get("run_state").calendar.elapsed_minutes
	return "week:%s:%d:%d" % [source, elapsed, flow_revision]


static func _applied_command_id(
	session: Object,
	source: String,
	flow_revision: int
) -> String:
	var ledger: Variant = session.get("applied_command_ids")
	if not ledger is Dictionary:
		return ""
	var prefix := "week:%s:" % source
	var suffix := ":%d" % flow_revision
	for raw_command_id: Variant in Dictionary(ledger):
		var command_id := String(raw_command_id)
		if command_id.begins_with(prefix) and command_id.ends_with(suffix):
			return command_id
	return ""
