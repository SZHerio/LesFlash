class_name SkillCatalog
extends RefCounted

## What a skill is, and — the part that was missing — what teaches it.
##
## A rank grows from *varied* practice: three different sources for the first
## rank, seven for the second, twelve for the third. That rule was written before
## anything but a work shift could teach anything, and the result was a skill
## system that looked complete and was decorative: six of seven skills could
## never leave rank zero, because between them the whole game offered fewer than
## three different ways to practise each.
##
## So a family here is not a name and a description. It is a name and the list of
## things in the game that teach it, and the catalog refuses to load a family
## with fewer than three. A skill with one application is a renamed button.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "skill_catalog_v1"
const DEFAULT_PATH := "res://game/skills/data/skill_catalog_v1.json"

## Where an application lives, which decides who has to emit the practice.
const SOURCE_KINDS := ["job_task", "location_action", "search_approach", "event_choice", "craft"]

## The rule the whole catalog exists to protect: below this a family cannot even
## reach its first rank, so declaring it would be a promise the game cannot keep.
const MIN_APPLICATIONS := 3


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
	var entries := Rules.index_entries(catalog.get("skills", null), "skills", "", errors)
	var claimed: Dictionary = {}
	for skill_id: String in entries:
		var entry: Dictionary = entries[skill_id]
		var path := "skills.%s" % skill_id
		# The save format still owns the list of skill ids. A catalog naming one
		# it does not know would write practice nobody can read back.
		if not GameRules.is_known_skill(skill_id):
			errors.append("%s не входит в список навыков сохранения" % path)
		for field: String in ["title", "description"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		_validate_applications(entry, path, claimed, errors)
	# Every skill the save format knows has to be taught by something, or the
	# hero carries a number that can only ever be zero.
	for skill_id: String in GameRules.SKILL_KEYS:
		if not entries.has(skill_id):
			errors.append("навык %s не описан в каталоге: его нечем практиковать" % skill_id)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_applications(
	entry: Dictionary,
	path: String,
	claimed: Dictionary,
	errors: Array[String]
) -> void:
	var raw: Variant = entry.get("applications", null)
	if not raw is Array:
		errors.append("%s.applications должен быть массивом" % path)
		return
	var applications: Array = raw
	if applications.size() < MIN_APPLICATIONS:
		errors.append(
			"%s.applications: %d — навык с меньшим числом применений не достигает и первого ранга"
				% [path, applications.size()]
		)
	var seen: Dictionary = {}
	for index: int in applications.size():
		var item: Variant = applications[index]
		var item_path := "%s.applications[%d]" % [path, index]
		if not item is Dictionary:
			errors.append("%s должен быть объектом" % item_path)
			continue
		var application: Dictionary = item
		var kind := String(application.get("kind", ""))
		if kind not in SOURCE_KINDS:
			errors.append("%s.kind должен быть одним из: %s" % [item_path, ", ".join(SOURCE_KINDS)])
		var source_id := String(application.get("source_id", "")).strip_edges()
		if source_id.is_empty():
			errors.append("%s.source_id не задан" % item_path)
			continue
		if seen.has(source_id):
			errors.append("%s повторяет источник %s" % [item_path, source_id])
			continue
		seen[source_id] = true
		# One action teaching two different skills would let a single confirmed
		# press count twice, which is how variety stops meaning anything.
		if claimed.has(source_id):
			errors.append(
				"%s: источник %s уже учит навыку %s" % [item_path, source_id, String(claimed[source_id])]
			)
			continue
		claimed[source_id] = path.trim_prefix("skills.")


## The highest rank each skill can reach if the hero does everything the catalog
## names. Not a promise that he will — a statement that he could.
static func reachable_ranks(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_entry: Variant in Array(catalog.get("skills", [])):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		result[String(entry.get("id", ""))] = GameRules.rank_for_practice(
			Array(entry.get("applications", [])).size()
		)
	return result


## Which skill this source teaches, or empty if it teaches nothing. This is the
## question every command asks after the hero confirms something.
static func skill_taught_by(catalog: Dictionary, source_id: String) -> String:
	if source_id.strip_edges().is_empty():
		return ""
	for raw_entry: Variant in Array(catalog.get("skills", [])):
		if not raw_entry is Dictionary:
			continue
		for raw_application: Variant in Array(Dictionary(raw_entry).get("applications", [])):
			if String(Dictionary(raw_application).get("source_id", "")) == source_id:
				return String(Dictionary(raw_entry).get("id", ""))
	return ""


static func find(catalog: Dictionary, skill_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("skills", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == skill_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


## Every source of one kind, so a cross-check can ask the content catalogs
## whether these things actually exist.
static func sources_of_kind(catalog: Dictionary, kind: String) -> Array[String]:
	var result: Array[String] = []
	for raw_entry: Variant in Array(catalog.get("skills", [])):
		if not raw_entry is Dictionary:
			continue
		for raw_application: Variant in Array(Dictionary(raw_entry).get("applications", [])):
			var application: Dictionary = raw_application
			if String(application.get("kind", "")) == kind:
				result.append(String(application.get("source_id", "")))
	return result
