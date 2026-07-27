class_name JobSessionCommand
extends RefCounted

## Atomic bridge between the shift domain and the owning session.
##
## Until this file the shift existed but could not be reached: JobWorkState was
## referenced by nothing but its own tests, so no player could work a day.
##
## Every confirmed step commits on its own — progress, the clock and the needs
## it costs — because a shift is six hours long and a run interrupted halfway
## must not rewind to the briefing. The final step commits the rest with it:
## pay, mastery, Viktor's opinion, the yard's reputation and the inspection
## process all move in the same transaction as the last decision.

const CatalogScript := preload("res://game/jobs/job_shift_catalog.gd")
const GeneratorScript := preload("res://game/jobs/job_shift_generator.gd")
const ServiceScript := preload("res://game/jobs/job_shift_service.gd")
const MasteryScript := preload("res://game/jobs/job_mastery.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const SocialMutationScript := preload("res://core/social/social_mutation.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")

const JOB_ID := "job_recycling_sorter"
const SUPERVISOR_ID := "npc_viktor_koren"
const PROCESS_ID := "process_recycling_inspection"
const YARD_LOCATION := "recycling_point"

## Six hours spread over the confirmed steps rather than charged at the end, so
## leaving a shift half-done still costs the part that was worked.
const SHIFT_MINUTES := 360


static func begin(target: Object, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if bool(target.get("applied_command_ids").has(command_id)):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var work_state: JobWorkState = target.get("job_work_state")
	if work_state.is_dismissed():
		return _failure("dismissed", "Виктор больше не ставит вас в смену")
	if work_state.is_active():
		return _failure("shift_active", "Смена уже идёт")
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("invalid_catalog", "Каталог смен недоступен", {"errors": loaded.get("errors", [])})
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить смену")
	var candidate_work: JobWorkState = candidate.get("job_work_state")
	var generated := GeneratorScript.generate(
		Dictionary(loaded["catalog"]),
		JOB_ID,
		int(candidate.get("run_state").rng.seed),
		candidate_work.next_shift_sequence
	)
	if not bool(generated.get("ok", false)):
		return _failure("shift_not_generated", "Смену не удалось составить", {"errors": generated.get("errors", [])})
	var snapshot: Dictionary = generated["snapshot"]
	var started := ServiceScript.start(snapshot)
	if not bool(started.get("ok", false)):
		return started
	if not candidate_work.begin_shift(snapshot, Dictionary(started["progress"])):
		return _failure("shift_rejected", "Смена не принята состоянием работы")
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "job_shift_begin",
		"title": "Выход на смену",
		"journal_message": "Смена на сортировочной площадке началась",
		"journal_payload": {"job_id": JOB_ID, "shift_id": String(snapshot.get("shift_id", ""))},
		"conditions": [],
		"effects": [],
	})
	if not bool(committed.get("ok", false)):
		return committed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила выход на смену")
	return {"ok": true, "code": "ok", "error": "", "idempotent": false, "transaction": committed}


static func resolve_step(target: Object, choice_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if bool(target.get("applied_command_ids").has(command_id)):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var work_state: JobWorkState = target.get("job_work_state")
	if not work_state.is_active():
		return _failure("no_active_shift", "Активной смены нет")
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить шаг смены")
	var candidate_work: JobWorkState = candidate.get("job_work_state")
	var snapshot: Dictionary = candidate_work.snapshot
	var step_count := maxi(Array(snapshot.get("steps", [])).size(), 1)
	var resolved := ServiceScript.resolve_step(
		snapshot,
		candidate_work.progress,
		choice_id,
		_actor_profile(candidate.get("run_state"))
	)
	if not bool(resolved.get("ok", false)):
		return resolved
	var next_progress: Dictionary = resolved["progress"]
	var finished := String(next_progress.get("status", "")) == "completed"
	@warning_ignore("integer_division")
	var minutes := SHIFT_MINUTES / step_count
	var effects: Array = [{
		"type": "advance_time",
		"minutes": minutes,
		"reason": "Работа на площадке",
	}]
	var payload := {"job_id": JOB_ID, "shift_id": String(snapshot.get("shift_id", ""))}
	var result: Dictionary = {}
	if finished:
		result = Dictionary(next_progress.get("result", {}))
		var day_index := int(candidate.get("run_state").calendar.elapsed_minutes / 1440)
		var next_mastery: Dictionary = MasteryScript.record_completed_shift(
			candidate_work.mastery,
			next_progress,
			int(candidate.get("run_state").get_skill_rank("cargo_handling"))
		)
		if not bool(next_mastery.get("ok", false)):
			return _failure("mastery_rejected", "Освоение смены не записалось")
		if not candidate_work.complete_shift(next_progress, Dictionary(next_mastery["mastery"]), day_index):
			return _failure("completion_rejected", "Итог смены не принят состоянием работы")
		var payout := _payout(result)
		effects.append({"type": "change_money", "amount": payout, "reason": "Оплата смены"})
		payload["result"] = result.duplicate(true)
		payload["payout_ard"] = payout
		var social := _record_social(candidate, result)
		if not bool(social.get("ok", false)):
			return social
		var world := _record_world(candidate, result)
		if not bool(world.get("ok", false)):
			return world
	elif not candidate_work.replace_progress(next_progress):
		return _failure("progress_rejected", "Шаг смены не принят состоянием работы")
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "job_shift_step",
		"title": "Смена",
		"journal_message": "Итог смены" if finished else "Шаг смены подтверждён",
		"journal_payload": payload,
		"conditions": [],
		"effects": effects,
	})
	if not bool(committed.get("ok", false)):
		return committed
	if not bool(target.call("replace_from", candidate)):
		return _failure("commit_failed", "Сессия отклонила шаг смены")
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"idempotent": false,
		"completed": finished,
		"result": result,
		"dismissed": bool(target.get("job_work_state").is_dismissed()),
		"transaction": committed,
	}


## Pay follows the grade rather than attendance, so a careless shift is worth
## less than a careful one even though both took six hours.
static func _payout(result: Dictionary) -> int:
	return int(
		float(int(result.get("base_payout_ard", 0)))
		* float(int(result.get("payout_basis_points", 10_000)))
		/ 10_000.0
	)


## Viktor watched the shift, so his opinion moves with the grade and he
## remembers the specific day rather than an average.
static func _record_social(candidate: Object, result: Dictionary) -> Dictionary:
	var grade := String(result.get("grade", "acceptable"))
	var trust: int = {"excellent": 6, "solid": 3, "acceptable": 0, "weak": -3, "unsafe": -7}.get(grade, 0)
	var operations: Array = [{
		"type": "add_npc_memory",
		"npc_id": SUPERVISOR_ID,
		"memory_id": "shift_%s" % String(result.get("shift_id", "")),
		"summary": "Смена на площадке: %s" % grade,
	}]
	if trust != 0:
		operations.push_front({
			"type": "change_relationship",
			"npc_id": SUPERVISOR_ID,
			"axis": "trust",
			"delta": trust,
		})
		operations.append({
			"type": "change_reputation",
			"scope_id": YARD_LOCATION,
			"delta": trust,
		})
	var applied := SocialMutationScript.apply(candidate.get("social_state"), {
		"schema_version": SocialMutationScript.SCHEMA_VERSION,
		"source_id": "job_shift_result",
		"at": candidate.get("run_state").calendar.current_stamp(),
		"operations": operations,
	})
	if not bool(applied.get("ok", false)):
		return _failure("social_commit_failed", "Не удалось записать отношение мастера", {"cause": applied})
	return {"ok": true}


## An unsafe shift is exactly what the district inspection is looking for, so
## bad work pushes the process along instead of merely scoring badly.
static func _record_world(candidate: Object, result: Dictionary) -> Dictionary:
	var grade := String(result.get("grade", "acceptable"))
	var pressure: int = {"unsafe": 2, "weak": 1}.get(grade, 0)
	if pressure == 0:
		return {"ok": true}
	var applied := WorldMutationScript.apply(candidate.get("world_state"), {
		"schema_version": WorldMutationScript.SCHEMA_VERSION,
		"source_id": "job_shift_result",
		"at": candidate.get("run_state").calendar.current_stamp(),
		"operations": [{
			"type": "advance_world_process",
			"process_id": PROCESS_ID,
			"steps": pressure,
		}],
	})
	if not bool(applied.get("ok", false)):
		return _failure("world_commit_failed", "Не удалось продвинуть проверку", {"cause": applied})
	return {"ok": true}


static func _actor_profile(run_state: RunState) -> Dictionary:
	return {
		"characteristics": run_state.characteristics.duplicate(true),
		"skills": run_state.skills.duplicate(true),
		"polarities": run_state.stored_polarities.duplicate(true),
	}


static func _guard(target: Object, command_id: String) -> Dictionary:
	if target == null:
		return _failure("invalid_session", "Игровая сессия отсутствует")
	for method: String in ["clone", "replace_from", "validate"]:
		if not target.has_method(method):
			return _failure("invalid_session", "Сессия не реализует %s()" % method)
	if command_id.strip_edges().is_empty():
		return _failure("missing_command_id", "Смена должна иметь идентификатор команды")
	return {}


static func _failure(code: String, error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(details, true)
	return result
