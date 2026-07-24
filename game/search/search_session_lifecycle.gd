class_name SearchSessionLifecycle
extends RefCounted

const ZoneCatalog := preload("res://game/search/search_zone_catalog.gd")
const SnapshotGenerator := preload(
	"res://game/search/search_snapshot_generator.gd"
)
const SnapshotValidator := preload(
	"res://game/search/search_snapshot_validator.gd"
)
const SessionTransaction := preload(
	"res://game/search/search_session_transaction.gd"
)


static func begin_search(
	session: Object,
	template_id: String,
	command_id: String
) -> Dictionary:
	var command_check := SessionTransaction.validate_command_id(command_id)
	if not bool(command_check.get("ok", false)):
		return command_check
	var current := SessionTransaction.active_search(session)
	if not current.is_empty():
		var current_snapshot: Dictionary = current["snapshot"]
		if SessionTransaction.was_applied(current_snapshot, command_id):
			return SessionTransaction.duplicate_result(current_snapshot)
		return SessionTransaction.failure(
			"activity_in_progress",
			"Сначала завершите текущее занятие."
		)
	if not _no_activity(session):
		return SessionTransaction.failure(
			"activity_in_progress",
			"Сначала завершите текущее занятие."
		)
	var loaded := ZoneCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return SessionTransaction.failure(
			"search_template_failed",
			"Не удалось загрузить поисковую зону.",
			{"errors": Array(loaded.get("errors", [])).duplicate(true)}
		)
	var template: Dictionary = loaded["template"]
	if template_id != String(template.get("id", "")):
		return SessionTransaction.failure(
			"unknown_search_template",
			"Неизвестная поисковая зона."
		)
	if String(template.get("location_id", "")) != String(session.get("location")):
		return SessionTransaction.failure(
			"search_zone_elsewhere",
			"Эта поисковая зона находится в другом месте."
		)
	var clone_result := SessionTransaction.clone_session(session)
	if not bool(clone_result.get("ok", false)):
		return clone_result
	var candidate: Object = clone_result["candidate"]
	var zones := SessionTransaction.zone_states(candidate)
	var snapshot: Dictionary = Dictionary(zones.get(template_id, {})).duplicate(true)
	if (
		not snapshot.is_empty()
		and SessionTransaction.was_applied(snapshot, command_id)
	):
		return SessionTransaction.duplicate_result(snapshot)
	if snapshot.is_empty():
		var run_state: RunState = candidate.get("run_state")
		var generated := SnapshotGenerator.generate(
			template,
			run_state.rng.seed,
			1,
			_generation_context(run_state)
		)
		if not bool(generated.get("ok", false)):
			return generated
		snapshot = generated["snapshot"]
	else:
		var validation := SnapshotValidator.validate(snapshot, template)
		if not bool(validation.get("ok", false)):
			return SessionTransaction.failure(
				"archived_search_invalid",
				"Сохранённая поисковая зона повреждена.",
				{"validation": validation}
			)
	snapshot = SessionTransaction.mark_applied(snapshot, command_id)
	zones[template_id] = snapshot.duplicate(true)
	var state_result := SessionTransaction.replace_search_state(
		candidate,
		{"kind": "search", "id": template_id, "snapshot": snapshot},
		zones
	)
	if not bool(state_result.get("ok", false)):
		return state_result
	var commit := SessionTransaction.commit(session, candidate)
	if not bool(commit.get("ok", false)):
		return commit
	return _success({"snapshot": snapshot, "template": template})


static func finish_search(session: Object, command_id: String) -> Dictionary:
	var command_check := SessionTransaction.validate_command_id(command_id)
	if not bool(command_check.get("ok", false)):
		return command_check
	var active_result := SessionTransaction.require_active(session)
	if not bool(active_result.get("ok", false)):
		for archived: Variant in SessionTransaction.zone_states(session).values():
			if archived is Dictionary and SessionTransaction.was_applied(
				archived,
				command_id
			):
				return SessionTransaction.duplicate_result(archived)
		return active_result
	var snapshot: Dictionary = active_result["snapshot"]
	if SessionTransaction.was_applied(snapshot, command_id):
		return SessionTransaction.duplicate_result(snapshot)
	var clone_result := SessionTransaction.clone_session(session)
	if not bool(clone_result.get("ok", false)):
		return clone_result
	var candidate: Object = clone_result["candidate"]
	snapshot = SessionTransaction.mark_applied(snapshot, command_id)
	var zones := SessionTransaction.zone_states(candidate)
	var activity_id := String(active_result["activity"].get("id", ""))
	zones[activity_id] = snapshot.duplicate(true)
	var state_result := SessionTransaction.replace_search_state(
		candidate,
		SessionTransaction.none_activity(),
		zones
	)
	if not bool(state_result.get("ok", false)):
		return state_result
	var commit := SessionTransaction.commit(session, candidate)
	if not bool(commit.get("ok", false)):
		return commit
	return _success({"snapshot": snapshot, "archived": true})


static func _generation_context(run_state: RunState) -> Dictionary:
	var minute := int(run_state.calendar.minute_of_day)
	return {
		"luck": run_state.get_characteristic("luck"),
		"depletion": 0,
		"weather": "dry",
		"time_band": "night" if minute < 360 or minute >= 1260 else "day",
	}


static func _no_activity(session: Object) -> bool:
	if session == null or not session.has_method("get_active_activity"):
		return false
	var activity: Variant = session.call("get_active_activity")
	return activity is Dictionary and String(activity.get("kind", "")) == "none"


static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "ok", "error": "", "idempotent": false}
	result.merge(details, true)
	return result
