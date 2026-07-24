class_name SearchEncounterCommand
extends RefCounted

## Read model and atomic answer for the encounter a search zone has queued.
##
## The card was already chosen when the encounter appeared, so answering it is
## never a fresh draw. Option availability is re-evaluated against the hero's
## current state, which keeps a freed hand or a used item from being ignored.

const CatalogScript := preload("res://game/events/event_catalog.gd")
const Director := preload("res://game/events/event_director.gd")
const EventCommandScript := preload("res://game/events/event_command.gd")
const EventContextScript := preload("res://game/events/event_context.gd")
const CommandService := preload("res://game/search/search_command_service.gd")
const SessionTransaction := preload(
	"res://game/search/search_session_transaction.gd"
)
const RiskResolver := preload("res://game/search/search_risk_resolver.gd")


static func pending(session: Object) -> Dictionary:
	var active := SessionTransaction.require_active(session)
	if not bool(active.get("ok", false)):
		return _inactive()
	var snapshot: Dictionary = active["snapshot"]
	var encounter: Dictionary = Dictionary(
		snapshot.get("pending_encounter", {})
	).duplicate(true)
	if encounter.is_empty():
		return _inactive()
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return SessionTransaction.failure(
			"event_catalog_failed",
			"Каталог встреч недоступен.",
			{"active": false, "errors": Array(loaded.get("errors", [])).duplicate()}
		)
	var preview := Director.preview(
		loaded["catalog"],
		String(encounter.get("card_id", "")),
		_current_context(session, encounter)
	)
	if not bool(preview.get("ok", false)):
		return SessionTransaction.failure(
			"unknown_encounter_card",
			"Карточка встречи не найдена.",
			{"active": false}
		)
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"active": true,
		"encounter": encounter,
		"preview": preview,
	}


static func resolve(
	session: Object,
	option_id: String,
	command_id: String
) -> Dictionary:
	var prepared := CommandService.prepare_mutation(session, command_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	var snapshot: Dictionary = prepared["snapshot"]
	var encounter: Dictionary = Dictionary(snapshot.get("pending_encounter", {}))
	if encounter.is_empty():
		return SessionTransaction.failure(
			"no_pending_encounter",
			"Сейчас нет встречи, ожидающей ответа."
		)
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return SessionTransaction.failure(
			"event_catalog_failed",
			"Каталог встреч недоступен.",
			{"errors": Array(loaded.get("errors", [])).duplicate()}
		)
	var candidate: Object = prepared["candidate"]
	var card_id := String(encounter.get("card_id", ""))
	var executed: Dictionary = EventCommandScript.execute(
		candidate.get("run_state"),
		loaded["catalog"],
		card_id,
		option_id,
		_current_context(candidate, encounter)
	)
	if not bool(executed.get("ok", false)):
		return executed
	var updated := RiskResolver.relieve(snapshot)
	updated.erase("pending_encounter")
	var cooldowns: Dictionary = Dictionary(
		updated.get("encounter_cooldowns", {})
	).duplicate(true)
	cooldowns[card_id] = int(executed.get("cooldown_ready_at", 0))
	updated["encounter_cooldowns"] = cooldowns
	var history: Array = Array(updated.get("encounter_history", [])).duplicate(true)
	var fact := String(executed.get("history_fact", ""))
	if not fact.is_empty() and fact not in history:
		history.append(fact)
	updated["encounter_history"] = history
	return CommandService.commit_active(
		session,
		candidate,
		SessionTransaction.mark_applied(updated, command_id),
		{
			"encounter_resolved": true,
			"card_id": card_id,
			"option_id": option_id,
			"outcome": String(executed.get("outcome", "")),
			"transaction": Dictionary(executed.get("transaction", {})).duplicate(true),
			"queued_consequences": Array(
				executed.get("queued_consequences", [])
			).duplicate(true),
		}
	)


## Keeps the encounter's own source, location and risk, but reads the hero from
## the live session so answering reflects what the player can do right now.
static func _current_context(session: Object, encounter: Dictionary) -> Dictionary:
	var stored: Dictionary = Dictionary(encounter.get("context", {})).duplicate(true)
	if session == null:
		return stored
	var run_state: Variant = session.get("run_state")
	if run_state == null or not run_state is RunState:
		return stored
	var refreshed := EventContextScript.build(
		run_state,
		Dictionary(stored.get("source", {})),
		{
			"location_id": String(stored.get("location_id", "")),
			"era_id": String(stored.get("era_id", "late_20th_century")),
			"weather_id": String(stored.get("weather_id", "dry")),
			"relationships": stored.get("relationships", {}),
			"reputations": stored.get("reputations", {}),
			"history_facts": stored.get("history_facts", []),
			"cooldowns": stored.get("cooldowns", {}),
			"risk": stored.get("risk", {}),
		}
	)
	return refreshed if not refreshed.is_empty() else stored


static func _inactive() -> Dictionary:
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"active": false,
		"encounter": {},
		"preview": {},
	}
