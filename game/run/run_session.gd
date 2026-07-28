class_name RunSession
extends RefCounted

## Serializable orchestration for the complete first-day vertical slice.
## RunState changes are committed only through ActionTransaction. Flow changes
## are applied after a successful transaction and carry their own revision.

const SESSION_VERSION := 8
const VALID_PHASES := ["uninitialized", "start", "map", "event", "shelter", "completed"]
const VALID_PSYCHE_MODES := ["off", "reduced", "full"]
const FIRST_DAY_DURATION_MINUTES := 24 * 60
const SHELTER_EVENING_MINUTE := 18 * 60
const SHELTER_WAKE_MINUTE := 8 * 60

const M2SessionMigrationScript := preload("res://game/run/run_session_migration.gd")
const SearchSessionStateScript := preload("res://game/search/search_session_state.gd")
const WorldStateScript := preload("res://core/world/world_state.gd")
const SocialStateScript := preload("res://core/social/social_state.gd")
const SurvivalStateScript := preload("res://game/survival/survival_state.gd")
const JobWorkStateScript := preload("res://game/jobs/job_work_state.gd")
const SystemBootstrapScript := preload("res://game/run/run_system_bootstrap.gd")
const SessionCommandBridgeScript := preload("res://game/run/run_session_command_bridge.gd")
const PsycheScaleScript := preload("res://core/state/psyche_scale.gd")

const DEFERRED_PAYLOADS := {
	"cold_symptoms": {"health": -5},
	"local_recognition": {"location_id": "underpass"},
	"stomach_upset": {"energy": -8, "tension": 4},
	"owner_remembers_help": {"location_id": "market"},
	"muscle_soreness": {"energy": -5},
	"owner_favor": {"money": 60},
	"shift_offer": {"location_id": "recycling_point"},
	"blister_worsens": {"health": -6, "energy": -4},
	"fisher_remembers": {"location_id": "embankment"},
	"cold_night": {"health": -8, "energy": -4},
}

var run_state: RunState = RunState.new()
var world_state: WorldState = WorldStateScript.new()
var social_state: SocialState = SocialStateScript.fresh()
var survival_state: SurvivalState = SurvivalStateScript.fresh()
var job_work_state: JobWorkState = JobWorkStateScript.fresh()
var applied_command_ids: Dictionary = {}
var phase: String = "uninitialized"
var location: String = ""
var current_event: String = ""
var start: String = ""
var seen: Array = []
var completed: Array = []
var settings: Dictionary = _default_settings()
var day_completed: bool = false
var biography: Array = []
var flow_revision: int = 0
var active_activity: Dictionary = SearchSessionStateScript.empty_activity()
var search_zone_states: Dictionary = {}


static func create(characteristics: Dictionary, seed: int) -> RunSession:
	var session := RunSession.new()
	var result := session.start_new_run(characteristics, seed)
	return session if bool(result.get("ok", false)) else null


static func create_location_first(characteristics: Dictionary, seed: int) -> RunSession:
	var session := RunSession.new()
	var result := session.start_new_location_first(characteristics, seed)
	return session if bool(result.get("ok", false)) else null


func start_new_location_first(
	characteristics: Dictionary = GameRules.DEFAULT_CHARACTERISTICS,
	seed: int = GameRules.DEFAULT_RNG_SEED
) -> Dictionary:
	var result := start_new_run(characteristics, seed)
	if not bool(result.get("ok", false)):
		return result
	if not current_event.is_empty():
		seen.erase(current_event)
	current_event = ""
	phase = "map"
	result["phase"] = phase
	result["event_id"] = ""
	return result


func start_new_run(
	characteristics: Dictionary = GameRules.DEFAULT_CHARACTERISTICS,
	seed: int = GameRules.DEFAULT_RNG_SEED
) -> Dictionary:
	if not GameRules.characteristics_use_budget(characteristics):
		return _failure("invalid_characteristics", "Характеристики должны быть от 1 до 10 и давать ровно 18 очков")
	var content_validation := _content_validation()
	if not bool(content_validation.get("ok", false)):
		return _failure("invalid_content", "Контент первого дня не прошёл проверку", {"validation": content_validation})

	var starts := _start_situations()
	if starts.is_empty():
		return _failure("missing_start_situations", "Не найдено ни одной стартовой ситуации")
	var candidate_state := RunState.new(characteristics, seed)
	var system_bootstrap := SystemBootstrapScript.create_world(candidate_state)
	if not bool(system_bootstrap.get("ok", false)):
		return _failure(
			String(system_bootstrap.get("code", "world_bootstrap_failed")),
			String(system_bootstrap.get("error", "Не удалось создать начальное состояние мира")),
			{"errors": Array(system_bootstrap.get("errors", [])).duplicate(true)}
		)
	var candidate_world: WorldState = system_bootstrap["world_state"]
	var chosen_start := RunWeightedChoice.start_situation(starts, candidate_state)
	if chosen_start.is_empty():
		return _failure("start_selection_failed", "Не удалось выбрать стартовую ситуацию")

	var start_action := {
		"id": "first_day_start:%s" % String(chosen_start.get("id", "unknown")),
		"title": String(chosen_start.get("title", "Начало пути")),
		"journal_message": String(chosen_start.get("journal_message", chosen_start.get("title", "Первый день начался"))),
		"conditions": ContentShape.array_copy(chosen_start.get("conditions", [])),
		"effects": ContentShape.array_copy(chosen_start.get("effects", chosen_start.get("initial_effects", []))),
		"journal_payload": {"start_id": String(chosen_start.get("id", ""))},
	}
	var transaction := ActionTransaction.execute(candidate_state, start_action, {"phase": "start"})
	if not transaction.success:
		return _transaction_failure(transaction)

	var chosen_location := String(chosen_start.get("location_id", chosen_start.get("location", "")))
	if chosen_location.is_empty() or _location(chosen_location).is_empty():
		return _failure("invalid_start_location", "Стартовая ситуация указывает неизвестную локацию")
	var opening_card := String(chosen_start.get("opening_card_id", chosen_start.get("opening_event_id", chosen_start.get("event_id", ""))))
	if not opening_card.is_empty() and _event_card(opening_card).is_empty():
		return _failure("invalid_opening_event", "Стартовая ситуация указывает неизвестное событие")

	run_state = candidate_state
	world_state = candidate_world
	social_state = SocialStateScript.fresh()
	survival_state = SurvivalStateScript.fresh(candidate_state.calendar.elapsed_minutes)
	job_work_state = JobWorkStateScript.fresh()
	applied_command_ids = {}
	phase = "event" if not opening_card.is_empty() else ("start" if not ContentShape.choices_of(chosen_start).is_empty() else "map")
	location = chosen_location
	current_event = opening_card
	start = String(chosen_start.get("id", ""))
	seen = []
	completed = []
	if not opening_card.is_empty():
		seen.append(opening_card)
	settings = _default_settings()
	day_completed = false
	biography = []
	flow_revision = 1
	active_activity = SearchSessionStateScript.empty_activity()
	search_zone_states = {}
	return _success({
		"start_id": start,
		"location_id": location,
		"phase": phase,
		"event_id": current_event,
		"transaction": transaction.to_dict(),
	})


func get_active_activity() -> Dictionary:
	if is_search_active():
		return active_activity.duplicate(true)
	return M2SessionMigrationScript.legacy_activity({
		"phase": phase,
		"location": location,
		"current_event": current_event,
		"start": start,
	})


func is_search_active() -> bool:
	return String(active_activity.get("kind", "")) == SearchSessionStateScript.SEARCH_KIND


func standard_action_guard() -> Dictionary:
	if not is_search_active():
		return _success()
	return _failure(
		"search_active",
		"Сначала завершите или покиньте текущий поиск",
		{"active_activity": active_activity.duplicate(true)}
	)


func replace_search_state(
	next_activity: Dictionary,
	next_zone_states: Dictionary
) -> Dictionary:
	var normalized := SearchSessionStateScript.normalize_activity(next_activity)
	if normalized.is_empty():
		return _failure("invalid_active_activity", "Состояние текущего поиска повреждено")
	var validation := SearchSessionStateScript.validate(normalized, next_zone_states)
	if not bool(validation.get("ok", false)):
		return _failure(
			"invalid_search_session_state",
			"Состояние поисковой зоны не прошло проверку",
			{"validation": validation}
		)
	var normalized_zones := SearchSessionStateScript.normalized_zone_states(next_zone_states)
	if String(normalized.get("kind", "")) == SearchSessionStateScript.SEARCH_KIND:
		if day_completed or phase != "map":
			return _failure(
				"invalid_search_phase",
				"Поиск можно продолжать только поверх карты активной попытки"
			)
	if active_activity == normalized and search_zone_states == normalized_zones:
		return _success({"changed": false})
	active_activity = normalized
	search_zone_states = normalized_zones
	_touch()
	return _success({"changed": true, "flow_revision": flow_revision})


func get_flow_model() -> Dictionary:
	return {
		"phase": phase,
		"base_location_id": location,
		"flow_revision": flow_revision,
		"day_completed": day_completed,
		"active_activity": get_active_activity(),
	}


func get_map_model() -> Dictionary:
	var location_models: Array = []
	for raw_location in _locations():
		var location_id := String(raw_location.get("id", ""))
		if location_id.is_empty():
			continue
		location_models.append({
			"id": location_id,
			"title": String(raw_location.get("title", location_id)),
			"description": String(raw_location.get("description", "")),
			"background_key": String(raw_location.get("background_key", raw_location.get("background_id", ""))),
			"tags": ContentShape.array_copy(raw_location.get("tags", [])),
			"current": location_id == location,
		})

	var routes: Array = []
	for route in _routes_from(location):
		var destination := String(route.get("to", route.get("destination_id", route.get("destination", ""))))
		if destination.is_empty():
			continue
		var modes := _route_modes(route)
		for mode in modes:
			var requirements := _combined_conditions(route, mode)
			var check := CheckResolver.evaluate_all(run_state, requirements, {
				"action": "travel",
				"from": location,
				"to": destination,
			})
			routes.append({
				"route_id": String(route.get("id", "%s_to_%s" % [location, destination])),
				"destination_id": destination,
				"destination_title": String(_location(destination).get("title", destination)),
				"mode": String(mode.get("id", mode.get("mode", "walk"))),
				"mode_title": String(mode.get("title", mode.get("label", "Пешком"))),
				"minutes": _travel_minutes(route, mode),
				"available": bool(check["allowed"]),
				"reasons": ContentShape.array_copy(check["reasons"]),
			})

	var local_events: Array = []
	for card in _events_for_location(location):
		var event_id := String(card.get("id", ""))
		var check := CheckResolver.evaluate_all(run_state, ContentShape.array_copy(card.get("conditions", [])))
		local_events.append({
			"id": event_id,
			"title": String(card.get("title", event_id)),
			"available": bool(check["allowed"]),
			"reasons": ContentShape.array_copy(check["reasons"]),
			"seen": event_id in seen,
			"completed": event_id in completed,
		})
	return {
		"phase": phase,
		"current_location_id": location,
		"locations": location_models,
		"routes": routes,
		"events": local_events,
		"shelter_available": not available_shelters().is_empty(),
		"wait_until_evening": get_wait_until_evening_model(),
		"calendar": run_state.calendar.current_stamp(),
	}


func enter_event(event_id: String) -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	if day_completed or phase not in ["map", "event"]:
		return _failure("invalid_phase", "Сейчас нельзя открыть событие")
	var card := _event_card(event_id)
	if card.is_empty():
		return _failure("unknown_event", "Событие не найдено")
	if bool(card.get("once", true)) and event_id in completed:
		return _failure("event_completed", "Это событие уже завершено")
	if not _event_belongs_to_location(card, location):
		return _failure("event_not_here", "Это событие недоступно в текущей локации")
	var check := CheckResolver.evaluate_all(run_state, ContentShape.array_copy(card.get("conditions", [])), {"event_id": event_id})
	if not bool(check["allowed"]):
		return _failure("event_blocked", "Событие сейчас недоступно", {"reasons": ContentShape.array_copy(check["reasons"])})
	current_event = event_id
	phase = "event"
	if event_id not in seen:
		seen.append(event_id)
	_touch()
	return _success({"event": get_current_event_model()})


func select_event(event_id: String = "") -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	if not event_id.is_empty():
		return enter_event(event_id)
	var candidates: Array = []
	for card in _events_for_location(location):
		var card_id := String(card.get("id", ""))
		if card_id.is_empty() or (bool(card.get("once", true)) and card_id in completed):
			continue
		var check := CheckResolver.evaluate_all(run_state, ContentShape.array_copy(card.get("conditions", [])))
		if bool(check["allowed"]):
			candidates.append(card)
	if candidates.is_empty():
		return _failure("no_event_available", "В этой локации сейчас нет доступных событий")
	var unseen: Array = []
	for card in candidates:
		if String(card.get("id", "")) not in seen:
			unseen.append(card)
	var pool := unseen if not unseen.is_empty() else candidates
	var chosen := RunWeightedChoice.event_card(pool, "event:%s:%d" % [location, seen.size()], run_state)
	return enter_event(String(chosen.get("id", "")))


func get_current_event_model() -> Dictionary:
	var card := _active_card()
	if card.is_empty():
		return {}
	var options: Array = []
	for option in ContentShape.choices_of(card):
		var conditions := ContentShape.array_copy(option.get("conditions", option.get("requirements", [])))
		var check := CheckResolver.evaluate_all(run_state, conditions, {
			"event_id": String(card.get("id", start)),
			"option_id": String(option.get("id", "")),
		})
		var locked := not bool(check["allowed"])
		if locked and not bool(settings.get("show_locked_options", false)):
			continue
		options.append({
			"id": String(option.get("id", "")),
			"text": String(option.get("text", option.get("label", "Продолжить"))),
			"locked": locked,
			"reasons": ContentShape.array_copy(check["reasons"]) if locked else [],
		})
	var backdrop := _location(location)
	return {
		"id": String(card.get("id", start)),
		"kind": "start" if phase == "start" else "event",
		"title": String(card.get("title", "Событие")),
		"text": String(card.get("text", card.get("description", ""))),
		"location_id": location,
		"location_title": String(backdrop.get("title", location)),
		"background_key": String(backdrop.get("background_key", backdrop.get("background_id", ""))),
		"options": options,
	}


func travel(destination: String, mode: String = "walk") -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	if day_completed or phase != "map":
		return _failure("invalid_phase", "Перемещение доступно только с карты")
	var route_match := _find_route(destination, mode)
	if route_match.is_empty():
		return _failure("route_not_found", "Подходящий маршрут не найден")
	var route: Dictionary = route_match["route"]
	var mode_data: Dictionary = route_match["mode"]
	var effects := _combined_effects(route, mode_data)
	if not _has_effect(effects, "advance_time"):
		effects.append({
			"type": "advance_time",
			"minutes": _travel_minutes(route, mode_data),
			"reason": "Дорога: %s → %s" % [location, destination],
		})
	var action := {
		"id": "travel:%s:%s:%s" % [location, destination, mode],
		"title": "Перемещение",
		"option_title": String(mode_data.get("title", mode)),
		"conditions": _combined_conditions(route, mode_data),
		"effects": effects,
		"journal_payload": {"from": location, "to": destination, "mode": mode},
	}
	var transaction := _execute_action_with_due(action, {"phase": phase})
	if not transaction.success:
		return _transaction_failure(transaction)
	var origin := location
	location = destination
	current_event = ""
	phase = "map"
	_touch()
	return _success({
		"from": origin,
		"to": location,
		"transaction": transaction.to_dict(),
		"map": get_map_model(),
	})


func resolve_choice(choice_id: String) -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	if phase not in ["start", "event"]:
		return _failure("invalid_phase", "Сейчас нет события, ожидающего решения")
	var card := _active_card()
	if card.is_empty():
		return _failure("missing_event", "Текущее событие не найдено")
	var choice := _find_by_id(ContentShape.choices_of(card), choice_id)
	if choice.is_empty():
		return _failure("unknown_choice", "Вариант ответа не найден")
	var card_id := String(card.get("id", start))
	var next_card := String(choice.get("next_card_id", choice.get("next_event_id", "")))
	if not next_card.is_empty() and _event_card(next_card).is_empty():
		return _failure("invalid_next_event", "Продолжение события отсутствует")
	var action := {
		"id": "event:%s" % card_id,
		"option_id": choice_id,
		"title": String(card.get("title", "Событие")),
		"option_title": String(choice.get("text", choice.get("label", choice_id))),
		"conditions": ContentShape.array_copy(choice.get("conditions", choice.get("requirements", []))),
		"effects": ContentShape.array_copy(choice.get("effects", [])),
		"journal_payload": {"event_id": card_id, "choice_id": choice_id},
	}
	var transaction := _execute_action_with_due(action, {"phase": phase, "location": location})
	if not transaction.success:
		return _transaction_failure(transaction)
	if phase == "event" and card_id not in completed:
		completed.append(card_id)
	if not next_card.is_empty():
		current_event = next_card
		phase = "event"
		if next_card not in seen:
			seen.append(next_card)
	else:
		current_event = ""
		phase = "map"
	_touch()
	return _success({
		"transaction": transaction.to_dict(),
		"phase": phase,
		"next_event_id": current_event,
		"outcome": String(choice.get("outcome", "")),
	})


func available_shelters() -> Array:
	var result: Array = []
	var time_open := _shelter_window_open()
	for shelter in _shelters():
		if String(shelter.get("location_id", "")) != location:
			continue
		var check := CheckResolver.evaluate_all(
			run_state,
			ContentShape.array_copy(shelter.get("conditions", [])),
			{"shelter_id": String(shelter.get("id", ""))}
		)
		var reasons := ContentShape.array_copy(check["reasons"])
		if not time_open:
			reasons.append({
				"passed": false,
				"code": "shelter_time_closed",
				"message": "Ночлег можно выбрать с 18:00 до 08:00",
				"kind": "time",
				"id": "shelter_window",
				"operator": "window",
				"required": null,
				"actual": run_state.calendar.minute_of_day,
				"condition": {},
			})
		var locked := not reasons.is_empty()
		if locked and not bool(settings.get("show_locked_options", false)):
			continue
		result.append({
			"id": String(shelter.get("id", "")),
			"title": String(shelter.get("title", "Ночлег")),
			"description": String(shelter.get("description", "")),
			"risk": int(shelter.get("risk", 0)),
			"quality": int(shelter.get("quality", 0)),
			"locked": locked,
			"reasons": reasons if locked else [],
		})
	return result


func get_wait_until_evening_model() -> Dictionary:
	var target_elapsed := SHELTER_EVENING_MINUTE - SHELTER_WAKE_MINUTE
	var elapsed := int(run_state.calendar.elapsed_minutes) if run_state != null and run_state.calendar != null else 0
	var visible := not day_completed and phase == "map" and elapsed < target_elapsed
	var available := visible and completed.size() >= 3
	var reason := ""
	if visible and not available:
		reason = "Сначала завершите дело или проведите время за другими занятиями"
	return {
		"visible": visible,
		"available": available,
		"minutes": maxi(target_elapsed - elapsed, 0),
		"reason": reason,
	}


func wait_until_evening() -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	var model := get_wait_until_evening_model()
	if not bool(model.get("visible", false)):
		return _failure("evening_wait_unavailable", "Сейчас ждать вечера уже не нужно")
	if not bool(model.get("available", false)):
		return _failure("evening_wait_not_earned", String(model.get("reason", "День ещё не сложился")))
	var minutes := int(model.get("minutes", 0))
	if minutes <= 0:
		return _failure("evening_wait_unavailable", "Вечер уже наступил")
	var hunger_cost := clampi(int(ceil(float(minutes) / 30.0)), 4, 18)
	var action := {
		"id": "first_day:wait_until_evening",
		"title": "Ожидание вечера",
		"option_title": "Скоротать остаток дня",
		"conditions": [],
		"effects": [
			{"type": "advance_time", "minutes": minutes, "reason": "Ожидание вечера"},
			{"type": "change_state", "id": "hunger", "delta": hunger_cost},
			{"type": "change_state", "id": "energy", "delta": 6},
			{"type": "change_state", "id": "tension", "delta": -5},
		],
		"journal_payload": {"minutes": minutes, "location_id": location},
	}
	var transaction := _execute_action_with_due(action, {"phase": phase, "location": location})
	if not transaction.success:
		return _transaction_failure(transaction)
	_touch()
	return _success({
		"transaction": transaction.to_dict(),
		"map": get_map_model(),
		"outcome": "Вы скоротали время до 18:00. Отдых немного восстановил силы, но голод усилился.",
	})


func choose_shelter(shelter_id: String) -> Dictionary:
	var activity_guard := standard_action_guard()
	if not bool(activity_guard.get("ok", false)):
		return activity_guard
	if day_completed or phase not in ["map", "shelter"]:
		return _failure("invalid_phase", "Сейчас нельзя выбрать ночлег")
	if not _shelter_window_open():
		return _failure("shelter_time_closed", "Ночлег можно выбрать с 18:00 до 08:00")
	var shelter := _find_by_id(_shelters(), shelter_id)
	if shelter.is_empty():
		return _failure("unknown_shelter", "Место ночлега не найдено")
	if String(shelter.get("location_id", "")) != location:
		return _failure("shelter_not_here", "Это место ночлега находится в другой локации")
	var effects: Array = []
	for effect in ContentShape.array_copy(shelter.get("effects", [])):
		if ContentShape.effect_type(effect) != "advance_time":
			effects.append(effect)
	var wake_minute := int(shelter.get("wake_minute", SHELTER_WAKE_MINUTE))
	wake_minute = clampi(wake_minute, 0, run_state.calendar.minutes_per_day - 1)
	var sleep_minutes := posmod(
		wake_minute - run_state.calendar.minute_of_day,
		run_state.calendar.minutes_per_day
	)
	if sleep_minutes == 0:
		sleep_minutes = run_state.calendar.minutes_per_day
	if run_state.calendar.elapsed_minutes + sleep_minutes != FIRST_DAY_DURATION_MINUTES:
		return _failure("first_day_deadline", "Первый день должен завершиться ближайшим утром в 08:00")
	effects.append({
		"type": "advance_time",
		"minutes": sleep_minutes,
		"reason": "Ночлег: %s" % String(shelter.get("title", shelter_id)),
	})
	var action := {
		"id": "shelter:%s" % shelter_id,
		"title": "Ночлег",
		"option_title": String(shelter.get("title", shelter_id)),
		"conditions": ContentShape.array_copy(shelter.get("conditions", [])),
		"effects": effects,
		"journal_payload": {"shelter_id": shelter_id},
	}
	var transaction := _execute_action_with_due(action, {"phase": phase, "location": location}, true)
	if not transaction.success:
		return _transaction_failure(transaction)
	day_completed = true
	phase = "completed"
	current_event = ""
	var biography_entry := _build_biography_entry(shelter, transaction)
	biography.append(biography_entry)
	_touch()
	return _success({
		"day_completed": true,
		"biography": biography_entry.duplicate(true),
		"transaction": transaction.to_dict(),
	})


func psyche_intensity() -> float:
	if String(settings.get("psyche_effect_mode", "full")) == "off":
		return 0.0
	var raw := PsycheScaleScript.filter_for(run_state.get_meter("mental_state"))
	if String(settings.get("psyche_effect_mode", "full")) == "reduced":
		raw *= 0.5
	return raw


func set_setting(key: String, value: Variant) -> bool:
	var candidate := settings.duplicate(true)
	candidate[key] = value
	if not _settings_valid(candidate):
		return false
	if candidate == settings:
		return true
	settings = candidate
	_touch()
	return true


func to_dict() -> Dictionary:
	return {
		"session_version": SESSION_VERSION,
		"run_state": run_state.to_dict(),
		"world_state": world_state.to_dict(),
		"social_state": social_state.to_dict(),
		"survival_state": survival_state.to_dict(),
		"job_work_state": job_work_state.to_dict(),
		"applied_command_ids": applied_command_ids.duplicate(true),
		"base_location": location,
		"active_activity": active_activity.duplicate(true),
		"search_zone_states": search_zone_states.duplicate(true),
		"phase": phase,
		"location": location,
		"current_event": current_event,
		"start": start,
		"seen": seen.duplicate(true),
		"completed": completed.duplicate(true),
		"settings": settings.duplicate(true),
		"day_completed": day_completed,
		"biography": biography.duplicate(true),
		"flow_revision": flow_revision,
	}


static func from_dict(data: Dictionary) -> RunSession:
	var migration := M2SessionMigrationScript.migrate_session(data)
	if not bool(migration.get("ok", false)):
		return null
	var source: Dictionary = migration["data"]
	var version: Variant = _integral(source.get("session_version", null))
	var revision: Variant = _integral(source.get("flow_revision", null))
	# Every older shape has already been migrated above, so anything that is not
	# the current version here is a save the migrator refused to understand.
	if version == null or int(version) != SESSION_VERSION or revision == null or int(revision) < 0:
		return null
	if typeof(source.get("run_state", null)) != TYPE_DICTIONARY:
		return null
	var parsed_state := RunState.from_dict(source["run_state"])
	if parsed_state == null:
		return null
	if typeof(source.get("world_state", null)) != TYPE_DICTIONARY or typeof(source.get("social_state", null)) != TYPE_DICTIONARY or typeof(source.get("survival_state", null)) != TYPE_DICTIONARY or typeof(source.get("applied_command_ids", null)) != TYPE_DICTIONARY:
		return null
	var parsed_world := WorldStateScript.from_dict(source["world_state"])
	var parsed_social := SocialStateScript.from_dict(source["social_state"])
	if not source.has("job_work_state"):
		source["job_work_state"] = JobWorkStateScript.fresh().to_dict()
	var parsed_job: JobWorkState = JobWorkStateScript.from_dict(source["job_work_state"])
	if parsed_job == null:
		return null
	var parsed_survival := SurvivalStateScript.from_dict(source["survival_state"])
	if parsed_world == null or parsed_social == null or parsed_survival == null:
		return null
	for key in ["phase", "location", "current_event", "start"]:
		if typeof(source.get(key, null)) != TYPE_STRING:
			return null
	if typeof(source.get("day_completed", null)) != TYPE_BOOL:
		return null
	if typeof(source.get("seen", null)) != TYPE_ARRAY or typeof(source.get("completed", null)) != TYPE_ARRAY:
		return null
	if typeof(source.get("settings", null)) != TYPE_DICTIONARY:
		return null
	if typeof(source.get("biography", null)) != TYPE_ARRAY:
		return null
	var parsed_activity := SearchSessionStateScript.normalize_activity(
		source.get("active_activity", null)
	)
	if parsed_activity.is_empty() or typeof(source.get("search_zone_states", null)) != TYPE_DICTIONARY:
		return null
	var parsed_zone_states := SearchSessionStateScript.normalized_zone_states(
		Dictionary(source["search_zone_states"])
	)
	var parsed_seen: Variant = _string_array(source["seen"])
	var parsed_completed: Variant = _string_array(source["completed"])
	if parsed_seen == null or parsed_completed == null:
		return null
	var result := RunSession.new()
	result.run_state = parsed_state
	result.world_state = parsed_world
	result.social_state = parsed_social
	result.survival_state = parsed_survival
	result.job_work_state = parsed_job
	result.applied_command_ids = SerializedValue.normalize_json_numbers(
		Dictionary(source["applied_command_ids"]).duplicate(true)
	)
	result.phase = String(source["phase"])
	result.location = String(source["location"])
	result.current_event = String(source["current_event"])
	result.start = String(source["start"])
	result.seen = parsed_seen
	result.completed = parsed_completed
	result.settings = Dictionary(source["settings"]).duplicate(true)
	result.day_completed = bool(source["day_completed"])
	result.biography = SerializedValue.normalize_json_numbers(Array(source["biography"]).duplicate(true))
	result.flow_revision = int(revision)
	result.active_activity = parsed_activity
	result.search_zone_states = parsed_zone_states
	var validation := result.validate()
	return result if bool(validation["ok"]) else null


func clone() -> RunSession:
	return RunSession.from_dict(to_dict())


func replace_from(other: RunSession) -> bool:
	if other == null:
		return false
	var candidate := RunSession.from_dict(other.to_dict())
	if candidate == null:
		return false
	run_state = candidate.run_state
	world_state = candidate.world_state
	social_state = candidate.social_state
	survival_state = candidate.survival_state
	job_work_state = candidate.job_work_state
	applied_command_ids = candidate.applied_command_ids
	phase = candidate.phase
	location = candidate.location
	current_event = candidate.current_event
	start = candidate.start
	seen = candidate.seen
	completed = candidate.completed
	settings = candidate.settings
	day_completed = candidate.day_completed
	biography = candidate.biography
	flow_revision = candidate.flow_revision
	active_activity = candidate.active_activity
	search_zone_states = candidate.search_zone_states
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	var start_data: Dictionary = {}
	if run_state == null:
		errors.append("run_state is null")
	else:
		_append_validation("run_state", run_state.validate(), errors)
		# RunState owns a generic, data-only deferred queue. An effect unknown to
		# the legacy M2 resolver is still a cloneable/saveable queue record; it is
		# rejected atomically with deferred_resolution_failed only when it becomes
		# due. Eager M2-specific validation here would prevent the common session
		# transaction from cloning the aggregate and hide the real domain error as
		# session_clone_failed.
	if world_state == null:
		errors.append("world_state is null")
	else:
		_append_validation("world_state", world_state.validate(), errors)
	if social_state == null:
		errors.append("social_state is null")
	else:
		_append_validation("social_state", social_state.validate(), errors)
	if job_work_state == null:
		errors.append("job_work_state is null")
	else:
		_append_validation("job_work_state", job_work_state.validate(), errors)
	if survival_state == null:
		errors.append("survival_state is null")
	else:
		_append_validation("survival_state", survival_state.validate(), errors)
		if run_state != null and run_state.calendar != null and survival_state.processed_elapsed_minutes != run_state.calendar.elapsed_minutes:
			errors.append("survival_state and calendar are desynchronized")
	_validate_applied_commands(errors)
	if phase not in VALID_PHASES:
		errors.append("phase is unknown: %s" % phase)
	if phase != "uninitialized":
		if location.is_empty() or _location(location).is_empty():
			errors.append("location is missing from DistrictContent")
		start_data = _find_by_id(_start_situations(), start)
		if start.is_empty() or start_data.is_empty():
			errors.append("start is missing from DistrictContent")
	if phase == "event":
		var event_card := _event_card(current_event)
		if current_event.is_empty() or event_card.is_empty():
			errors.append("event phase requires a valid current_event")
		elif not _event_belongs_to_location(event_card, location):
			errors.append("current_event does not belong to the current location")
		if current_event in completed:
			errors.append("current_event cannot already be completed")
	elif not current_event.is_empty():
		errors.append("current_event must be empty outside event phase")
	if phase == "start":
		if start_data.is_empty():
			errors.append("start phase requires a valid start situation")
		elif String(start_data.get("location_id", "")) != location:
			errors.append("start phase must remain in its configured location")
	_validate_unique_strings(seen, "seen", errors)
	_validate_unique_strings(completed, "completed", errors)
	for event_id in seen:
		if _event_card(String(event_id)).is_empty():
			errors.append("seen contains unknown event %s" % String(event_id))
	if not current_event.is_empty() and current_event not in seen:
		errors.append("current_event must also be present in seen")
	for event_id in completed:
		if _event_card(String(event_id)).is_empty():
			errors.append("completed contains unknown event %s" % String(event_id))
		if event_id not in seen:
			errors.append("completed event %s was never seen" % String(event_id))
	if not _settings_valid(settings):
		errors.append("settings are invalid")
	if day_completed != (phase == "completed"):
		errors.append("day_completed and completed phase disagree")
	if run_state != null and phase != "uninitialized":
		var elapsed := int(run_state.calendar.elapsed_minutes)
		if day_completed and elapsed != FIRST_DAY_DURATION_MINUTES:
			errors.append("completed first day must end exactly at the next 08:00")
	if flow_revision < 0:
		errors.append("flow_revision cannot be negative")
	var search_validation := SearchSessionStateScript.validate(
		active_activity,
		search_zone_states
	)
	_append_validation("search_session", search_validation, errors)
	if is_search_active() and phase != "map":
		errors.append("active search requires map phase")
	var contract_validation := M2SessionMigrationScript.validate_contract_fields({
		"run_state": run_state.to_dict() if run_state != null else {},
		"phase": phase,
		"location": location,
		"base_location": location,
		"current_event": current_event,
		"start": start,
		"world_state": world_state.to_dict() if world_state != null else {},
		"social_state": social_state.to_dict() if social_state != null else {},
		"survival_state": survival_state.to_dict() if survival_state != null else {},
		"applied_command_ids": applied_command_ids.duplicate(true),
		"active_activity": active_activity,
		"search_zone_states": search_zone_states,
	})
	if not bool(contract_validation.get("ok", false)):
		errors.append("M3A session contract: %s" % String(contract_validation.get("error", "invalid")))
	SerializedValue.validate_json_value(biography, "biography", errors)
	var content_validation := _content_validation()
	if not bool(content_validation.get("ok", false)):
		_append_validation("content", content_validation, errors)
	return {"ok": errors.is_empty(), "errors": errors}


func _validate_applied_commands(errors: Array[String]) -> void:
	for raw_id: Variant in applied_command_ids:
		var command_id := String(raw_id).strip_edges()
		var record: Variant = applied_command_ids[raw_id]
		if typeof(raw_id) != TYPE_STRING or command_id.is_empty() or not record is Dictionary:
			errors.append("applied_command_ids contains an invalid record")
			continue
		if typeof(Dictionary(record).get("source_id", null)) != TYPE_STRING:
			errors.append("applied_command_ids.%s.source_id must be a string" % command_id)
		if not Dictionary(record).get("applied_at", null) is Dictionary:
			errors.append("applied_command_ids.%s.applied_at must be a dictionary" % command_id)


func _execute_action_with_due(
	action: Dictionary,
	context: Dictionary,
	completes_day: bool = false
) -> ActionResult:
	return SessionCommandBridgeScript.execute(
		self,
		action,
		context,
		completes_day,
		FIRST_DAY_DURATION_MINUTES
	)


func _resolve_due_consequences(candidate: RunState, context: Dictionary) -> Dictionary:
	var consequences := candidate.take_due_consequences()
	if consequences.is_empty():
		return {"ok": true, "changes": [], "journal_entries": []}
	consequences.sort_custom(_deferred_before)
	var all_changes: Array[Dictionary] = []
	var journal_entries: Array = []
	for consequence_value in consequences:
		var consequence: Dictionary = consequence_value
		var consequence_id := String(consequence.get("id", ""))
		var effect_id := String(consequence.get("effect_id", ""))
		var conversion := _deferred_effects(consequence)
		if not bool(conversion.get("ok", false)):
			return {
				"ok": false,
				"message": "Последствие %s повреждено: %s" % [consequence_id, String(conversion.get("message", "неверные данные"))],
				"changes": all_changes,
				"failed_effect_index": -1,
			}
		var consequence_action := {
			"id": "deferred:%s" % consequence_id,
			"title": "Отложенное последствие",
			"journal_message": "Проявилось отложенное последствие: %s" % effect_id,
			"conditions": [],
			"effects": ContentShape.array_copy(conversion.get("effects", [])),
			"journal_payload": {
				"consequence_id": consequence_id,
				"effect_id": effect_id,
				"source_id": String(consequence.get("source_id", "")),
				"due": Dictionary(consequence.get("due", {})).duplicate(true),
				"scheduled_payload": Dictionary(consequence.get("payload", {})).duplicate(true),
			},
		}
		var consequence_context := context.duplicate(true)
		consequence_context["consequence_id"] = consequence_id
		consequence_context["effect_id"] = effect_id
		var applied := ActionTransaction.execute(candidate, consequence_action, consequence_context)
		if not applied.success:
			return {
				"ok": false,
				"message": "Не удалось применить последствие %s: %s" % [consequence_id, applied.message],
				"changes": all_changes,
				"failed_effect_index": applied.failed_effect_index,
			}
		all_changes.append_array(applied.changes.duplicate(true))
		journal_entries.append(applied.journal_entry.duplicate(true))
	return {"ok": true, "changes": all_changes, "journal_entries": journal_entries}


## M2 consequences keep their fixed payload contract. Consequences queued by
## versioned content are accepted on shape alone, so a new event card does not
## require a code change to schedule its own follow-up.
func _deferred_effects(consequence: Dictionary) -> Dictionary:
	var effect_id := String(consequence.get("effect_id", ""))
	if effect_id.is_empty():
		return _failure("unknown_deferred_effect", "Отложенное последствие без effect_id")
	var payload_value: Variant = consequence.get("payload", null)
	if not payload_value is Dictionary:
		return _failure("invalid_deferred_payload", "payload должен быть словарём")
	var payload: Dictionary = SerializedValue.normalize_json_numbers(payload_value)
	if DEFERRED_PAYLOADS.has(effect_id):
		var expected: Dictionary = Dictionary(DEFERRED_PAYLOADS[effect_id]).duplicate(true)
		if payload != expected:
			return _failure("invalid_deferred_payload", "payload не соответствует контракту %s" % effect_id)
	elif payload.is_empty():
		return _failure("invalid_deferred_payload", "payload последствия %s пуст" % effect_id)
	var effects: Array = []
	for key_value in payload:
		var key := String(key_value)
		if key == "location_id":
			effects.append({"type": "knowledge", "id": effect_id, "amount": 1, "mode": "unlock"})
		elif key == "money":
			effects.append({"type": "change_money", "delta": int(payload[key_value])})
		elif GameRules.is_known_meter(key):
			effects.append({"type": "change_state", "id": key, "delta": int(payload[key_value])})
		else:
			return _failure("invalid_deferred_payload", "Неподдерживаемое поле payload: %s" % key)
	return _success({"effects": effects})


func _shelter_window_open() -> bool:
	if run_state == null or run_state.calendar == null:
		return false
	if run_state.calendar.elapsed_minutes < 0 or run_state.calendar.elapsed_minutes >= FIRST_DAY_DURATION_MINUTES:
		return false
	var minute := int(run_state.calendar.minute_of_day)
	return minute >= SHELTER_EVENING_MINUTE or minute < SHELTER_WAKE_MINUTE


static func _deferred_before(left: Dictionary, right: Dictionary) -> bool:
	var comparison := GameCalendar.compare_stamps(
		Dictionary(left.get("due", {})),
		Dictionary(right.get("due", {}))
	)
	if comparison != 0:
		return comparison < 0
	return String(left.get("id", "")) < String(right.get("id", ""))


func _active_card() -> Dictionary:
	if phase == "start":
		return _find_by_id(_start_situations(), start)
	if phase == "event":
		return _event_card(current_event)
	return {}


func _find_route(destination: String, requested_mode: String) -> Dictionary:
	for route in _routes_from(location):
		var route_destination := String(route.get("to", route.get("destination_id", route.get("destination", ""))))
		if route_destination != destination:
			continue
		for mode in _route_modes(route):
			var mode_id := String(mode.get("id", mode.get("mode", "walk")))
			if mode_id == requested_mode:
				return {"route": route, "mode": mode}
	return {}


func _route_modes(route: Dictionary) -> Array:
	var explicit := ContentShape.dictionary_array(route.get("modes", []))
	if not explicit.is_empty():
		return explicit
	if route.has("mode"):
		return [{
			"id": String(route.get("mode", "walk")),
			"title": String(route.get("mode_title", route.get("title", "Пешком"))),
			"minutes": int(route.get("minutes", route.get("duration_minutes", 0))),
			"conditions": ContentShape.array_copy(route.get("mode_conditions", [])),
			"effects": ContentShape.array_copy(route.get("mode_effects", [])),
		}]
	var result: Array = [{
		"id": "walk",
		"title": "Пешком",
		"minutes": int(route.get("walk_minutes", route.get("minutes", 0))),
		"conditions": [],
		"effects": [],
	}]
	if route.has("bus_minutes"):
		var fare := int(route.get("fare", 0))
		var bus_conditions: Array = []
		var bus_effects: Array = []
		if fare > 0:
			bus_conditions.append({"kind": "money", "value": fare, "operator": ">="})
			bus_effects.append({"type": "change_money", "delta": -fare})
		result.append({
			"id": "bus",
			"title": "Автобус",
			"minutes": int(route["bus_minutes"]),
			"conditions": bus_conditions,
			"effects": bus_effects,
		})
	return result


func _travel_minutes(route: Dictionary, mode: Dictionary) -> int:
	var minutes := int(mode.get("minutes", mode.get("duration_minutes", 0)))
	if minutes <= 0:
		minutes = int(route.get("minutes", route.get("walk_minutes", route.get("duration_minutes", 1))))
	if mode.has("time_multiplier"):
		minutes = ceili(float(minutes) * float(mode["time_multiplier"]))
	return maxi(minutes, 1)


func _combined_conditions(first: Dictionary, second: Dictionary) -> Array:
	var result := ContentShape.array_copy(first.get("conditions", first.get("requirements", [])))
	result.append_array(ContentShape.array_copy(second.get("conditions", second.get("requirements", []))))
	return result


func _combined_effects(first: Dictionary, second: Dictionary) -> Array:
	var result := ContentShape.array_copy(first.get("effects", []))
	result.append_array(ContentShape.array_copy(second.get("effects", [])))
	return result


func _build_biography_entry(shelter: Dictionary, transaction: ActionResult) -> Dictionary:
	var start_data := _find_by_id(_start_situations(), start)
	return {
		"id": "day_one",
		"title": "Первый день",
		"summary": "Первый день начался в «%s» и завершился ночлегом в «%s»." % [
			String(_location(String(start_data.get("location_id", location))).get("title", location)),
			String(shelter.get("title", "неизвестном месте")),
		],
		"start_id": start,
		"shelter_id": String(shelter.get("id", "")),
		"seen_events": seen.duplicate(true),
		"completed_events": completed.duplicate(true),
		"final_state": {
			"calendar": run_state.calendar.current_stamp(),
			"money": run_state.money,
			"meters": run_state.meters.duplicate(true),
		},
		"journal_entry": transaction.journal_entry.duplicate(true),
	}


static func _locations() -> Array:
	return ContentShape.dictionary_array(DistrictContent.locations())


## Just the place: its id, its name and its background. Readers that need only
## a caption must not pay for the whole location read-model.
func get_location_summary() -> Dictionary:
	var place := _location(location)
	return {
		"id": location,
		"title": String(place.get("title", location)),
		"background_key": String(place.get("background_key", "")),
	}


static func _location(location_id: String) -> Dictionary:
	var value: Variant = DistrictContent.location(location_id)
	return value.duplicate(true) if value is Dictionary else {}


static func _routes_from(location_id: String) -> Array:
	return ContentShape.dictionary_array(DistrictContent.routes_from(location_id))


static func _start_situations() -> Array:
	return ContentShape.dictionary_array(DistrictContent.start_situations())


static func _event_cards() -> Array:
	return ContentShape.dictionary_array(DistrictContent.event_cards())


static func _event_card(event_id: String) -> Dictionary:
	for card in _event_cards():
		if String(card.get("id", "")) == event_id:
			return card
	return {}


static func _events_for_location(location_id: String) -> Array:
	return ContentShape.dictionary_array(DistrictContent.events_for_location(location_id))


static func _shelters() -> Array:
	return ContentShape.dictionary_array(DistrictContent.shelters())


static func _content_validation() -> Dictionary:
	var raw: Variant = DistrictContentValidator.validate_content()
	if raw is Dictionary:
		return raw.duplicate(true)
	if raw is bool:
		return {"ok": raw, "errors": [] if raw else ["DistrictContent rejected its data"]}
	return {"ok": false, "errors": ["DistrictContentValidator.validate_content returned an invalid value"]}


static func _event_belongs_to_location(card: Dictionary, location_id: String) -> bool:
	if String(card.get("location_id", "")) == location_id:
		return true
	var location_ids: Variant = card.get("location_ids", [])
	return location_ids is Array and location_id in location_ids


static func _find_by_id(values: Array, identifier: String) -> Dictionary:
	for value in values:
		if value is Dictionary and String(value.get("id", value.get("category", ""))) == identifier:
			return value.duplicate(true)
	return {}


static func _typed_dictionary_array(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Array:
		for value in raw:
			if value is Dictionary:
				result.append(value.duplicate(true))
	return result


static func _has_effect(effects: Array, wanted_type: String) -> bool:
	for effect in effects:
		if effect is Dictionary and ContentShape.effect_type(effect) == wanted_type:
			return true
	return false


static func _has_target_effect(effects: Array, wanted_type: String, target_id: String) -> bool:
	for effect in effects:
		if not effect is Dictionary:
			continue
		if ContentShape.effect_type(effect) != wanted_type:
			continue
		if String(effect.get("id", effect.get("key", ""))) == target_id:
			return true
	return false


static func _default_settings() -> Dictionary:
	return {
		"show_locked_options": false,
		"psyche_effect_mode": "full",
		"font_scale": 1.0,
	}


static func _settings_valid(value: Dictionary) -> bool:
	if value.size() != 3:
		return false
	if typeof(value.get("show_locked_options", null)) != TYPE_BOOL:
		return false
	if typeof(value.get("psyche_effect_mode", null)) != TYPE_STRING:
		return false
	if String(value["psyche_effect_mode"]) not in VALID_PSYCHE_MODES:
		return false
	var scale: Variant = value.get("font_scale", null)
	if typeof(scale) != TYPE_INT and typeof(scale) != TYPE_FLOAT:
		return false
	return is_finite(float(scale)) and float(scale) >= 0.8 and float(scale) <= 2.0


static func _string_array(raw: Variant) -> Variant:
	if not raw is Array:
		return null
	var result: Array = []
	for value in raw:
		if typeof(value) != TYPE_STRING or String(value).is_empty():
			return null
		result.append(String(value))
	return result


static func _integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var number := float(value)
	if not is_finite(number) or number != floor(number) or absf(number) > float(GameRules.JSON_SAFE_INTEGER_MAX):
		return null
	return int(number)


static func _validate_unique_strings(values: Array, path: String, errors: Array[String]) -> void:
	var seen_values: Dictionary = {}
	for index in range(values.size()):
		if typeof(values[index]) != TYPE_STRING or String(values[index]).is_empty():
			errors.append("%s[%d] must be a non-empty string" % [path, index])
			continue
		if seen_values.has(values[index]):
			errors.append("%s contains duplicate id %s" % [path, values[index]])
		seen_values[values[index]] = true


static func _append_validation(prefix: String, validation: Dictionary, errors: Array[String]) -> void:
	if bool(validation.get("ok", false)):
		return
	var nested: Variant = validation.get("errors", [])
	if not nested is Array:
		errors.append("%s validation failed" % prefix)
		return
	for error in nested:
		errors.append("%s: %s" % [prefix, String(error)])


func _touch() -> void:
	flow_revision += 1


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "message": ""}
	for key in extra:
		result[key] = extra[key]
	return result


static func _failure(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "message": message}
	for key in extra:
		result[key] = extra[key]
	return result


static func _transaction_failure(transaction: ActionResult) -> Dictionary:
	return _failure(String(transaction.code), transaction.message, {"transaction": transaction.to_dict()})
