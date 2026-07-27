class_name NpcInteractionValidator
extends RefCounted

## Structural and cross-reference gate for authored NPC interactions.

const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const CANONICAL_NPC_IDS := [
	"npc_viktor_koren",
	"npc_lidia_maren",
	"npc_tamara_roven",
]
const REPEAT_KINDS := ["once_per_life", "once_per_civil_day", "cooldown"]
const CONDITION_KINDS := [
	"stat", "state", "polarity", "skill", "knowledge", "item",
	"relationship", "reputation", "world_fact", "world_metric",
	"world_process", "npc_memory", "commitment",
]
const EFFECT_TYPES := [
	"advance_time", "change_state", "knowledge", "change_relationship",
	"add_npc_memory", "change_reputation", "set_world_fact",
	"change_world_metric",
]
const OPERATORS := [">=", ">", "==", "!=", "<", "<="]
const MEMORY_TYPES := [
	"helped", "worked_well", "kept_promise", "broke_promise",
	"threatened", "stole", "caused_loss", "shared_resource",
]


static func validate(catalog: Dictionary, references: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, "npc_interaction_catalog_v1", 1, errors)
	var indexed := Rules.index_entries(
		catalog.get("interactions", null), "interactions", "npc_interaction_", errors
	)
	var memories := _declared_memories(indexed, errors)
	var npc_counts: Dictionary = {}
	var memory_followups: Dictionary = {}
	var repeat_kinds: Dictionary = {}
	for interaction_id: String in indexed:
		var entry: Dictionary = indexed[interaction_id]
		var npc_id := String(entry.get("npc_id", ""))
		var path := "interactions.%s" % interaction_id
		_validate_reference(npc_id, references.get("npc", {}), "%s.npc_id" % path, errors)
		if npc_id not in CANONICAL_NPC_IDS:
			errors.append("%s.npc_id не входит в canonical M3F.3" % path)
		npc_counts[npc_id] = int(npc_counts.get(npc_id, 0)) + 1
		Rules.validate_text(entry.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(entry.get("description", null), "%s.description" % path, errors)
		Rules.validate_text(entry.get("outcome", null), "%s.outcome" % path, errors)
		if entry.has("repeat_outcome"):
			Rules.validate_text(entry.get("repeat_outcome"), "%s.repeat_outcome" % path, errors)
		Rules.validate_int_range(entry.get("duration_minutes"), 1, 120, "%s.duration_minutes" % path, errors)
		var repeat_kind := _validate_repeat(entry.get("repeat_policy"), path, errors)
		repeat_kinds[repeat_kind] = true
		_validate_conditions(entry.get("conditions"), npc_id, memories, references, path, memory_followups, errors)
		_validate_effects(entry.get("effects"), npc_id, references, path, false, errors)
		_validate_effects(entry.get("first_time_effects", []), npc_id, references, path, true, errors)
		_validate_time_effect(entry, path, errors)
		if repeat_kind != "once_per_life":
			_validate_repeat_rewards(entry.get("effects", []), path, errors)
	for npc_id: String in CANONICAL_NPC_IDS:
		if int(npc_counts.get(npc_id, 0)) != 3:
			errors.append("%s должен иметь ровно три взаимодействия" % npc_id)
		if not memory_followups.has(npc_id):
			errors.append("%s должен иметь продолжение, зависящее от памяти" % npc_id)
	for kind: String in REPEAT_KINDS:
		if not repeat_kinds.has(kind):
			errors.append("Каталог должен доказывать repeat policy %s" % kind)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_repeat(raw: Variant, path: String, errors: Array[String]) -> String:
	if not raw is Dictionary:
		errors.append("%s.repeat_policy должен быть объектом" % path)
		return ""
	var policy: Dictionary = raw
	var kind := String(policy.get("kind", ""))
	if kind not in REPEAT_KINDS:
		errors.append("%s.repeat_policy.kind неизвестен" % path)
		return kind
	if kind == "cooldown":
		Rules.validate_int_range(policy.get("minutes"), 1, 1440, "%s.repeat_policy.minutes" % path, errors)
	elif policy.has("minutes"):
		errors.append("%s.repeat_policy.minutes допустим только для cooldown" % path)
	return kind


static func _validate_conditions(
	raw: Variant,
	npc_id: String,
	memories: Dictionary,
	references: Dictionary,
	path: String,
	followups: Dictionary,
	errors: Array[String]
) -> void:
	if not raw is Array:
		errors.append("%s.conditions должен быть массивом" % path)
		return
	for index: int in raw.size():
		var value: Variant = raw[index]
		var condition_path := "%s.conditions[%d]" % [path, index]
		if not value is Dictionary:
			errors.append("%s должен быть объектом" % condition_path)
			continue
		var condition: Dictionary = value
		var kind := String(condition.get("kind", ""))
		var identifier := String(condition.get("id", ""))
		if kind not in CONDITION_KINDS:
			errors.append("%s.kind неизвестен" % condition_path)
		if String(condition.get("operator", "")) not in OPERATORS:
			errors.append("%s.operator неизвестен" % condition_path)
		if not condition.has("value"):
			errors.append("%s.value обязателен" % condition_path)
		Rules.validate_text(condition.get("blocked_reason"), "%s.blocked_reason" % condition_path, errors)
		_validate_condition_reference(kind, identifier, condition, npc_id, memories, references, condition_path, followups, errors)


static func _validate_condition_reference(
	kind: String,
	identifier: String,
	condition: Dictionary,
	npc_id: String,
	memories: Dictionary,
	references: Dictionary,
	path: String,
	followups: Dictionary,
	errors: Array[String]
) -> void:
	var fixed := {
		"stat": GameRules.CHARACTERISTIC_KEYS,
		"state": GameRules.METER_KEYS,
		"polarity": GameRules.STORED_POLARITY_KEYS + GameRules.COMPUTED_PROFILE_KEYS,
		"skill": GameRules.SKILL_KEYS,
	}
	if fixed.has(kind) and identifier not in fixed[kind]:
		errors.append("%s.id неизвестен: %s" % [path, identifier])
	elif kind in ["knowledge", "reputation", "world_fact", "world_metric", "world_process"]:
		_validate_reference(identifier, references.get(kind, {}), "%s.id" % path, errors)
	elif kind == "relationship":
		_validate_reference(identifier, references.get("npc", {}), "%s.id" % path, errors)
		if identifier != npc_id or String(condition.get("field", "")) not in SocialState.RELATIONSHIP_FIELDS:
			errors.append("%s должен проверять поле отношения текущего NPC" % path)
	elif kind == "npc_memory":
		if not memories.has(identifier) or String(condition.get("npc_id", "")) != npc_id:
			errors.append("%s ссылается на неизвестную память текущего NPC" % path)
		elif bool(condition.get("value", false)):
			followups[npc_id] = true


static func _validate_effects(
	raw: Variant,
	npc_id: String,
	references: Dictionary,
	path: String,
	first_time: bool,
	errors: Array[String]
) -> void:
	var field := "first_time_effects" if first_time else "effects"
	if not raw is Array or (not first_time and raw.is_empty()):
		errors.append("%s.%s должен быть %sмассивом" % [path, field, "непустым " if not first_time else ""])
		return
	for index: int in raw.size():
		var value: Variant = raw[index]
		var effect_path := "%s.%s[%d]" % [path, field, index]
		if not value is Dictionary:
			errors.append("%s должен быть объектом" % effect_path)
			continue
		var effect: Dictionary = value
		var kind := String(effect.get("type", ""))
		if kind not in EFFECT_TYPES:
			errors.append("%s.type неизвестен: %s" % [effect_path, kind])
			continue
		_validate_effect(kind, effect, npc_id, references, effect_path, first_time, errors)


static func _validate_effect(kind: String, effect: Dictionary, npc_id: String, references: Dictionary, path: String, first_time: bool, errors: Array[String]) -> void:
	if kind == "advance_time":
		if first_time:
			errors.append("%s не может повторно продвигать время" % path)
		Rules.validate_int_range(effect.get("minutes"), 1, 120, "%s.minutes" % path, errors)
		Rules.validate_text(effect.get("reason"), "%s.reason" % path, errors)
	elif kind == "change_state":
		if String(effect.get("id", "")) not in GameRules.METER_KEYS:
			errors.append("%s.id неизвестен" % path)
		Rules.validate_int_range(effect.get("delta"), -100, 100, "%s.delta" % path, errors)
	elif kind == "knowledge":
		_validate_reference(String(effect.get("id", "")), references.get("knowledge", {}), "%s.id" % path, errors)
		Rules.validate_int_range(effect.get("amount"), 1, 3, "%s.amount" % path, errors)
		if String(effect.get("mode", "")) not in ["add", "advance", "unlock", "set"]:
			errors.append("%s.mode неизвестен" % path)
	elif kind == "change_relationship":
		if String(effect.get("npc_id", "")) != npc_id or String(effect.get("field", "")) not in SocialState.RELATIONSHIP_FIELDS:
			errors.append("%s должен менять отношение текущего NPC" % path)
		Rules.validate_int_range(effect.get("delta"), -3, 3, "%s.delta" % path, errors)
	elif kind == "add_npc_memory":
		_validate_memory_effect(effect, npc_id, path, errors)
	elif kind == "change_reputation":
		_validate_reference(String(effect.get("reputation_id", "")), references.get("reputation", {}), "%s.reputation_id" % path, errors)
		Rules.validate_int_range(effect.get("delta"), -3, 3, "%s.delta" % path, errors)
	elif kind == "set_world_fact":
		_validate_reference(String(effect.get("id", "")), references.get("world_fact", {}), "%s.id" % path, errors)
		if typeof(effect.get("value", null)) != TYPE_BOOL:
			errors.append("%s.value должен быть bool" % path)
	elif kind == "change_world_metric":
		_validate_reference(String(effect.get("id", "")), references.get("world_metric", {}), "%s.id" % path, errors)
		Rules.validate_int_range(effect.get("delta"), -5, 5, "%s.delta" % path, errors)


static func _validate_memory_effect(effect: Dictionary, npc_id: String, path: String, errors: Array[String]) -> void:
	if String(effect.get("npc_id", "")) != npc_id or not effect.get("memory", null) is Dictionary:
		errors.append("%s должен добавлять память текущему NPC" % path)
		return
	var memory: Dictionary = effect["memory"]
	if not String(memory.get("memory_id", "")).begins_with("memory_"):
		errors.append("%s.memory.memory_id некорректен" % path)
	if String(memory.get("type_id", "")) not in MEMORY_TYPES:
		errors.append("%s.memory.type_id неизвестен" % path)
	Rules.validate_int_range(memory.get("valence"), -100, 100, "%s.memory.valence" % path, errors)
	Rules.validate_int_range(memory.get("salience"), 0, 100, "%s.memory.salience" % path, errors)


static func _declared_memories(interactions: Dictionary, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for interaction_id: String in interactions:
		var entry: Dictionary = interactions[interaction_id]
		for field: String in ["effects", "first_time_effects"]:
			for raw: Variant in Array(entry.get(field, [])):
				if not raw is Dictionary or String(raw.get("type", "")) != "add_npc_memory":
					continue
				var memory: Variant = raw.get("memory", {})
				var memory_id := String(Dictionary(memory).get("memory_id", "")) if memory is Dictionary else ""
				if result.has(memory_id):
					errors.append("memory_id повторяется: %s" % memory_id)
				elif not memory_id.is_empty():
					result[memory_id] = String(entry.get("npc_id", ""))
	return result


static func _validate_time_effect(entry: Dictionary, path: String, errors: Array[String]) -> void:
	var time_count := 0
	var effects: Array = entry.get("effects", [])
	for raw: Variant in effects:
		if raw is Dictionary and String(raw.get("type", "")) == "advance_time":
			time_count += 1
			if int(raw.get("minutes", -1)) != int(entry.get("duration_minutes", -2)):
				errors.append("%s duration и advance_time должны совпадать" % path)
	if time_count != 1 or effects.is_empty() or String(Dictionary(effects[0]).get("type", "")) != "advance_time":
		errors.append("%s должен иметь ровно один первый эффект advance_time" % path)


static func _validate_repeat_rewards(effects: Variant, path: String, errors: Array[String]) -> void:
	for raw: Variant in Array(effects):
		if raw is Dictionary and String(raw.get("type", "")) != "advance_time":
			errors.append("%s repeatable effects не могут бесконечно выдавать награду" % path)


static func _validate_reference(identifier: String, raw_known: Variant, path: String, errors: Array[String]) -> void:
	var known: Dictionary = raw_known if raw_known is Dictionary else {}
	if identifier.is_empty() or not known.has(identifier):
		errors.append("%s ссылается на неизвестный ID %s" % [path, identifier])
