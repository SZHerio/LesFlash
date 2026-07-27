class_name SocialState
extends RefCounted

## Typed per-run social state. This is intentionally separate from objective
## WorldState and from the hero's knowledge.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1
const RELATIONSHIP_FIELDS := ["trust", "respect", "affinity", "fear"]
const COMMITMENT_STATES := ["open", "resolved", "broken", "cancelled"]
const MEMORY_TYPES := [
	"helped", "worked_well", "kept_promise", "broke_promise",
	"threatened", "stole", "caused_loss", "shared_resource",
]

var revision: int = 0
var relationships: Dictionary = {}
var reputations: Dictionary = {}
var memories: Dictionary = {}
var commitments: Dictionary = {}


static func fresh() -> SocialState:
	return SocialState.new()


static func neutral_relationship() -> Dictionary:
	return {"trust": 0, "respect": 0, "affinity": 0, "fear": 0}


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": revision,
		"relationships": relationships.duplicate(true),
		"reputations": reputations.duplicate(true),
		"memories": memories.duplicate(true),
		"commitments": commitments.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SocialState:
	var normalized: Variant = JsonValidator.normalize_numbers(data)
	if not normalized is Dictionary:
		return null
	var source: Dictionary = normalized
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return null
	if typeof(source.get("revision", null)) != TYPE_INT or int(source["revision"]) < 0:
		return null
	for field: String in ["relationships", "reputations", "memories", "commitments"]:
		if not source.get(field, null) is Dictionary:
			return null
	var result := SocialState.new()
	result.revision = int(source["revision"])
	result.relationships = Dictionary(source["relationships"]).duplicate(true)
	result.reputations = Dictionary(source["reputations"]).duplicate(true)
	result.memories = Dictionary(source["memories"]).duplicate(true)
	result.commitments = Dictionary(source["commitments"]).duplicate(true)
	return result if bool(result.validate().get("ok", false)) else null


func clone() -> SocialState:
	return SocialState.from_dict(to_dict())


func replace_from(other: SocialState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	revision = other.revision
	relationships = other.relationships.duplicate(true)
	reputations = other.reputations.duplicate(true)
	memories = other.memories.duplicate(true)
	commitments = other.commitments.duplicate(true)
	return true


func relationship(npc_id: String) -> Dictionary:
	var value: Variant = relationships.get(npc_id)
	return Dictionary(value).duplicate(true) if value is Dictionary else neutral_relationship()


func memories_for(npc_id: String) -> Array:
	var value: Variant = memories.get(npc_id, [])
	return Array(value).duplicate(true) if value is Array else []


func validate() -> Dictionary:
	var errors: Array[String] = []
	if revision < 0:
		errors.append("social_state.revision cannot be negative")
	_validate_relationships(errors)
	_validate_reputations(errors)
	_validate_memories(errors)
	_validate_commitments(errors)
	var json_validation := JsonValidator.validate(to_dict(), "social_state")
	for raw_error: Variant in Array(json_validation.get("errors", [])):
		errors.append(String(raw_error))
	return {"ok": errors.is_empty(), "errors": errors}


func _validate_relationships(errors: Array[String]) -> void:
	for raw_id: Variant in relationships:
		var npc_id := String(raw_id)
		var value: Variant = relationships[raw_id]
		if not _valid_id(npc_id) or not value is Dictionary:
			errors.append("social_state.relationships contains an invalid entry")
			continue
		var record: Dictionary = value
		if record.size() != RELATIONSHIP_FIELDS.size():
			errors.append("social_state.relationships.%s has an invalid shape" % npc_id)
		for field: String in RELATIONSHIP_FIELDS:
			if typeof(record.get(field, null)) != TYPE_INT:
				errors.append("social_state.relationships.%s.%s must be integer" % [npc_id, field])
				continue
			var minimum := 0 if field == "fear" else -100
			if int(record[field]) < minimum or int(record[field]) > 100:
				errors.append("social_state.relationships.%s.%s is outside range" % [npc_id, field])


func _validate_reputations(errors: Array[String]) -> void:
	for raw_id: Variant in reputations:
		if not _valid_id(String(raw_id)) or typeof(reputations[raw_id]) != TYPE_INT:
			errors.append("social_state.reputations contains an invalid value")
		elif int(reputations[raw_id]) < -100 or int(reputations[raw_id]) > 100:
			errors.append("social_state.reputations.%s is outside -100..100" % String(raw_id))


func _validate_memories(errors: Array[String]) -> void:
	var ids: Dictionary = {}
	for raw_npc_id: Variant in memories:
		var npc_id := String(raw_npc_id)
		var entries: Variant = memories[raw_npc_id]
		if not _valid_id(npc_id) or not entries is Array:
			errors.append("social_state.memories contains an invalid NPC entry")
			continue
		for index: int in entries.size():
			var raw_memory: Variant = entries[index]
			if not raw_memory is Dictionary:
				errors.append("social_state.memories.%s[%d] must be a dictionary" % [npc_id, index])
				continue
			var memory: Dictionary = raw_memory
			var memory_id := String(memory.get("memory_id", ""))
			if not _valid_id(memory_id) or ids.has(memory_id):
				errors.append("social_state memory_id is invalid or duplicated")
			else:
				ids[memory_id] = true
			if String(memory.get("type_id", "")) not in MEMORY_TYPES:
				errors.append("social_state memory %s has an unknown type" % memory_id)
			if typeof(memory.get("source_id", null)) != TYPE_STRING:
				errors.append("social_state memory %s source_id must be a string" % memory_id)
			if not memory.get("occurred_at", null) is Dictionary:
				errors.append("social_state memory %s occurred_at must be a dictionary" % memory_id)
			if typeof(memory.get("valence", null)) != TYPE_INT or int(memory.get("valence", 0)) < -100 or int(memory.get("valence", 0)) > 100:
				errors.append("social_state memory %s valence is invalid" % memory_id)
			if typeof(memory.get("salience", null)) != TYPE_INT or int(memory.get("salience", 0)) < 0 or int(memory.get("salience", 0)) > 100:
				errors.append("social_state memory %s salience is invalid" % memory_id)
			if typeof(memory.get("resolved", null)) != TYPE_BOOL:
				errors.append("social_state memory %s resolved must be boolean" % memory_id)
			if memory.has("expires_at") and not memory["expires_at"] is Dictionary:
				errors.append("social_state memory %s expires_at must be a dictionary" % memory_id)


func _validate_commitments(errors: Array[String]) -> void:
	for raw_id: Variant in commitments:
		var commitment_id := String(raw_id)
		var value: Variant = commitments[raw_id]
		if not _valid_id(commitment_id) or not value is Dictionary:
			errors.append("social_state.commitments contains an invalid entry")
			continue
		var record: Dictionary = value
		if String(record.get("commitment_id", "")) != commitment_id:
			errors.append("social_state commitment key mismatch")
		for field: String in ["type_id", "debtor_id", "creditor_id", "subject_id", "source_id"]:
			if typeof(record.get(field, null)) != TYPE_STRING:
				errors.append("social_state commitment %s.%s must be a string" % [commitment_id, field])
		if String(record.get("state", "")) not in COMMITMENT_STATES:
			errors.append("social_state commitment %s has an invalid state" % commitment_id)
		if not record.get("created_at", null) is Dictionary:
			errors.append("social_state commitment %s created_at must be a dictionary" % commitment_id)
		if record.has("due_at") and not record["due_at"] is Dictionary:
			errors.append("social_state commitment %s due_at must be a dictionary" % commitment_id)
		if record.has("resolved_at") and not record["resolved_at"] is Dictionary:
			errors.append("social_state commitment %s resolved_at must be a dictionary" % commitment_id)


static func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := String(value)
	if identifier.is_empty() or identifier != identifier.to_lower():
		return false
	for character: String in identifier:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true
