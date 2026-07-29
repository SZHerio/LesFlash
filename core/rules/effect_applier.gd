class_name EffectApplier
extends RefCounted

## Applies a limited vocabulary of effects to a supplied RunState.
##
## This class mutates its argument. Atomicity is provided by ActionTransaction,
## which always supplies a clone and commits it only after every effect and the
## final validation succeed.


static func apply_all(
		run_state: Object,
		effects: Array,
		context: Dictionary = {}
	) -> Dictionary:
	var changes: Array[Dictionary] = []
	var total_advanced_minutes := 0
	for index: int in effects.size():
		var raw_effect: Variant = effects[index]
		if not raw_effect is Dictionary:
			return _batch_failure(
				"invalid_effect",
				"Эффект с индексом %d должен быть словарём" % index,
				index,
				changes
			)
		var effect_context := context.duplicate(true)
		effect_context["effect_index"] = index
		if _normalized_type(raw_effect) == "advance_time":
			var minutes_result := _integer_field(raw_effect, ["minutes", "amount"], true)
			if bool(minutes_result["valid"]):
				var requested_minutes := int(minutes_result["value"])
				if (
					requested_minutes >= 0
					and total_advanced_minutes > GameRules.MAX_TIME_ADVANCE_MINUTES - requested_minutes
				):
					return _batch_failure(
						"time_advance_too_large",
						"Суммарный переход времени одного решения не может превышать %d минут" % GameRules.MAX_TIME_ADVANCE_MINUTES,
						index,
						changes
					)
		var result := apply_one(run_state, raw_effect, effect_context)
		if not bool(result.get("ok", false)):
			return _batch_failure(
				String(result.get("code", "effect_failed")),
				String(result.get("message", "Не удалось применить эффект")),
				index,
				changes
			)
		changes.append(result["change"])
		if String(result["change"].get("effect_type", "")) == "advance_time":
			total_advanced_minutes += int(result["change"].get("delta", 0))
	return {
		"ok": true,
		"code": "ok",
		"message": "Все эффекты применены",
		"failed_index": -1,
		"changes": changes,
	}


static func apply_one(
		run_state: Object,
		effect: Dictionary,
		context: Dictionary = {}
	) -> Dictionary:
	if run_state == null:
		return _failure("missing_state", "Состояние игры отсутствует")
	var effect_type := _normalized_type(effect)
	if effect_type.is_empty():
		return _failure("invalid_effect", "Не указан тип эффекта")

	match effect_type:
		"advance_time":
			return _advance_time(run_state, effect)
		"change_state":
			return _change_state(run_state, effect)
		"change_money":
			return _change_money(run_state, effect)
		"add_item":
			return _change_item(run_state, effect, true)
		"remove_item":
			return _change_item(run_state, effect, false)
		"shift_polarity":
			return _shift_polarity(run_state, effect)
		"unlock_skill":
			return _unlock_skill(run_state, effect)
		"advance_skill":
			return _advance_skill(run_state, effect)
		"practice_skill":
			return _practice_skill(run_state, effect)
		"wash":
			return _wash(run_state)
		"standing":
			return _standing(run_state, effect)
		"mastery":
			return _change_mastery(run_state, effect)
		"deferred":
			return _schedule_deferred(run_state, effect, context)
		"knowledge":
			return _change_knowledge(run_state, effect)
		_:
			return _failure("unknown_effect", "Неизвестный тип эффекта: %s" % effect_type)


static func _advance_time(run_state: Object, effect: Dictionary) -> Dictionary:
	var minutes_result := _integer_field(effect, ["minutes", "amount"], true)
	if not bool(minutes_result["valid"]):
		return _failure("invalid_minutes", String(minutes_result["message"]))
	var minutes := int(minutes_result["value"])
	if minutes < 0:
		return _failure("invalid_minutes", "Время нельзя сдвинуть назад")
	if minutes > GameRules.MAX_TIME_ADVANCE_MINUTES:
		return _failure(
			"time_advance_too_large",
			"Один переход времени не может превышать %d минут" % GameRules.MAX_TIME_ADVANCE_MINUTES
		)
	var before := RuleStateAccess.time_snapshot(run_state)
	var reason := String(effect.get("reason", ""))
	var payload: Variant = effect.get("payload", {})
	if not payload is Dictionary:
		return _failure("invalid_payload", "Данные эффекта времени должны быть словарём")

	var applied := false
	if run_state.has_method("advance_time"):
		var time_result: Variant = run_state.call(
			"advance_time",
			minutes,
			reason,
			payload.duplicate(true)
		)
		applied = not (time_result is bool) or bool(time_result)
	else:
		for calendar_name: String in ["calendar", "game_time", "clock"]:
			var property_name := StringName(calendar_name)
			if not RuleStateAccess.has_property(run_state, property_name):
				continue
			var calendar: Variant = run_state.get(property_name)
			if calendar is Object and calendar.has_method("advance_minutes"):
				var calendar_result: Variant = calendar.call("advance_minutes", minutes)
				applied = not (calendar_result is bool) or bool(calendar_result)
				break
	if not applied:
		return _failure("time_update_failed", "RunState не смог применить сдвиг времени")

	var after := RuleStateAccess.time_snapshot(run_state)
	return _success(_record(
		"advance_time",
		"time",
		"calendar",
		before,
		after,
		minutes,
		"Прошло %d мин." % minutes,
		effect
	))


static func _change_state(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указана шкала состояния")
	var delta_result := _integer_field(effect, ["delta", "amount"], true)
	if not bool(delta_result["valid"]):
		return _failure("invalid_delta", String(delta_result["message"]))
	var delta := int(delta_result["value"])
	var current := RuleStateAccess.meter_value(run_state, identifier)
	if not bool(current["found"]):
		return _failure("unknown_state", "Неизвестная шкала состояния: %s" % identifier)
	var before := int(roundf(float(current["value"])))
	var applied := false
	if run_state.has_method("change_meter"):
		var method_result: Variant = run_state.call("change_meter", StringName(identifier), delta)
		applied = not (method_result is bool) or bool(method_result)
	else:
		var container := RuleStateAccess.find_dictionary(run_state, RuleStateAccess.STATE_CONTAINERS)
		var dictionary: Dictionary = container["value"]
		var after_fallback := clampi(before + delta, 0, 100)
		dictionary[current["key"]] = after_fallback
		run_state.set(StringName(container["name"]), dictionary)
		applied = true
	if not applied:
		return _failure("state_update_failed", "Не удалось изменить состояние «%s»" % identifier)
	var updated := RuleStateAccess.meter_value(run_state, identifier)
	var after := int(roundf(float(updated["value"])))
	return _success(_record(
		"change_state",
		"state",
		identifier,
		before,
		after,
		after - before,
		"%s: %s → %s" % [identifier, before, after],
		effect
	))


static func _change_money(run_state: Object, effect: Dictionary) -> Dictionary:
	var delta_result := _integer_field(effect, ["delta", "amount"], true)
	if not bool(delta_result["valid"]):
		return _failure("invalid_delta", String(delta_result["message"]))
	var current := RuleStateAccess.money_value(run_state)
	if not bool(current["found"]):
		return _failure("money_not_supported", "RunState не содержит деньги")
	var delta := int(delta_result["value"])
	var before := int(roundf(float(current["value"])))
	var after := before + delta
	if after < 0 and not bool(effect.get("allow_negative", false)):
		return _failure(
			"insufficient_money",
			"Недостаточно денег: нужно %d, доступно %d" % [-delta, before]
		)
	var property_name := String(current["property"])
	if property_name in ["money", "cash"]:
		run_state.set(StringName(property_name), after)
	else:
		var resources := RuleStateAccess.find_dictionary(run_state, [property_name])
		var dictionary: Dictionary = resources["value"]
		dictionary["money"] = after
		run_state.set(StringName(property_name), dictionary)
	return _success(_record(
		"change_money",
		"resource",
		"money",
		before,
		after,
		delta,
		"Деньги: %s → %s" % [before, after],
		effect
	))


static func _change_item(run_state: Object, effect: Dictionary, adding: bool) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указан предмет")
	var quantity_result := _integer_field(effect, ["quantity", "amount"], false)
	if not bool(quantity_result["valid"]):
		return _failure("invalid_quantity", String(quantity_result["message"]))
	var quantity := int(quantity_result["value"])
	if quantity <= 0:
		return _failure("invalid_quantity", "Количество предметов должно быть больше нуля")
	var current := RuleStateAccess.item_value(run_state, identifier)
	if not bool(current.get("found", false)):
		return _failure("inventory_not_supported", "RunState не содержит инвентарь")
	var before := int(roundf(float(current["value"])))
	if not adding and before < quantity:
		return _failure(
			"insufficient_item",
			"Недостаточно предмета «%s»: нужно %d, доступно %d" % [identifier, quantity, before]
		)
	var after := before + quantity if adding else before - quantity
	if run_state.has_method("add_item") and run_state.has_method("remove_item"):
		var changed := (
			bool(run_state.call("add_item", identifier, quantity))
			if adding
			else bool(run_state.call("remove_item", identifier, quantity))
		)
		if not changed:
			return _failure(
				"inventory_capacity" if adding else "insufficient_item",
				"Для предмета «%s» не хватает места." % identifier
				if adding
				else "Недостаточно предмета «%s»." % identifier
			)
	else:
		var container := RuleStateAccess.find_dictionary(run_state, RuleStateAccess.INVENTORY_CONTAINERS)
		if not bool(container["found"]):
			return _failure("inventory_not_supported", "RunState не содержит инвентарь")
		var dictionary: Dictionary = container["value"]
		var item_key: Variant = current.get("key", identifier)
		if after == 0:
			dictionary.erase(item_key)
		else:
			dictionary[item_key] = after
		run_state.set(StringName(container["name"]), dictionary)
	var effect_type := "add_item" if adding else "remove_item"
	return _success(_record(
		effect_type,
		"item",
		identifier,
		before,
		after,
		after - before,
		"%s: %s → %s" % [identifier, before, after],
		effect
	))


static func _shift_polarity(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указана полярность")
	var delta_result := _integer_field(effect, ["delta", "amount"], true)
	if not bool(delta_result["valid"]):
		return _failure("invalid_delta", String(delta_result["message"]))
	var current := RuleStateAccess.polarity_value(run_state, identifier)
	if not bool(current["found"]):
		return _failure("unknown_polarity", "Неизвестная полярность: %s" % identifier)
	if not bool(current.get("stored", false)):
		return _failure(
			"computed_polarity_read_only",
			"Вычисляемый профиль «%s» нельзя сдвигать эффектом" % identifier
		)
	var delta := int(delta_result["value"])
	var before := int(roundf(float(current["value"])))
	var applied := false
	if run_state.has_method("shift_polarity"):
		var method_result: Variant = run_state.call("shift_polarity", StringName(identifier), delta)
		applied = not (method_result is bool) or bool(method_result)
	else:
		var container := RuleStateAccess.find_dictionary(run_state, RuleStateAccess.POLARITY_CONTAINERS)
		var dictionary: Dictionary = container["value"]
		dictionary[current["key"]] = clampi(before + delta, -100, 100)
		run_state.set(StringName(container["name"]), dictionary)
		applied = true
	if not applied:
		return _failure("polarity_update_failed", "Не удалось сдвинуть полярность «%s»" % identifier)
	var after_result := RuleStateAccess.polarity_value(run_state, identifier)
	var after := int(roundf(float(after_result["value"])))
	return _success(_record(
		"shift_polarity",
		"polarity",
		identifier,
		before,
		after,
		after - before,
		"%s: %s → %s" % [identifier, before, after],
		effect
	))


static func _unlock_skill(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указан навык")
	var rank_result := _integer_field(effect, ["rank", "value"], false)
	if not bool(rank_result["valid"]):
		return _failure("invalid_rank", String(rank_result["message"]))
	var rank := int(rank_result["value"])
	if rank < 1 or rank > 3:
		return _failure("invalid_rank", "Начальный ранг навыка должен быть от 1 до 3")
	var current := RuleStateAccess.skill_value(run_state, identifier)
	if not bool(current["found"]):
		return _failure("unknown_skill", "Неизвестный навык: %s" % identifier)
	var before := int(roundf(float(current["value"])))
	var after := maxi(before, rank)
	var update := _write_level(
		run_state,
		RuleStateAccess.SKILL_CONTAINERS,
		current,
		after,
		"rank"
	)
	if not bool(update["ok"]):
		return update
	return _success(_record(
		"unlock_skill",
		"skill",
		identifier,
		before,
		after,
		after - before,
		"Навык %s: ранг %s → %s" % [identifier, before, after],
		effect
	))


## Репутация живёт в сессии, а не в состоянии попытки: её знают люди, а не тело.
## Эффект поэтому только сообщает о поступке, а записывает его команда.
static func _standing(run_state: Object, effect: Dictionary) -> Dictionary:
	var kind := String(effect.get("id", "")).strip_edges()
	if kind not in ["reliable", "feared"]:
		return _failure("unknown_standing", "Неизвестная сторона репутации")
	var weight := int(effect.get("weight", 1))
	if weight <= 0:
		return _failure("invalid_standing_weight", "Поступок должен что-то значить")
	return _success(_record("standing", "standing", kind, 0, weight, weight, "Как о нём говорят", effect))


static func _wash(run_state: Object) -> Dictionary:
	var before := int(run_state.days_unwashed())
	if not bool(run_state.record_wash()):
		return _failure("wash_rejected", "Отметка о мытье не принята")
	return _success(_record("wash", "appearance", "washed", before, 0, -before, "Вымылся", {}))


static func _practice_skill(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указан навык")
	var source_id := String(effect.get("source_id", "")).strip_edges()
	if source_id.is_empty():
		return _failure("missing_practice_source", "Практика должна называть свой источник")
	if not GameRules.is_known_skill(identifier):
		return _failure("unknown_skill", "Неизвестный навык: %s" % identifier)
	var before := int(run_state.get_skill_rank(identifier))
	var after := int(run_state.record_practice(identifier, source_id))
	return _success(_record(
		"practice_skill",
		"skill",
		identifier,
		before,
		after,
		after - before,
		"Навык %s: практика «%s»" % [identifier, source_id],
		effect
	))


static func _advance_skill(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указан навык")
	var ranks_result := _integer_field(effect, ["ranks", "delta", "amount"], false)
	if not bool(ranks_result["valid"]):
		return _failure("invalid_rank_delta", String(ranks_result["message"]))
	var ranks := int(ranks_result["value"])
	var max_rank_value: Variant = effect.get("max_rank", 3)
	if not (max_rank_value is int or (max_rank_value is float and is_equal_approx(max_rank_value, roundf(max_rank_value)))):
		return _failure("invalid_max_rank", "Максимальный ранг должен быть целым числом")
	var max_rank := int(max_rank_value)
	if ranks <= 0 or max_rank < 1 or max_rank > GameRules.SKILL_MAX_RANK:
		return _failure("invalid_rank_delta", "Рост навыка и максимальный ранг должны быть положительными")
	var current := RuleStateAccess.skill_value(run_state, identifier)
	if not bool(current["found"]):
		return _failure("unknown_skill", "Неизвестный навык: %s" % identifier)
	var before := int(roundf(float(current["value"])))
	if before <= 0:
		return _failure("skill_locked", "Навык «%s» ещё не открыт" % identifier)
	if max_rank < before:
		return _failure(
			"invalid_max_rank",
			"Максимальный ранг не может быть ниже текущего ранга навыка"
		)
	var after := mini(before + ranks, max_rank)
	var update := _write_level(
		run_state,
		RuleStateAccess.SKILL_CONTAINERS,
		current,
		after,
		"rank"
	)
	if not bool(update["ok"]):
		return update
	return _success(_record(
		"advance_skill",
		"skill",
		identifier,
		before,
		after,
		after - before,
		"Навык %s: ранг %s → %s" % [identifier, before, after],
		effect
	))


static func _change_mastery(run_state: Object, effect: Dictionary) -> Dictionary:
	var delta_result := _integer_field(effect, ["delta", "amount"], true)
	if not bool(delta_result["valid"]):
		return _failure("invalid_delta", String(delta_result["message"]))
	var property_name := StringName()
	for candidate: String in ["mastery_points", "skill_points"]:
		if RuleStateAccess.has_property(run_state, StringName(candidate)):
			property_name = StringName(candidate)
			break
	if property_name == StringName():
		return _failure("mastery_not_supported", "RunState не содержит очки освоения")
	var raw_before: Variant = run_state.get(property_name)
	if not (raw_before is int or raw_before is float):
		return _failure("invalid_mastery", "Очки освоения должны быть числом")
	var before := int(raw_before)
	var delta := int(delta_result["value"])
	var after := before + delta
	if after < 0:
		return _failure(
			"insufficient_mastery",
			"Недостаточно очков освоения: нужно %d, доступно %d" % [-delta, before]
		)
	run_state.set(property_name, after)
	return _success(_record(
		"mastery",
		"resource",
		"mastery_points",
		before,
		after,
		delta,
		"Очки освоения: %s → %s" % [before, after],
		effect
	))


static func _schedule_deferred(
		run_state: Object,
		effect: Dictionary,
		context: Dictionary
	) -> Dictionary:
	var effect_id := String(effect.get("effect_id", effect.get("id", ""))).strip_edges()
	if effect_id.is_empty():
		return _failure("missing_effect_id", "Не указан идентификатор отложенного последствия")
	var payload: Variant = effect.get("payload", {})
	if not payload is Dictionary:
		return _failure("invalid_payload", "Данные отложенного последствия должны быть словарём")
	var due: Dictionary = {}
	var raw_due: Variant = effect.get("due")
	if raw_due is Dictionary and not raw_due.is_empty():
		due = raw_due.duplicate(true)
	else:
		var delay_result := _integer_field(effect, ["delay_minutes", "delay"], true)
		if not bool(delay_result["valid"]):
			return _failure("invalid_delay", String(delay_result["message"]))
		var delay_minutes := int(delay_result["value"])
		if delay_minutes < 0:
			return _failure("invalid_delay", "Задержка последствия не может быть отрицательной")
		due = _future_stamp(run_state, delay_minutes)
		if due.is_empty():
			return _failure("future_time_failed", "Не удалось вычислить срок последствия")

	var deferred_count := 0
	for candidate: String in RuleStateAccess.DEFERRED_CONTAINERS:
		var property_name := StringName(candidate)
		if RuleStateAccess.has_property(run_state, property_name):
			var value: Variant = run_state.get(property_name)
			if value is Array:
				deferred_count = value.size()
				break
	var deferred_id := String(effect.get("deferred_id", "")).strip_edges()
	var source_id := String(effect.get("source_id", context.get("action_id", ""))).strip_edges()
	if deferred_id.is_empty():
		deferred_id = _generated_deferred_id(effect_id, due, deferred_count, context)
	if not run_state.has_method("schedule_consequence"):
		return _failure(
			"deferred_not_supported",
			"RunState не реализует schedule_consequence()"
		)
	var scheduled: Variant = run_state.call(
		"schedule_consequence",
		deferred_id,
		due,
		effect_id,
		payload.duplicate(true),
		source_id
	)
	if scheduled is bool and not scheduled:
		return _failure(
			"deferred_schedule_failed",
			"Не удалось запланировать последствие «%s»" % effect_id
		)
	var record_after := {
		"id": deferred_id,
		"due": due.duplicate(true),
		"effect_id": effect_id,
		"payload": payload.duplicate(true),
		"source_id": source_id,
	}
	return _success(_record(
		"deferred",
		"deferred_consequence",
		deferred_id,
		null,
		record_after,
		null,
		"Запланировано последствие «%s»" % effect_id,
		effect
	))


static func _change_knowledge(run_state: Object, effect: Dictionary) -> Dictionary:
	var identifier := _identifier(effect)
	if identifier.is_empty():
		return _failure("missing_identifier", "Не указан тег знания")
	var amount_result := _integer_field(effect, ["amount", "level", "value"], true)
	if not bool(amount_result["valid"]):
		return _failure("invalid_knowledge", String(amount_result["message"]))
	var current := RuleStateAccess.knowledge_value(run_state, identifier)
	if not bool(current["found"]):
		return _failure("knowledge_not_supported", "RunState не содержит знания")
	var before := int(roundf(float(current["value"])))
	var amount := int(amount_result["value"])
	var mode := String(effect.get("mode", "add")).strip_edges().to_lower().replace("-", "_")
	var after := before
	match mode:
		"add", "advance":
			if amount <= 0:
				return _failure("invalid_knowledge", "Прирост знания должен быть положительным")
			after = mini(before + amount, 3)
		"unlock":
			after = maxi(before, maxi(amount, 1))
			after = mini(after, 3)
		"set":
			after = amount
		"remove":
			if amount <= 0:
				return _failure("invalid_knowledge", "Снижение знания должно быть положительным")
			after = maxi(0, before - amount)
		_:
			return _failure("invalid_knowledge_mode", "Неизвестный режим знания: %s" % mode)
	if after < 0 or after > 3:
		return _failure("invalid_knowledge", "Уровень знания должен быть от 0 до 3")
	var container := RuleStateAccess.find_dictionary(run_state, RuleStateAccess.KNOWLEDGE_CONTAINERS)
	var dictionary: Dictionary = container["value"]
	var key: Variant = current.get("key", identifier)
	if after == 0:
		dictionary.erase(key)
	else:
		var existing: Variant = dictionary.get(key)
		if existing is Dictionary:
			var updated: Dictionary = existing.duplicate(true)
			updated["level"] = after
			dictionary[key] = updated
		else:
			dictionary[key] = after
	run_state.set(StringName(container["name"]), dictionary)
	return _success(_record(
		"knowledge",
		"knowledge",
		identifier,
		before,
		after,
		after - before,
		"Знание %s: уровень %s → %s" % [identifier, before, after],
		effect
	))


static func _write_level(
		run_state: Object,
		container_names: Array,
		current: Dictionary,
		new_level: int,
		field: String
	) -> Dictionary:
	var container := RuleStateAccess.find_dictionary(run_state, container_names)
	if not bool(container["found"]):
		return _failure("container_not_supported", "RunState не содержит требуемые данные")
	var dictionary: Dictionary = container["value"]
	var key: Variant = current["key"]
	var existing: Variant = dictionary.get(key)
	if existing is Dictionary:
		var updated: Dictionary = existing.duplicate(true)
		updated[field] = new_level
		dictionary[key] = updated
	else:
		dictionary[key] = new_level
	run_state.set(StringName(container["name"]), dictionary)
	return {"ok": true}


static func _future_stamp(run_state: Object, delay_minutes: int) -> Dictionary:
	if not run_state.has_method("clone"):
		return {}
	var future_state: Variant = run_state.call("clone")
	if future_state == null or not (future_state is Object):
		return {}
	if not future_state.has_method("advance_time"):
		return {}
	var advanced: Variant = future_state.call("advance_time", delay_minutes, "", {})
	if advanced is bool and not advanced:
		return {}
	return RuleStateAccess.time_snapshot(future_state)


static func _generated_deferred_id(
		effect_id: String,
		due: Dictionary,
		deferred_count: int,
		context: Dictionary
	) -> String:
	var action_id := String(context.get("action_id", "action"))
	var option_id := String(context.get("option_id", "option"))
	var effect_index := int(context.get("effect_index", 0))
	var elapsed := int(due.get("elapsed_minutes", 0))
	return "%s:%s:%s:%s:%s:%s" % [
		action_id,
		option_id,
		effect_id,
		elapsed,
		effect_index,
		deferred_count,
	]


static func _normalized_type(effect: Dictionary) -> String:
	var effect_type := String(effect.get("type", effect.get("kind", ""))).strip_edges().to_lower()
	effect_type = effect_type.replace("-", "_")
	match effect_type:
		"advance_clock", "time":
			return "advance_time"
		"change_meter", "meter":
			return "change_state"
		"money":
			return "change_money"
		"polarity":
			return "shift_polarity"
		"unlock":
			return "unlock_skill"
		"skill":
			return "advance_skill"
		"mastery_points":
			return "mastery"
		"defer", "schedule":
			return "deferred"
		"learn_knowledge", "unlock_knowledge":
			return "knowledge"
	return effect_type


static func _identifier(effect: Dictionary) -> String:
	return String(effect.get("id", effect.get("key", effect.get("name", "")))).strip_edges()


static func _integer_field(
		dictionary: Dictionary,
		field_names: Array,
		allow_zero: bool
	) -> Dictionary:
	for raw_name: Variant in field_names:
		var field_name := String(raw_name)
		if not dictionary.has(field_name):
			continue
		var value: Variant = dictionary[field_name]
		if value is int:
			return {"valid": true, "value": value, "message": ""}
		if value is float and is_equal_approx(value, roundf(value)):
			return {"valid": true, "value": int(roundf(value)), "message": ""}
		return {
			"valid": false,
			"value": 0,
			"message": "Поле %s должно быть целым числом" % field_name,
		}
	return {
		"valid": false,
		"value": 0 if allow_zero else 1,
		"message": "Не найдено числовое поле: %s" % ", ".join(PackedStringArray(field_names)),
	}


static func _record(
		effect_type: String,
		target_kind: String,
		target_id: String,
		before: Variant,
		after: Variant,
		delta: Variant,
		description: String,
		effect: Dictionary
	) -> Dictionary:
	return {
		"effect_type": effect_type,
		"target_kind": target_kind,
		"target_id": target_id,
		"before": _duplicate_variant(before),
		"after": _duplicate_variant(after),
		"delta": _duplicate_variant(delta),
		"description": description,
		"effect": effect.duplicate(true),
	}


static func _duplicate_variant(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _success(change: Dictionary) -> Dictionary:
	return {"ok": true, "code": "ok", "message": "", "change": change}


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "change": {}}


static func _batch_failure(
		code: String,
		message: String,
		failed_index: int,
		changes: Array[Dictionary]
	) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"failed_index": failed_index,
		"changes": changes.duplicate(true),
	}
