class_name NpcInteractionCatalog
extends RefCounted

## Read-only versioned content for player-initiated recurring NPC meetings.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Validator := preload("res://game/npc/npc_interaction_validator.gd")
const NpcCatalog := preload("res://game/content/catalogs/npc_catalog.gd")
const KnowledgeCatalog := preload("res://game/content/catalogs/knowledge_catalog.gd")
const ReputationCatalog := preload("res://game/content/catalogs/reputation_catalog.gd")
const WorldCatalog := preload("res://game/content/catalogs/world_definition_catalog.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "npc_interaction_catalog_v1"
const DEFAULT_PATH := "res://game/npc/data/npc_interaction_catalog_v1.json"


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var references := default_references()
	if not bool(references.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": references.get("errors", [])}
	var validation := Validator.validate(
		Dictionary(parsed.get("catalog", {})),
		Dictionary(references.get("ids", {}))
	)
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary, references: Dictionary = {}) -> Dictionary:
	var resolved := references
	if resolved.is_empty():
		var loaded := default_references()
		if not bool(loaded.get("ok", false)):
			return {"ok": false, "errors": loaded.get("errors", [])}
		resolved = Dictionary(loaded.get("ids", {}))
	return Validator.validate(catalog, resolved)


static func find_interaction(catalog: Dictionary, interaction_id: String) -> Dictionary:
	for raw: Variant in catalog.get("interactions", []):
		if raw is Dictionary and String(raw.get("id", "")) == interaction_id:
			return Dictionary(raw).duplicate(true)
	return {}


static func interactions_for_npc(catalog: Dictionary, npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in catalog.get("interactions", []):
		if raw is Dictionary and String(raw.get("npc_id", "")) == npc_id:
			result.append(Dictionary(raw).duplicate(true))
	return result


static func default_references() -> Dictionary:
	var errors: Array[String] = []
	var npcs := _load("npcs", NpcCatalog.load_default(), errors)
	var knowledge := _load("knowledge", KnowledgeCatalog.load_default(), errors)
	var reputations := _load("reputations", ReputationCatalog.load_default(), errors)
	var world := _load("world", WorldCatalog.load_default(), errors)
	if not errors.is_empty():
		return {"ok": false, "ids": {}, "errors": errors}
	return {
		"ok": true,
		"errors": [],
		"ids": {
			"npc": _index(npcs.get("npcs", [])),
			"knowledge": _index(knowledge.get("knowledge", [])),
			"reputation": _index(reputations.get("reputations", [])),
			"world_fact": _index(world.get("facts", [])),
			"world_metric": _index(world.get("metrics", [])),
			"world_process": _index(world.get("processes", [])),
		},
	}


static func _load(label: String, loaded: Dictionary, errors: Array[String]) -> Dictionary:
	if bool(loaded.get("ok", false)):
		return Dictionary(loaded.get("catalog", {}))
	for error: Variant in Array(loaded.get("errors", [])):
		errors.append("%s: %s" % [label, String(error)])
	return {}


static func _index(entries: Variant) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in Array(entries):
		if raw is Dictionary:
			result[String(raw.get("id", ""))] = true
	return result
