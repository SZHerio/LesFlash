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
const StoreViewModelScript := preload("res://app/commerce/store_view_model.gd")


static func location_model(
	session: Object,
	base_model: Dictionary,
	include_blocked: bool
) -> Dictionary:
	var result := base_model.duplicate(true)
	result["actions"] = WeekActions.actions(session, include_blocked)
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


static func _shelter_description(option: Dictionary) -> String:
	var price := int(option.get("price_arden", 0))
	var price_text := "бесплатно" if price <= 0 else "%d арденов" % price
	return "%s\nПодъём в %s · %s" % [
		String(option.get("description", "")),
		String(option.get("wake_time_text", "—")),
		price_text,
	]


static func _command_id(
	session: Object,
	source: String,
	flow_revision: int
) -> String:
	var elapsed := 0
	if session != null and session.get("run_state") is RunState:
		elapsed = session.get("run_state").calendar.elapsed_minutes
	return "week:%s:%d:%d" % [source, elapsed, flow_revision]
