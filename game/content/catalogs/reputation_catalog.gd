class_name ReputationDefinitionCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "reputation_catalog_v1"
const DEFAULT_PATH := "res://game/content/data/reputation_catalog_v1.json"
const AUDIENCE_KINDS := ["organization", "group"]


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
	var audiences := Rules.index_entries(
		catalog.get("audiences", null), "audiences", "", errors
	)
	var reputations := Rules.index_entries(
		catalog.get("reputations", null), "reputations", "rep_", errors
	)
	for audience_id: String in audiences:
		var audience: Dictionary = audiences[audience_id]
		var path := "audiences.%s" % audience_id
		var kind := String(audience.get("kind", ""))
		if kind not in AUDIENCE_KINDS:
			errors.append("%s.kind неизвестен" % path)
		elif kind == "organization" and not audience_id.begins_with("org_"):
			errors.append("%s должен использовать префикс org_" % path)
		elif kind == "group" and not audience_id.begins_with("group_"):
			errors.append("%s должен использовать префикс group_" % path)
		Rules.validate_text(audience.get("title", null), "%s.title" % path, errors)
	for reputation_id: String in reputations:
		var reputation: Dictionary = reputations[reputation_id]
		var path := "reputations.%s" % reputation_id
		Rules.validate_text(reputation.get("title", null), "%s.title" % path, errors)
		Rules.validate_text(
			reputation.get("description", null), "%s.description" % path, errors
		)
		var audience_id := String(reputation.get("audience_id", ""))
		if not audiences.has(audience_id):
			errors.append("%s.audience_id ссылается на неизвестную аудиторию" % path)
		Rules.validate_int_range(reputation.get("minimum", null), -100, -100, "%s.minimum" % path, errors)
		Rules.validate_int_range(reputation.get("maximum", null), 100, 100, "%s.maximum" % path, errors)
		Rules.validate_int_range(reputation.get("default", null), -100, 100, "%s.default" % path, errors)
		if reputation.get("requires_observed_source", null) != true:
			errors.append("%s.requires_observed_source должен быть true" % path)
	return {"ok": errors.is_empty(), "errors": errors}


static func reputations(catalog: Dictionary) -> Array:
	return Array(catalog.get("reputations", [])).duplicate(true)
