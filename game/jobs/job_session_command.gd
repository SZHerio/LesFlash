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
const LadderScript := preload("res://game/jobs/job_ladder.gd")
const SessionTransactionScript := preload("res://game/session/session_command_transaction.gd")
const SocialMutationScript := preload("res://core/social/social_mutation.gd")
const WorldMutationScript := preload("res://core/world/world_mutation.gd")
const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")
const WorldDefinitionCatalogScript := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)

## Which employer sits at which place, and who runs the shift there.
const JOBS := {
	"recycling_point": {
		"job_id": "job_recycling_sorter",
		"supervisor": "npc_viktor_koren",
		"opens_minute": 420,
		"last_start_minute": 990,
		"title": "смена на площадке",
		"description": "Сортировочная площадка. Мартин распределяет участок.",
	},
	"market": {
		"job_id": "job_market_porter",
		"supervisor": "npc_tamara_roven",
		"opens_minute": 330,
		"last_start_minute": 900,
		"required_qualification_id": "qual_sanitary_book",
		"title": "смена в ряду",
		"description": "Продуктовый ряд. Клара показывает, что разгружать.",
	},
}
const DEFAULT_JOB_ID := "job_recycling_sorter"
const PROCESS_ID := "process_recycling_inspection"
const YARD_LOCATION := "recycling_point"


static func job_at(location_id: String) -> Dictionary:
	return Dictionary(JOBS.get(location_id, {}))
const YARD_REPUTATION := "rep_recycling_reliability"
const PRESSURE_METRIC := "metric_riverside_institution_pressure"

## Six hours spread over the confirmed steps rather than charged at the end, so
## leaving a shift half-done still costs the part that was worked.
const SHIFT_MINUTES := 360

## What Viktor remembers about a shift, in the vocabulary the social state
## actually stores. A dangerous shift is a loss he had to cover for.
## The class of shift task that teaches load handling, and the skill it teaches.
const CARGO_TASK_CLASS := "task_recycling_move_load"
const CARGO_SKILL := "cargo_handling"

const MEMORY_TYPE_BY_GRADE := {
	"excellent": "worked_well",
	"solid": "worked_well",
	"acceptable": "worked_well",
	"weak": "caused_loss",
	"unsafe": "caused_loss",
}


static func begin(target: Object, job_id: String, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if bool(target.get("applied_command_ids").has(command_id)):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var work_state: JobWorkState = target.get("job_work_state")
	if work_state.is_dismissed(job_id):
		return _failure("dismissed", "Вас больше не ставят в смену")
	if work_state.is_active():
		return _failure("shift_active", "Смена уже идёт")
	# One shift a day. JobWorkState has always known this; nobody asked it.
	if not work_state.can_work_on_day(job_id, _day_index(target)):
		return _failure("shift_already_worked_today", "Сегодняшняя смена уже отработана")
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("invalid_catalog", "Каталог смен недоступен", {"errors": loaded.get("errors", [])})
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить смену")
	var candidate_work: JobWorkState = candidate.get("job_work_state")
	var generated := GeneratorScript.generate(
		Dictionary(loaded["catalog"]),
		job_id,
		int(candidate.get("run_state").rng.seed),
		candidate_work.sequence_for(job_id)
	)
	if not bool(generated.get("ok", false)):
		return _failure("shift_not_generated", "Смену не удалось составить", {"errors": generated.get("errors", [])})
	var snapshot: Dictionary = generated["snapshot"]
	var started := ServiceScript.start(snapshot)
	if not bool(started.get("ok", false)):
		return started
	if not candidate_work.begin_shift(
		snapshot, Dictionary(started["progress"]), _day_index(target)
	):
		return _failure("shift_rejected", "Смена не принята состоянием работы")
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": "job_shift_begin",
		"title": "Выход на смену",
		"journal_message": "Смена на сортировочной площадке началась",
		"journal_payload": {"job_id": job_id, "shift_id": String(snapshot.get("shift_id", ""))},
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
	return _finish(
		target,
		candidate,
		candidate_work,
		snapshot,
		Dictionary(resolved["progress"]),
		1,
		step_count,
		command_id,
		"job_shift_step"
	)


## The shortcut a hero earns by having actually worked the job several different
## ways. It resolves only the routine — every remaining task whose class he has
## already practised — and stops in front of the decision, because the decision
## is the part of the shift that is not routine.
static func quick_resolve(target: Object, command_id: String) -> Dictionary:
	var guard := _guard(target, command_id)
	if not guard.is_empty():
		return guard
	if bool(target.get("applied_command_ids").has(command_id)):
		return {"ok": true, "code": "already_applied", "error": "", "idempotent": true}
	var work_state: JobWorkState = target.get("job_work_state")
	if not work_state.is_active():
		return _failure("no_active_shift", "Активной смены нет")
	if not quick_resolve_available(target):
		return _failure(
			"quick_resolve_locked",
			"Быстрый расчёт открывается после разнообразной подтверждённой практики"
		)
	var candidate: Object = target.call("clone")
	if candidate == null:
		return _failure("clone_failed", "Не удалось подготовить быстрый расчёт")
	var candidate_work: JobWorkState = candidate.get("job_work_state")
	var snapshot: Dictionary = candidate_work.snapshot
	var step_count := maxi(Array(snapshot.get("steps", [])).size(), 1)
	var profile := _actor_profile(candidate.get("run_state"))
	var practiced: Array = Array(
		candidate_work.mastery_for(candidate_work.active_job_id()).get("practiced_task_class_ids", [])
	)
	var progress: Dictionary = candidate_work.progress.duplicate(true)
	var resolved_steps := 0
	var resolved_choices: Array = []
	# A shift cannot need more turns than it has steps. Without this bound a step
	# that resolves successfully without advancing — a snapshot whose steps do not
	# line up with its progress, which a hand-edited or half-migrated save can
	# produce — spins here forever, and the player sees the game stop responding
	# with no way out but killing it.
	var turns_allowed := step_count + 1
	while String(progress.get("status", "")) != "completed":
		if resolved_steps >= turns_allowed:
			return _failure(
				"shift_did_not_advance",
				"Смена не сдвинулась с места — доработайте её вручную"
			)
		var planned := ServiceScript.quick_choice(snapshot, progress, profile)
		if not bool(planned.get("ok", false)):
			break
		if String(planned.get("task_class_id", "")) not in practiced:
			break
		var stepped := ServiceScript.resolve_step(
			snapshot,
			progress,
			String(planned["choice_id"]),
			profile
		)
		if not bool(stepped.get("ok", false)):
			return stepped
		progress = Dictionary(stepped["progress"])
		resolved_steps += 1
		resolved_choices.append({
			"step_id": String(planned["step_id"]),
			"choice_id": String(planned["choice_id"]),
		})
	if resolved_steps == 0:
		return _failure(
			"nothing_to_skip",
			"Сейчас впереди не рутина, а решение смены"
		)
	var finished := _finish(
		target,
		candidate,
		candidate_work,
		snapshot,
		progress,
		resolved_steps,
		step_count,
		command_id,
		"job_shift_quick"
	)
	if bool(finished.get("ok", false)):
		finished["resolved_steps"] = resolved_steps
		finished["resolved_choices"] = resolved_choices
	return finished


static func _newly_practiced(history: Dictionary) -> Array:
	var shifts: Array = Array(history.get("completed_shifts", []))
	if shifts.is_empty() or not shifts[-1] is Dictionary:
		return []
	return Array(Dictionary(shifts[-1]).get("new_task_class_ids", []))


static func can_begin_today(target: Object, job_id: String = DEFAULT_JOB_ID) -> bool:
	if target == null:
		return false
	var work_state: JobWorkState = target.get("job_work_state")
	if work_state == null or work_state.is_active():
		return false
	return work_state.can_work_on_day(job_id, _day_index(target))


static func _day_index(target: Object) -> int:
	@warning_ignore("integer_division")
	var day: int = int(target.get("run_state").calendar.elapsed_minutes) / 1440
	return day


static func quick_resolve_available(target: Object) -> bool:
	if target == null:
		return false
	var work_state: JobWorkState = target.get("job_work_state")
	if work_state == null or not work_state.is_active():
		return false
	return MasteryScript.quick_resolve_eligible(
		work_state.mastery_for(work_state.active_job_id())
	)


## One commit for one confirmed decision, whether that decision resolved a
## single step or the whole remaining routine. Pay, mastery, the supervisor's
## opinion, the yard's standing and the inspection all move with it.
static func _finish(
	target: Object,
	candidate: Object,
	candidate_work: JobWorkState,
	snapshot: Dictionary,
	next_progress: Dictionary,
	resolved_steps: int,
	step_count: int,
	command_id: String,
	source_id: String
) -> Dictionary:
	var finished := String(next_progress.get("status", "")) == "completed"
	@warning_ignore("integer_division")
	var per_step: int = SHIFT_MINUTES / step_count
	var effects: Array = [{
		"type": "advance_time",
		"minutes": per_step * resolved_steps,
		"reason": "Работа на площадке",
	}]
	var payload := {"job_id": candidate_work.active_job_id(), "shift_id": String(snapshot.get("shift_id", ""))}
	var result: Dictionary = {}
	if finished:
		result = Dictionary(next_progress.get("result", {}))
		var day_index := int(candidate.get("run_state").calendar.elapsed_minutes / 1440)
		var next_mastery: Dictionary = MasteryScript.record_completed_shift(
			candidate_work.mastery_for(candidate_work.active_job_id()),
			next_progress
		)
		if not bool(next_mastery.get("ok", false)):
			return _failure("mastery_rejected", "Освоение смены не записалось")
		# JobMastery returns the updated record under `history`; reading a
		# `mastery` key here crashed every shift that reached its last step.
		if not candidate_work.complete_shift(
			next_progress,
			Dictionary(next_mastery["history"]),
			day_index
		):
			return _failure("completion_rejected", "Итог смены не принят состоянием работы")
		# What the day is worth depends on who is working it. A casual hand gets
		# what the job pays; the one they ask for by name gets half again. The
		# grade is read *before* this shift is recorded, so a rung is never
		# reached and paid for in the same breath.
		var grade := LadderScript.grade_of(
			target.get("run_state"),
			target.get("job_work_state"),
			candidate_work.active_job_id()
		)
		var payout := int(
			float(_payout(result)) * float(LadderScript.pay_basis_points(grade)) / 10_000.0
		)
		effects.append({"type": "change_money", "amount": payout, "reason": "Оплата смены"})
		payload["result"] = result.duplicate(true)
		payload["payout_ard"] = payout
		payload["grade_id"] = grade
		# A shift is where a trade is actually learned. Each task class the hero
		# worked counts as one distinct piece of practice for the skill that
		# task uses, so a rank comes from doing different things rather than
		# repeating the easy one.
		var practised := _practice_effects(snapshot, next_progress)
		effects.append_array(practised)
		if not practised.is_empty():
			payload["practiced_skills"] = _practiced_skill_ids(practised)
		var social := _record_social(candidate, result, candidate_work.active_job_id())
		if not bool(social.get("ok", false)):
			return social
		var world := _record_world(candidate, result)
		if not bool(world.get("ok", false)):
			return world
	elif not candidate_work.replace_progress(next_progress):
		return _failure("progress_rejected", "Шаг смены не принят состоянием работы")
	var committed := SessionTransactionScript.execute(candidate, {
		"command_id": command_id,
		"source_id": source_id,
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
		"dismissed": bool(target.get("job_work_state").is_dismissed(String(payload["job_id"]))),
		"transaction": committed,
	}


## Pay follows the grade rather than attendance, so a careless shift is worth
## less than a careful one even though both took six hours.
## One practice entry per task class worked, tagged by that class. Repeating a
## class within the same shift teaches nothing extra, and the run state refuses
## a duplicate source anyway.
static func _practice_effects(snapshot: Dictionary, progress: Dictionary) -> Array:
	var by_class: Dictionary = {}
	for raw_step: Variant in Array(snapshot.get("steps", [])):
		var step: Dictionary = raw_step
		if String(step.get("kind", "")) != "task":
			continue
		by_class[String(step.get("task_class_id", ""))] = String(step.get("skill_id", ""))
	var effects: Array = []
	var seen: Dictionary = {}
	for raw_done: Variant in Array(progress.get("completed_steps", [])):
		var done: Dictionary = raw_done
		var class_id := String(done.get("task_class_id", ""))
		if class_id.is_empty() or seen.has(class_id):
			continue
		seen[class_id] = true
		var skill_id := String(by_class.get(class_id, ""))
		if skill_id.is_empty():
			continue
		effects.append({
			"type": "practice_skill",
			"id": skill_id,
			"source_id": class_id,
		})
	return effects


static func _practiced_skill_ids(effects: Array) -> Array:
	var ids: Array = []
	for raw_effect: Variant in effects:
		var skill_id := String(Dictionary(raw_effect).get("id", ""))
		if not skill_id.is_empty() and not ids.has(skill_id):
			ids.append(skill_id)
	return ids


static func _payout(result: Dictionary) -> int:
	return int(
		float(int(result.get("base_payout_ard", 0)))
		* float(int(result.get("payout_basis_points", 10_000)))
		/ 10_000.0
	)


## Viktor watched the shift, so his opinion moves with the grade and he
## remembers the specific day rather than an average.
static func _record_social(candidate: Object, result: Dictionary, job_id: String) -> Dictionary:
	var supervisor := "npc_viktor_koren"
	var yard := YARD_LOCATION
	for location_id: String in JOBS:
		if String(Dictionary(JOBS[location_id])["job_id"]) == job_id:
			supervisor = String(Dictionary(JOBS[location_id])["supervisor"])
			yard = location_id
	var grade := String(result.get("grade", "acceptable"))
	var trust: int = {"excellent": 6, "solid": 3, "acceptable": 0, "weak": -3, "unsafe": -7}.get(grade, 0)
	# The mutation takes a complete memory record, not a loose summary string:
	# a flat payload was rejected as invalid_npc_memory and took the whole
	# shift result down with it.
	var operations: Array = [{
		"type": "add_npc_memory",
		"npc_id": supervisor,
		"memory": {
			"memory_id": _memory_id(String(result.get("shift_id", "shift"))),
			"type_id": MEMORY_TYPE_BY_GRADE.get(grade, "worked_well"),
			"valence": clampi(trust * 10, -100, 100),
			"salience": 45 if grade in ["unsafe", "excellent"] else 25,
		},
	}]
	if trust != 0:
		# The mutation names the axis `field` and the audience `reputation_id`;
		# the earlier spelling was rejected and rolled the shift result back.
		operations.push_front({
			"type": "change_relationship",
			"npc_id": supervisor,
			"field": "trust",
			"delta": trust,
		})
		operations.append({
			"type": "change_reputation",
			"reputation_id": YARD_REPUTATION,
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


## An unsafe shift is exactly what the district inspection is looking for. The
## stage itself moves on confirmed time through the authored transitions, so a
## bad shift does what a bad shift actually does: it draws attention. Higher
## institution pressure is read by the inspection and by the shop counter, so
## careless work is felt in the district rather than scored in private.
static func _record_world(candidate: Object, result: Dictionary) -> Dictionary:
	var grade := String(result.get("grade", "acceptable"))
	var pressure: int = {"unsafe": 4, "weak": 2}.get(grade, 0)
	if pressure == 0:
		return {"ok": true}
	var world_state: WorldState = candidate.get("world_state")
	var current := world_state.metric_value(PRESSURE_METRIC, 0)
	var delta := mini(pressure, WorldState.METRIC_MAX - current)
	if delta <= 0:
		return {"ok": true}
	var loaded := WorldDefinitionCatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure("world_definitions_failed", "Каталог процессов мира недоступен")
	var applied := WorldMutationScript.apply(
		world_state,
		{
			"schema_version": WorldMutationScript.SCHEMA_VERSION,
			"source_id": "job_shift_result",
			"at": candidate.get("run_state").calendar.current_stamp(),
			"operations": [{
				"type": "change_world_metric",
				"id": PRESSURE_METRIC,
				"delta": delta,
			}],
		},
		Dictionary(loaded.get("catalog", {}))
	)
	if not bool(applied.get("ok", false)):
		return _failure("world_commit_failed", "Не удалось записать внимание района", {"cause": applied})
	return {"ok": true}


## Memory ids are lowercase identifiers, and a generated shift id carries
## colons and a version suffix, so it is folded down rather than pasted in.
static func _memory_id(shift_id: String) -> String:
	var normalized := ""
	for character: String in shift_id.to_lower():
		normalized += character if character in "abcdefghijklmnopqrstuvwxyz0123456789" else "_"
	return "shift_%s" % normalized.lstrip("_")


static func _actor_profile(run_state: RunState) -> Dictionary:
	return {
		"characteristics": run_state.characteristics.duplicate(true),
		"skills": run_state.skills.duplicate(true),
		"polarities": run_state.stored_polarities.duplicate(true),
		"equipment": EquipmentRulesScript.modifiers(run_state.inventory),
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
