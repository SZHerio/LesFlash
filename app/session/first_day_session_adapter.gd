class_name FirstDaySessionAdapter
extends RefCounted

## Compatibility façade between the M2 orchestration API and the M3A session
## contract. New coordinators can use this class without reading legacy fields
## or RunState directly, while the existing M2 UI keeps its public API.

const GameSessionScript := preload("res://app/session/game_session.gd")
const FirstDaySessionScript := preload("res://game/first_day/first_day_session.gd")
const FirstDaySaveScript := preload("res://game/first_day/first_day_save.gd")

var _session: FirstDaySession


func _init(session: FirstDaySession = null) -> void:
	_session = session


static func create(characteristics: Dictionary, seed: int) -> RefCounted:
	var session := FirstDaySessionScript.create(characteristics, seed)
	if session == null:
		return null
	var adapter_script: Script = load("res://app/session/first_day_session_adapter.gd")
	return adapter_script.new(session)


static func load_session(path: String = FirstDaySave.DEFAULT_SAVE_PATH) -> Dictionary:
	var result: Dictionary = FirstDaySaveScript.load_session(path)
	if bool(result.get("ok", false)):
		var adapter_script: Script = load("res://app/session/first_day_session_adapter.gd")
		result["adapter"] = adapter_script.new(result.get("session"))
	return result


func is_valid() -> bool:
	return _session != null and bool(_session.validate().get("ok", false))


func get_phase() -> String:
	return "uninitialized" if _session == null else _session.phase


func get_location_id() -> String:
	return "" if _session == null else _session.location


func get_flow_revision() -> int:
	return 0 if _session == null else _session.flow_revision


func get_active_activity() -> Dictionary:
	return activity_from_legacy(_session)


func get_flow_model() -> Dictionary:
	if _session == null:
		return {}
	return {
		"phase": _session.phase,
		"base_location_id": _session.location,
		"flow_revision": _session.flow_revision,
		"day_completed": _session.day_completed,
		"active_activity": get_active_activity(),
	}


func get_current_event_model() -> Dictionary:
	return {} if _session == null else _session.get_current_event_model()


func get_job_result_model() -> Dictionary:
	if _session == null:
		return {}
	var result: Dictionary = Dictionary(_session.job_state.get("result", {})).duplicate(true)
	return {
		"available": not result.is_empty(),
		"active": bool(_session.job_state.get("active", false)),
		"job_id": String(_session.job_state.get("job_id", "")),
		"score": int(_session.job_state.get("score", 0)),
		"round": int(_session.job_state.get("round_index", 0)),
		"rounds_total": int(_session.job_state.get("rounds_total", 0)),
		"result": result,
		"transaction": Dictionary(result.get("transaction", {})).duplicate(true),
	}


func get_summary_model() -> Dictionary:
	if _session == null:
		return {}
	var shell_status: Dictionary = Dictionary(get_shell_model().get("status", {})).duplicate(true)
	return {
		"day_completed": _session.day_completed,
		"phase": _session.phase,
		"base_location_id": _session.location,
		"biography": _session.biography.duplicate(true),
		"status": shell_status,
	}


func get_shell_model() -> Dictionary:
	if _session == null:
		return {}
	var contract := GameSessionScript.new(
		_session.run_state,
		_session.location,
		get_active_activity()
	)
	contract.set_location_view_model(get_location_model())
	var result: Dictionary = contract.get_shell_model()
	result["flow"] = get_flow_model()
	return result


func get_location_model() -> Dictionary:
	if _session == null:
		return {}
	var map_model: Dictionary = _session.get_map_model()
	var current: Dictionary = {}
	for value in Array(map_model.get("locations", [])):
		if value is Dictionary and String(value.get("id", "")) == _session.location:
			current = Dictionary(value).duplicate(true)
			break
	var actions: Array = []
	for value in Array(map_model.get("events", [])):
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		actions.append({
			"id": String(event.get("id", "")),
			"kind": "event",
			"title": String(event.get("title", event.get("id", "Событие"))),
			"available": bool(event.get("available", false)),
			"reasons": Array(event.get("reasons", [])).duplicate(true),
			"seen": bool(event.get("seen", false)),
			"completed": bool(event.get("completed", false)),
			})
	if bool(map_model.get("job_available", false)):
		var job_completed := (
			_session.job_state.get("result", {}) is Dictionary
			and not Dictionary(_session.job_state.get("result", {})).is_empty()
		)
		var job_reason := "Сегодняшняя смена завершена" if job_completed else ""
		actions.append({
			"id": "recycling_shift",
			"kind": "job",
			"title": "Подработка на сортировке",
			"description": job_reason,
			"available": not job_completed,
			"completed": job_completed,
			"reasons": [] if not job_completed else [{
				"code": "job_completed_today",
				"message": job_reason,
			}],
		})
	var wait_model: Variant = map_model.get("wait_until_evening", {})
	if wait_model is Dictionary and bool(wait_model.get("visible", false)):
		var wait_reason := String(wait_model.get("reason", ""))
		var wait_reasons: Array = Array(wait_model.get("reasons", [])).duplicate(true)
		if not wait_reason.is_empty() and wait_reasons.is_empty():
			wait_reasons.append({"code": "wait_unavailable", "message": wait_reason})
		actions.append({
			"id": "wait_until_evening",
			"kind": "wait",
			"title": String(wait_model.get("title", "Скоротать время до вечера")),
			"description": wait_reason,
			"available": bool(wait_model.get("available", true)),
			"reasons": wait_reasons,
			"minutes": int(wait_model.get("minutes", 0)),
		})
	if bool(map_model.get("shelter_available", false)):
		actions.append({
			"id": "choose_shelter",
			"kind": "shelter",
			"title": "Выбрать ночлег",
			"available": true,
			"reasons": [],
		})
	return {
		"id": _session.location,
		"title": String(current.get("title", _session.location)),
		"description": String(current.get("description", "")),
		"background_key": String(current.get("background_key", "")),
		"tags": Array(current.get("tags", [])).duplicate(true),
		"actions": actions,
		"calendar": Dictionary(map_model.get("calendar", {})).duplicate(true),
	}


func start_new_run(characteristics: Dictionary, seed: int) -> Dictionary:
	return _missing_session() if _session == null else _session.start_new_run(characteristics, seed)


func travel(destination: String, mode: String = "walk") -> Dictionary:
	return _missing_session() if _session == null else _session.travel(destination, mode)


func enter_event(event_id: String) -> Dictionary:
	return _missing_session() if _session == null else _session.enter_event(event_id)


func select_event(event_id: String = "") -> Dictionary:
	return _missing_session() if _session == null else _session.select_event(event_id)


func resolve_choice(choice_id: String) -> Dictionary:
	return _missing_session() if _session == null else _session.resolve_choice(choice_id)


func begin_job(approach: String = "standard") -> Dictionary:
	return _missing_session() if _session == null else _session.begin_job(approach)


func current_job_prompt() -> Dictionary:
	return {} if _session == null else _session.current_job_prompt()


func answer_job(category: String) -> Dictionary:
	return _missing_session() if _session == null else _session.answer_job(category)


func available_shelters() -> Array:
	return [] if _session == null else _session.available_shelters()


func get_wait_until_evening_model() -> Dictionary:
	return {} if _session == null else _session.get_wait_until_evening_model()


func wait_until_evening() -> Dictionary:
	return _missing_session() if _session == null else _session.wait_until_evening()


func choose_shelter(shelter_id: String) -> Dictionary:
	return _missing_session() if _session == null else _session.choose_shelter(shelter_id)


func set_setting(key: String, value: Variant) -> bool:
	return false if _session == null else _session.set_setting(key, value)


func save(path: String = FirstDaySave.DEFAULT_SAVE_PATH) -> Dictionary:
	return _missing_session() if _session == null else FirstDaySaveScript.save_session(_session, path)


static func activity_from_legacy(session: Object) -> Dictionary:
	if session == null:
		return GameSessionScript.empty_activity()
	return activity_from_fields(
		String(session.get("phase")),
		String(session.get("location")),
		String(session.get("current_event")),
		String(session.get("start")),
		Dictionary(session.get("job_state"))
	)


static func activity_from_serialized(data: Dictionary) -> Dictionary:
	return activity_from_fields(
		String(data.get("phase", "")),
		String(data.get("location", "")),
		String(data.get("current_event", "")),
		String(data.get("start", "")),
		Dictionary(data.get("job_state", {}))
	)


static func activity_from_fields(
	phase: String,
	location: String,
	current_event: String,
	start: String,
	job_state: Dictionary
) -> Dictionary:
	match phase:
		"start":
			return {"kind": "event", "id": start, "snapshot": {"legacy_phase": "start"}}
		"event":
			return {"kind": "event", "id": current_event, "snapshot": {"legacy_phase": "event"}}
		"job":
			return {
				"kind": "job",
				"id": String(job_state.get("job_id", "")),
				"snapshot": job_state.duplicate(true),
			}
		"shelter":
			return {
				"kind": "shelter",
				"id": "%s:shelter" % location,
				"snapshot": {"legacy_phase": "shelter"},
			}
		_:
			return GameSessionScript.empty_activity()


static func values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not values_equal(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not values_equal(left[index], right[index]):
				return false
		return true
	return left == right


func _missing_session() -> Dictionary:
	return {"ok": false, "code": "missing_session", "error": "FirstDaySession is not attached."}
