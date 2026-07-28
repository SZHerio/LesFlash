class_name NpcGiftCommand
extends RefCounted

## Handing a carried thing to a person who is standing in front of you.
##
## A gift is not a trade: nothing comes back in the same minute. What changes is
## what the other person thinks and remembers, which is why the item, the clock,
## the relationship and the memory all commit in one transaction.

const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const NpcCatalogScript := preload("res://game/content/catalogs/npc_catalog.gd")
const ScheduleResolverScript := preload("res://game/npc/npc_schedule_resolver.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")

const DEFAULT_MINUTES := 3
const VALUE_PER_AFFINITY_POINT := 50
const MAX_BASE_AFFINITY := 5
const VALUED_TAG_TRUST := 2
const VALUED_TAG_AFFINITY := 1


## Everything the hero is carrying that this person would take, with the price
## of giving it away already visible.
static func offers(session: Object, npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var setup := _setup(session, npc_id)
	if not bool(setup.get("ok", false)):
		return result
	var preferences: Dictionary = setup["preferences"]
	var run_state: RunState = session.get("run_state")
	for raw_stack: Variant in InventoryStateScript.all_stacks(run_state.inventory):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = raw_stack
		if bool(stack.get("external", false)):
			continue
		var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
		var action: Dictionary = definition.action("give")
		if action.is_empty():
			continue
		var tags: Array = definition.tags()
		var refused := _matches(tags, Array(preferences.get("refused_tags", [])))
		var valued := _matches(tags, Array(preferences.get("valued_tags", [])))
		result.append({
			"stack_id": String(stack.get("stack_id", "")),
			"item_id": String(definition.id()),
			"title": String(definition.title()),
			"quantity": int(stack.get("quantity", 0)),
			"action_title": String(action.get("title", "Отдать")),
			"duration_minutes": maxi(int(action.get("duration_minutes", DEFAULT_MINUTES)), 1),
			"accepted": not refused,
			"valued": valued,
			"reason": String(preferences.get("refused_note", "Этот человек такого не возьмёт")) if refused else "",
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("stack_id", "")) < String(right.get("stack_id", ""))
	)
	return result


static func give(
	target: Object,
	npc_id: String,
	stack_id: String,
	quantity: int,
	command_id: String
) -> Dictionary:
	if command_id.strip_edges().is_empty() or command_id.length() > 160:
		return _failure("invalid_command_id", "Передача должна иметь стабильный command_id")
	var setup := _setup(target, npc_id)
	if not bool(setup.get("ok", false)):
		return setup
	if Dictionary(target.get("applied_command_ids")).has(command_id):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var run_state: RunState = target.get("run_state")
	var day_index := int(run_state.calendar.elapsed_minutes / 1440)
	# One accepted gift a day per person. Generosity is remembered; a stack of
	# cigarettes handed over one by one is not a relationship.
	if _gave_on_day(run_state, npc_id, day_index):
		return _failure("gift_already_given_today", "Сегодня вы уже что-то передавали этому человеку")
	var stack := InventoryStateScript.find_stack(run_state.inventory, stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return _failure("missing_stack", "Предмет больше не находится у героя")
	var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
	var action: Dictionary = definition.action("give")
	if action.is_empty():
		return _failure("action_not_allowed", "Этот предмет не передают из рук в руки")
	var available := int(stack.get("quantity", 0))
	var given := available if quantity <= 0 else quantity
	if given <= 0 or given > available:
		return _failure("invalid_quantity", "Указано неверное количество")
	var preferences: Dictionary = setup["preferences"]
	var tags: Array = definition.tags()
	if _matches(tags, Array(preferences.get("refused_tags", []))):
		return _failure(
			"gift_refused",
			String(preferences.get("refused_note", "Этот человек такого не возьмёт"))
		)

	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("session_clone_failed", "Не удалось подготовить передачу")
	var candidate_state: RunState = candidate.get("run_state")
	var removal := InventoryStateScript.remove_stack(candidate_state.inventory, stack_id, given)
	if not bool(removal.get("ok", false)):
		return removal
	candidate_state.inventory = Dictionary(removal["inventory"]).duplicate(true)

	var valued := _matches(tags, Array(preferences.get("valued_tags", [])))
	var worth := int(definition.base_value()) * given
	@warning_ignore("integer_division")
	var affinity: int = clampi(1 + worth / VALUE_PER_AFFINITY_POINT, 1, MAX_BASE_AFFINITY)
	if valued:
		affinity += VALUED_TAG_AFFINITY
	var trust := VALUED_TAG_TRUST if valued else 0
	var effects: Array = [{
		"type": "advance_time",
		"minutes": maxi(int(action.get("duration_minutes", DEFAULT_MINUTES)), 1),
		"reason": "Передача: %s" % String(definition.title()),
	}]
	effects.append({
		"type": "change_relationship",
		"npc_id": npc_id,
		"field": "affinity",
		"delta": affinity,
	})
	if trust != 0:
		effects.append({
			"type": "change_relationship",
			"npc_id": npc_id,
			"field": "trust",
			"delta": trust,
		})
	effects.append({
		"type": "add_npc_memory",
		"npc_id": npc_id,
		"memory": {
			"memory_id": "gift_%s_day_%d" % [String(definition.id()), day_index],
			"type_id": "shared_resource",
			"valence": clampi(affinity * 10, -100, 100),
			"salience": 40 if valued else 20,
		},
	})
	effects.append_array(Array(action.get("effects", [])).duplicate(true))

	var transaction := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "npc_gift:%s" % npc_id,
		"title": String(action.get("title", "Отдать")),
		"journal_message": "%s — %s" % [String(setup["display_name"]), String(definition.title())],
		"journal_payload": {
			"npc_id": npc_id,
			"item_id": String(definition.id()),
			"quantity": given,
			"gift_day_index": day_index,
			"valued": valued,
		},
		"conditions": [],
		"effects": effects,
	}, {"source": "npc_gift", "npc_id": npc_id})
	if not bool(transaction.get("ok", false)):
		return transaction
	var validation: Dictionary = candidate.call("validate")
	if not bool(validation.get("ok", false)):
		return _failure("session_validation_failed", "Передача создала некорректную сессию", {
			"validation": validation,
		})
	if not bool(target.call("replace_from", candidate)):
		return _failure("session_commit_failed", "Сессия отклонила передачу")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"npc_id": npc_id,
		"item_id": String(definition.id()),
		"quantity": given,
		"valued": valued,
		"affinity_delta": affinity,
		"trust_delta": trust,
		"note": String(preferences.get("accepted_note", "Передано из рук в руки")),
		"relationship": target.get("social_state").relationship(npc_id),
		"transaction": transaction,
	}


static func _setup(session: Object, npc_id: String) -> Dictionary:
	if session == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	for method: String in ["clone", "replace_from", "validate"]:
		if not session.has_method(method):
			return _failure("invalid_session", "Сессия не реализует %s()" % method)
	if not session.get("run_state") is RunState or not session.get("social_state") is SocialState:
		return _failure("invalid_session", "Состояние сессии не поддерживает передачу")
	var loaded := NpcCatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("catalog_failed", "Каталог персонажей недоступен")
	var catalog: Dictionary = loaded["catalog"]
	var npc: Dictionary = {}
	for raw_npc: Variant in Array(catalog.get("npcs", [])):
		if raw_npc is Dictionary and String(raw_npc.get("id", "")) == npc_id:
			npc = Dictionary(raw_npc).duplicate(true)
			break
	if npc.is_empty():
		return _failure("unknown_npc", "Персонаж не найден")
	var presence := ScheduleResolverScript.presence(
		catalog,
		npc_id,
		session.get("run_state").calendar.current_stamp(),
		_location_id(session)
	)
	if not bool(presence.get("present", false)):
		return _failure(
			"npc_unavailable",
			String(presence.get("message", "Персонажа здесь нет")),
			{"presence": presence}
		)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"npc": npc,
		"display_name": String(npc.get("display_name", npc_id)),
		"preferences": Dictionary(npc.get("gift_preferences", {})).duplicate(true),
	}


static func _gave_on_day(run_state: RunState, npc_id: String, day_index: int) -> bool:
	for raw_entry: Variant in run_state.journal:
		if not raw_entry is Dictionary:
			continue
		var payload: Variant = Dictionary(raw_entry).get("payload", {})
		if not payload is Dictionary:
			continue
		var entry: Dictionary = payload
		if (
			String(entry.get("npc_id", "")) == npc_id
			and int(entry.get("gift_day_index", -1)) == day_index
		):
			return true
	return false


static func _matches(tags: Array, wanted: Array) -> bool:
	for raw_tag: Variant in wanted:
		if String(raw_tag) in tags:
			return true
	return false


static func _location_id(session: Object) -> String:
	for field: String in ["base_location", "location"]:
		for raw_property: Variant in session.get_property_list():
			if raw_property is Dictionary and String(raw_property.get("name", "")) == field:
				return String(session.get(field))
	return ""


static func _failure(code: String, error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(details, true)
	return result
