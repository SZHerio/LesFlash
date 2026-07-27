class_name SocialMutation
extends RefCounted

## Atomic interpreter for relationships, scoped reputation, memory and typed
## commitments. It never executes content-provided code.

const SCHEMA_VERSION := 1
const OPERATION_TYPES := [
	"change_relationship",
	"add_npc_memory",
	"change_reputation",
	"create_commitment",
	"resolve_commitment",
]


static func apply(target: SocialState, mutation: Dictionary) -> Dictionary:
	if target == null:
		return _failure("missing_social_state", "Социальное состояние отсутствует")
	var validation := validate(mutation)
	if not bool(validation.get("ok", false)):
		return _failure("invalid_social_mutation", "; ".join(PackedStringArray(validation["errors"])))
	var working := target.clone()
	if working == null:
		return _failure("social_clone_failed", "Не удалось создать копию отношений")
	var changes: Array[Dictionary] = []
	var source_id := String(mutation.get("source_id", ""))
	var at: Dictionary = Dictionary(mutation.get("at", {})).duplicate(true)
	for index: int in Array(mutation["operations"]).size():
		var operation: Dictionary = mutation["operations"][index]
		var result := _apply_operation(working, operation, source_id, at)
		if not bool(result.get("ok", false)):
			return _failure(
				String(result.get("code", "social_operation_failed")),
				String(result.get("error", "Не удалось изменить отношения")),
				{"failed_index": index, "changes": changes}
			)
		changes.append(Dictionary(result["change"]).duplicate(true))
	working.revision += 1
	var state_validation := working.validate()
	if not bool(state_validation.get("ok", false)) or not target.replace_from(working):
		return _failure("social_commit_failed", "Не удалось зафиксировать социальное состояние")
	return {"ok": true, "code": "ok", "error": "", "changes": changes}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["social_mutation must be a dictionary"]}
	var mutation: Dictionary = value
	if int(mutation.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("social_mutation.schema_version is unsupported")
	if String(mutation.get("source_id", "")).strip_edges().is_empty():
		errors.append("social_mutation.source_id cannot be empty")
	if not mutation.get("at", null) is Dictionary:
		errors.append("social_mutation.at must be a dictionary")
	var operations: Variant = mutation.get("operations", null)
	if not operations is Array:
		errors.append("social_mutation.operations must be an array")
	else:
		for index: int in operations.size():
			var operation: Variant = operations[index]
			if not operation is Dictionary or String(Dictionary(operation).get("type", "")) not in OPERATION_TYPES:
				errors.append("social_mutation.operations[%d] is unsupported" % index)
	return {"ok": errors.is_empty(), "errors": errors}


static func _apply_operation(
	state: SocialState,
	operation: Dictionary,
	source_id: String,
	at: Dictionary
) -> Dictionary:
	var operation_type := String(operation.get("type", ""))
	match operation_type:
		"change_relationship":
			var npc_id := String(operation.get("npc_id", operation.get("id", "")))
			var field := String(operation.get("field", ""))
			if npc_id.is_empty() or field not in SocialState.RELATIONSHIP_FIELDS or typeof(operation.get("delta", null)) != TYPE_INT:
				return _failure("invalid_relationship_change", "Изменение отношения заполнено неверно")
			var relationship := state.relationship(npc_id)
			var before := int(relationship[field])
			var minimum := 0 if field == "fear" else -100
			var after := clampi(before + int(operation["delta"]), minimum, 100)
			relationship[field] = after
			state.relationships[npc_id] = relationship
			return _change(operation_type, "%s.%s" % [npc_id, field], before, after)
		"change_reputation":
			var reputation_id := String(operation.get("reputation_id", operation.get("id", "")))
			if reputation_id.is_empty() or typeof(operation.get("delta", null)) != TYPE_INT:
				return _failure("invalid_reputation_change", "Изменение репутации заполнено неверно")
			var before := int(state.reputations.get(reputation_id, 0))
			var after := clampi(before + int(operation["delta"]), -100, 100)
			state.reputations[reputation_id] = after
			return _change(operation_type, reputation_id, before, after)
		"add_npc_memory":
			var npc_id := String(operation.get("npc_id", ""))
			var memory: Variant = operation.get("memory", null)
			if npc_id.is_empty() or not memory is Dictionary:
				return _failure("invalid_npc_memory", "Память NPC заполнена неверно")
			var record: Dictionary = Dictionary(memory).duplicate(true)
			record["source_id"] = String(record.get("source_id", source_id))
			record["occurred_at"] = Dictionary(record.get("occurred_at", at)).duplicate(true)
			record["resolved"] = bool(record.get("resolved", false))
			var entries := state.memories_for(npc_id)
			var memory_id := String(record.get("memory_id", ""))
			for raw_existing: Variant in entries:
				if String(Dictionary(raw_existing).get("memory_id", "")) == memory_id:
					return _failure("duplicate_npc_memory", "Память %s уже существует" % memory_id)
			entries.append(record)
			state.memories[npc_id] = entries
			return _change(operation_type, memory_id, null, record)
		"create_commitment":
			var commitment: Variant = operation.get("commitment", null)
			if not commitment is Dictionary:
				return _failure("invalid_commitment", "Обязательство заполнено неверно")
			var record: Dictionary = Dictionary(commitment).duplicate(true)
			var commitment_id := String(record.get("commitment_id", operation.get("id", "")))
			if commitment_id.is_empty() or state.commitments.has(commitment_id):
				return _failure("duplicate_commitment", "Обязательство уже существует или не имеет ID")
			record["commitment_id"] = commitment_id
			record["source_id"] = String(record.get("source_id", source_id))
			record["created_at"] = Dictionary(record.get("created_at", at)).duplicate(true)
			record["state"] = "open"
			state.commitments[commitment_id] = record
			return _change(operation_type, commitment_id, null, record)
		"resolve_commitment":
			var commitment_id := String(operation.get("commitment_id", operation.get("id", "")))
			if not state.commitments.has(commitment_id):
				return _failure("unknown_commitment", "Обязательство %s не найдено" % commitment_id)
			var before: Dictionary = Dictionary(state.commitments[commitment_id]).duplicate(true)
			if String(before.get("state", "")) != "open":
				return _failure("commitment_not_open", "Обязательство уже закрыто")
			var after := before.duplicate(true)
			var resolved_state := String(operation.get("state", "resolved"))
			if resolved_state not in ["resolved", "broken", "cancelled"]:
				return _failure("invalid_commitment_state", "Неизвестный итог обязательства")
			after["state"] = resolved_state
			after["resolved_at"] = at.duplicate(true)
			state.commitments[commitment_id] = after
			return _change(operation_type, commitment_id, before, after)
	return _failure("unknown_social_operation", "Неизвестное социальное изменение")


static func _change(kind: String, identifier: String, before: Variant, after: Variant) -> Dictionary:
	return {
		"ok": true,
		"code": "ok",
		"error": "",
		"change": {"effect_type": kind, "target_id": identifier, "before": before, "after": after},
	}


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
