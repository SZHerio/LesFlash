class_name KnowledgeDefinitionCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "knowledge_catalog_v1"
const DEFAULT_PATH := "res://game/content/data/knowledge_catalog_v1.json"
const KINDS := ["fact", "topic"]


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	Rules.validate_header(catalog, CATALOG_ID, SCHEMA_VERSION, errors)
	var definitions := Rules.index_entries(
		catalog.get("knowledge", null), "knowledge", "", errors
	)
	for knowledge_id: String in definitions:
		var definition: Dictionary = definitions[knowledge_id]
		var path := "knowledge.%s" % knowledge_id
		Rules.validate_text(definition.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(
			definition.get("description", null), "%s.description" % path, errors
		)
		var kind := String(definition.get("kind", ""))
		if kind not in KINDS:
			errors.append("%s.kind должен быть fact или topic" % path)
		var expected_max := 1 if kind == "fact" else 3
		if definition.get("max_level", null) != expected_max:
			errors.append("%s.max_level должен быть равен %d" % [path, expected_max])
		Rules.validate_id_array(definition.get("tags", []), "%s.tags" % path, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func definitions(catalog: Dictionary) -> Array:
	return Array(catalog.get("knowledge", [])).duplicate(true)


static func definition(catalog: Dictionary, knowledge_id: String) -> Dictionary:
	for raw_definition: Variant in catalog.get("knowledge", []):
		if raw_definition is Dictionary and String(raw_definition.get("id", "")) == knowledge_id:
			return Dictionary(raw_definition).duplicate(true)
	return {}
