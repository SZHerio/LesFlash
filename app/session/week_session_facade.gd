class_name WeekSessionFacade
extends RefCounted

## Small application boundary for the seven-day sandbox vertical slice.
## Read models stay pure; every confirmed decision delegates to a session-level
## domain command and receives a unique, reproducible command identifier.

const WeekActions := preload("res://game/week/week_action_service.gd")
const WeekActionCommandScript := preload("res://game/week/week_action_command.gd")
const RoutineCommandScript := preload("res://game/routine/routine_session_command.gd")
const BusinessCommandScript := preload("res://game/business/business_session_command.gd")
const BusinessCatalogScript := preload("res://game/business/business_catalog.gd")
const ObligationCommandScript := preload("res://game/obligations/obligation_session_command.gd")
const TopicCommandScript := preload("res://game/topics/topic_session_command.gd")
const StoreServiceScript := preload("res://game/commerce/store_service.gd")
const CommerceCommandScript := preload("res://game/commerce/commerce_session_command.gd")
const ShelterServiceScript := preload("res://game/shelter/shelter_session_service.gd")
const RecyclingServiceScript := preload("res://game/recycling/recycling_service.gd")
const NpcInteractionServiceScript := preload("res://game/npc/npc_interaction_service.gd")
const JobLocationActionsScript := preload("res://game/jobs/job_location_actions.gd")
const QualificationCommandScript := preload("res://game/content/qualification_session_command.gd")
const JobSessionCommandScript := preload("res://game/jobs/job_session_command.gd")
const JobLadderScript := preload("res://game/jobs/job_ladder.gd")
const JobShiftViewModelScript := preload("res://app/jobs/job_shift_view_model.gd")
const NpcInteractionCommandScript := preload("res://game/npc/npc_interaction_command.gd")
const NpcGiftCommandScript := preload("res://game/npc/npc_gift_command.gd")
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
	actions.append_array(JobLocationActionsScript.location_actions(session, include_blocked))
	actions.append_array(_qualification_actions(session, include_blocked))
	actions.append_array(_business_actions(session, include_blocked))
	actions.append_array(_room_actions(session, include_blocked))
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
	if not bool(raw.get("ok", false)):
		return raw
	var sale := StoreServiceScript.sell_offers(session, store_id)
	if bool(sale.get("ok", false)):
		raw["sell_offers"] = Array(sale.get("offers", [])).duplicate(true)
		raw["sell_message"] = String(sale.get("message", ""))
	return StoreViewModelScript.build(raw, reduced_motion)


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


static func sell_offers(session: Object, store_id: String) -> Dictionary:
	return StoreServiceScript.sell_offers(session, store_id)


static func sell(
	session: Object,
	store_id: String,
	stack_id: String,
	quantity: int,
	expected_revision: int,
	flow_revision: int
) -> Dictionary:
	return CommerceCommandScript.sell(
		session,
		store_id,
		stack_id,
		quantity,
		_command_id(session, "sell:%s:%s" % [store_id, stack_id], flow_revision),
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
			"shielded": int(option.get("shielded", 0)),
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
	# Handing something over is one of the things you can do with a person who is
	# standing in front of you, so it belongs in the same list as talking.
	var gifts := NpcGiftCommandScript.offers(session, npc_id)
	var interactions: Array = Array(source.get("interactions", [])).duplicate(true)
	for gift: Dictionary in gifts:
		if not bool(gift.get("accepted", false)) and not include_blocked:
			continue
		interactions.append(_gift_interaction(gift))
	source["interactions"] = interactions
	var result := NpcInteractionViewModelScript.build(source, reduced_motion)
	result["ok"] = true
	result["code"] = String(raw.get("code", "ok"))
	result["error"] = ""
	result["gifts"] = NpcGiftCommandScript.offers(session, npc_id)
	return result


const GIFT_INTERACTION_PREFIX := "gift:"


static func gift_stack_id(interaction_id: String) -> String:
	return interaction_id.trim_prefix(GIFT_INTERACTION_PREFIX) if is_gift_interaction(interaction_id) else ""


static func is_gift_interaction(interaction_id: String) -> bool:
	return interaction_id.begins_with(GIFT_INTERACTION_PREFIX)


static func _gift_interaction(gift: Dictionary) -> Dictionary:
	var quantity := int(gift.get("quantity", 1))
	return {
		"id": "%s%s" % [GIFT_INTERACTION_PREFIX, String(gift.get("stack_id", ""))],
		"title": "%s — %s" % [String(gift.get("action_title", "Отдать")), String(gift.get("title", ""))],
		"description": (
			"Этот человек ценит такое."
			if bool(gift.get("valued", false))
			else "Вещь перейдёт из рук в руки и больше не вернётся."
		),
		"available": bool(gift.get("accepted", false)),
		"reasons": [] if bool(gift.get("accepted", false)) else [{"message": String(gift.get("reason", ""))}],
		"duration_minutes": int(gift.get("duration_minutes", 0)),
		"category_icon_id": &"nav_items",
		"quantity": quantity,
	}


static func gift_offers(session: Object, npc_id: String) -> Array[Dictionary]:
	return NpcGiftCommandScript.offers(session, npc_id)


static func give_to_npc(
	session: Object,
	npc_id: String,
	stack_id: String,
	quantity: int,
	flow_revision: int
) -> Dictionary:
	return NpcGiftCommandScript.give(
		session,
		npc_id,
		stack_id,
		quantity,
		_command_id(session, "gift:%s:%s" % [npc_id, stack_id], flow_revision)
	)


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
	var lines := PackedStringArray([
		String(option.get("description", "")),
		"Подъём в %s · %s" % [String(option.get("wake_time_text", "—")), price_text],
	])
	# The hero can feel his own coat, so the night says what it is worth here
	# instead of leaving the player to compare two identical-looking options.
	var shielded := int(option.get("shielded", 0))
	if shielded >= 60:
		lines.append("Снаряжение держит тепло всю ночь")
	elif shielded > 0:
		lines.append("Снаряжение отчасти спасает от холода")
	elif int(option.get("exposure", 0)) > 0:
		lines.append("Ночь открыта холоду")
	return "\n".join(lines)


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


static func job_shift_model(session: Object, reduced_motion: bool = false) -> Dictionary:
	if session == null:
		return {}
	var work_state: JobWorkState = session.get("job_work_state")
	var raw := work_state.to_dict()
	raw["dismissed"] = work_state.is_dismissed(work_state.active_job_id())
	raw["quick_resolve"] = JobSessionCommandScript.quick_resolve_available(session)
	# How the supervisor speaks to him is where the hero finds out he has moved
	# up. Rule 3.4: nothing announces a promotion, the greeting simply changes.
	var job_id := work_state.active_job_id()
	var grade := JobLadderScript.grade_of(session.get("run_state"), work_state, job_id)
	raw["grade_id"] = grade
	raw["grade_title"] = JobLadderScript.title_of(grade)
	raw["supervisor_greeting"] = JobLadderScript.address_at(grade)
	return JobShiftViewModelScript.build(raw, reduced_motion)


static func quick_resolve_job_shift(session: Object, flow_revision: int) -> Dictionary:
	return JobSessionCommandScript.quick_resolve(
		session,
		_command_id(session, "job_shift_quick", flow_revision)
	)


static func begin_job_shift(session: Object, flow_revision: int) -> Dictionary:
	var posting := JobSessionCommandScript.job_at(String(session.get("location")))
	if posting.is_empty():
		return {"ok": false, "code": "no_job_here", "error": "Здесь не нанимают"}
	var job_id := String(posting["job_id"])
	return JobSessionCommandScript.begin(
		session,
		job_id,
		_command_id(session, "job_shift_begin:%s" % job_id, flow_revision)
	)


static func resolve_job_shift_step(
	session: Object,
	choice_id: String,
	flow_revision: int
) -> Dictionary:
	return JobSessionCommandScript.resolve_step(
		session,
		choice_id,
		_command_id(session, "job_shift_step:%s" % choice_id, flow_revision)
	)


## Counters where a paper can be obtained. A blocked counter is hidden rather
## than greyed out: rule 3.4 says the interface does not teach its own rules,
## and Artur or a neighbour is how a hero learns what he needs.
static func _qualification_actions(session: Object, include_blocked: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_offer: Variant in QualificationCommandScript.available(session):
		var offer: Dictionary = raw_offer
		var reasons: Array = Array(offer.get("reasons", []))
		var available := reasons.is_empty()
		if not available and not include_blocked:
			continue
		result.append({
			"id": "qualification_%s" % String(offer["id"]),
			"kind": "qualification",
			"category_id": "talk",
			"category_icon_id": "action_talk",
			"title": "Оформить: %s" % String(offer["title"]),
			"description": String(offer["description"]),
			"available": available,
			"reasons": reasons,
			"minutes": int(offer.get("minutes", 0)),
			"intent": {
				"type": "obtain_qualification",
				"payload": {"qualification_id": String(offer["id"])},
			},
			"confirmation_required": true,
		})
	return result


## Buying a place, and — once it is his — coming by to settle up. Both are
## ordinary location actions, because standing at your own bench and deciding
## something is not a different kind of act from any other.
static func _business_actions(session: Object, include_blocked: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_offer: Variant in BusinessCommandScript.offers_at(session):
		var offer: Dictionary = raw_offer
		var reasons: Array = Array(offer.get("reasons", []))
		var available := reasons.is_empty()
		if not available and not include_blocked:
			continue
		result.append({
			"id": "business_open_%s" % String(offer["id"]),
			"kind": "business",
			"category_id": "trade",
			"category_icon_id": "action_trade",
			"title": "Взять себе: %s" % String(offer["title"]),
			"description": "%s Цена — %d ард." % [String(offer["description"]), int(offer["price_ard"])],
			"available": available,
			"reasons": reasons,
			"minutes": 0,
			"intent": {
				"type": "open_business",
				"payload": {"business_id": String(offer["id"])},
			},
			"confirmation_required": true,
		})
	var business: BusinessState = session.get("business_state")
	if business == null or not business.owns_anything():
		return result
	var loaded := BusinessCatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var entry := BusinessCatalogScript.find(Dictionary(loaded["catalog"]), business.business_id)
	if String(entry.get("location_id", "")) != String(session.get("location")):
		return result
	var run_state: RunState = session.get("run_state")
	var days := business.days_owed(int(run_state.calendar.elapsed_minutes))
	result.append({
		"id": "business_settle",
		"kind": "business",
		"category_id": "trade",
		"category_icon_id": "action_trade",
		"title": "Свести счёта",
		"description": (
			"Посмотреть, что тут было без вас." if days <= 0
			else "Без вас прошло дней: %d." % days
		),
		"available": true,
		"reasons": [],
		"minutes": 0,
		"intent": {"type": "settle_business", "payload": {}},
		"confirmation_required": true,
	})
	return result


## Rooms going here, and rent that can be handed over on the spot. Both are
## ordinary location actions: taking a room is a decision like any other, and
## the only thing that makes it different is that it does not end.
static func _room_actions(session: Object, include_blocked: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_room: Variant in ObligationCommandScript.rooms_at(session):
		var room: Dictionary = raw_room
		var reasons: Array = Array(room.get("reasons", []))
		var available := reasons.is_empty()
		if not available and not include_blocked:
			continue
		result.append({
			"id": "room_take_%s" % String(room["id"]),
			"kind": "room",
			"category_id": "shelter",
			"category_icon_id": "action_shelter",
			"title": "Снять: %s" % String(room["title"]),
			"description": "%s Залог и плата вперёд — %d ард, дальше %d раз в %d дней." % [
				String(room["description"]),
				int(room["upfront_ard"]),
				int(room["rent_ard"]),
				int(room["rent_every_days"]),
			],
			"available": available,
			"reasons": reasons,
			"minutes": 0,
			"intent": {"type": "take_room", "payload": {"room_id": String(room["id"])}},
			"confirmation_required": true,
		})
	for raw_entry: Variant in ObligationCommandScript.ledger(session):
		var entry: Dictionary = raw_entry
		if bool(entry.get("broken", false)):
			continue
		# Only what is close enough to matter. A debt with a week still on it is
		# not something a place should be nagging about.
		if int(entry.get("days_left", 0)) > 2 and not bool(entry.get("overdue", false)):
			continue
		result.append({
			"id": "obligation_pay_%s" % String(entry["id"]),
			"kind": "room",
			"category_id": "trade",
			"category_icon_id": "action_trade",
			"title": "Заплатить: %s" % String(entry["title"]),
			"description": (
				"Просрочено." if bool(entry.get("overdue", false))
				else "Осталось дней: %d." % int(entry.get("days_left", 0))
			) + " Сумма — %d ард." % int(entry.get("amount_ard", 0)),
			"available": true,
			"reasons": [],
			"minutes": 0,
			"intent": {"type": "pay_obligation", "payload": {"obligation_id": String(entry["id"])}},
			"confirmation_required": true,
		})
	return result


## --- о чём с ним можно заговорить ------------------------------------------


static func npc_topics(session: Object, npc_id: String) -> Array[Dictionary]:
	return TopicCommandScript.available(session, npc_id)


static func raise_topic(
	session: Object,
	npc_id: String,
	topic_id: String,
	flow_revision: int
) -> Dictionary:
	return TopicCommandScript.raise_topic(
		session,
		npc_id,
		topic_id,
		_command_id(session, "topic:%s:%s" % [npc_id, topic_id], flow_revision)
	)


## --- what he owes, and by when ---------------------------------------------


static func rooms_here(session: Object) -> Array[Dictionary]:
	return ObligationCommandScript.rooms_at(session)


static func obligation_ledger(session: Object) -> Array[Dictionary]:
	return ObligationCommandScript.ledger(session)


static func take_room(session: Object, room_id: String, flow_revision: int) -> Dictionary:
	return ObligationCommandScript.take_room(
		session, room_id, _command_id(session, "room:%s" % room_id, flow_revision)
	)


static func pay_obligation(session: Object, obligation_id: String, flow_revision: int) -> Dictionary:
	return ObligationCommandScript.pay(
		session, obligation_id, _command_id(session, "obligation:pay:%s" % obligation_id, flow_revision)
	)


static func obligations_fall_due(session: Object, flow_revision: int) -> Dictionary:
	return ObligationCommandScript.fall_due(
		session, _command_id(session, "obligation:due", flow_revision)
	)


## --- a place of his own ---------------------------------------------------


static func business_offers(session: Object) -> Array[Dictionary]:
	return BusinessCommandScript.offers_at(session)


static func open_business(session: Object, business_id: String, flow_revision: int) -> Dictionary:
	return BusinessCommandScript.open(
		session, business_id, _command_id(session, "business:open:%s" % business_id, flow_revision)
	)


static func restock_business(session: Object, units: int, flow_revision: int) -> Dictionary:
	return BusinessCommandScript.restock(
		session, units, _command_id(session, "business:restock:%d" % units, flow_revision)
	)


static func set_business_hands(session: Object, count: int, flow_revision: int) -> Dictionary:
	return BusinessCommandScript.set_hands(
		session, count, _command_id(session, "business:hands:%d" % count, flow_revision)
	)


static func settle_business(session: Object, flow_revision: int) -> Dictionary:
	return BusinessCommandScript.settle(
		session, _command_id(session, "business:settle", flow_revision)
	)


## --- the week the hero means to have ---------------------------------------


static func routine_options(session: Object, block_id: String) -> Array[Dictionary]:
	return RoutineCommandScript.options_for(session, block_id)


static func set_routine_block(
	session: Object,
	day_of_week: int,
	block_id: String,
	activity_id: String,
	flow_revision: int
) -> Dictionary:
	return RoutineCommandScript.set_block(
		session,
		day_of_week,
		block_id,
		activity_id,
		_command_id(session, "routine:%d:%s" % [day_of_week, block_id], flow_revision)
	)


static func set_routine_following(
	session: Object,
	following: bool,
	flow_revision: int
) -> Dictionary:
	return RoutineCommandScript.set_following(
		session,
		following,
		_command_id(session, "routine:following:%s" % str(following), flow_revision)
	)


static func clear_routine(session: Object, flow_revision: int) -> Dictionary:
	return RoutineCommandScript.clear(
		session,
		_command_id(session, "routine:clear", flow_revision)
	)


static func obtain_qualification(
	session: Object,
	qualification_id: String,
	flow_revision: int
) -> Dictionary:
	return QualificationCommandScript.obtain(
		session,
		qualification_id,
		_command_id(session, "qualification:%s" % qualification_id, flow_revision)
	)
