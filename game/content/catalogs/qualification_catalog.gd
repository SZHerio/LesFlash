class_name QualificationCatalog
extends RefCounted

## Documents, clearances, courses and licences.
##
## A skill answers "what can he do"; a qualification answers "is he allowed to".
## The two are deliberately separate: knowing how to fix a scale is not the same
## as holding the paper that lets you be paid for it, and M5 is where that
## distinction starts to matter.

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Rules := preload("res://game/content/catalogs/catalog_rules.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "qualification_catalog_v1"
const DEFAULT_PATH := "res://game/content/data/qualification_catalog_v1.json"
const KINDS := ["document", "clearance", "course", "licence"]
const KNOWN_LOCATION_IDS := [
	"underpass", "market", "station_square", "recycling_point", "clinic_yard", "embankment",
	"freight_yard", "courtyard_blocks",
]
const KNOWN_ISSUER_IDS := ["org_riverside_recycling", "org_riverside_market"]


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
	var entries := Rules.index_entries(
		catalog.get("qualifications", null), "qualifications", "qual_", errors
	)
	for qualification_id: String in entries:
		var entry: Dictionary = entries[qualification_id]
		var path := "qualifications.%s" % qualification_id
		for field: String in ["title", "description"]:
			Rules.validate_text(entry.get(field, null), "%s.%s" % [path, field], errors)
		if String(entry.get("kind", "")) not in KINDS:
			errors.append("%s.kind должен быть одним из: %s" % [path, ", ".join(KINDS)])
		if String(entry.get("issuer_id", "")) not in KNOWN_ISSUER_IDS:
			errors.append("%s.issuer_id ссылается на неизвестную организацию" % path)
		if String(entry.get("location_id", "")) not in KNOWN_LOCATION_IDS:
			errors.append("%s.location_id неизвестен" % path)
		Rules.validate_int_range(
			entry.get("duration_minutes", null), 30, 480, "%s.duration_minutes" % path, errors
		)
		Rules.validate_int_range(
			entry.get("fee_ard", null), 0, 2_000, "%s.fee_ard" % path, errors
		)
		_validate_skill_ranks(entry.get("required_skill_ranks", null), path, errors)
		Rules.validate_id_array(
			entry.get("required_knowledge_ids", null),
			"%s.required_knowledge_ids" % path,
			errors,
			false
		)
		_validate_prerequisites(entry, entries, path, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_skill_ranks(value: Variant, path: String, errors: Array[String]) -> void:
	if value == null:
		return
	if not value is Dictionary:
		errors.append("%s.required_skill_ranks должен быть объектом" % path)
		return
	for raw_skill: Variant in Dictionary(value):
		var skill_id := String(raw_skill)
		if not GameRules.is_known_skill(skill_id):
			errors.append("%s.required_skill_ranks содержит неизвестный навык %s" % [path, skill_id])
			continue
		Rules.validate_int_range(
			Dictionary(value)[raw_skill],
			1,
			GameRules.SKILL_MAX_RANK,
			"%s.required_skill_ranks.%s" % [path, skill_id],
			errors
		)


## A qualification may require others, but the chain has to terminate: a paper
## that requires itself, directly or through a loop, can never be earned.
static func _validate_prerequisites(
	entry: Dictionary,
	entries: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var required := Rules.validate_id_array(
		entry.get("required_qualification_ids", null),
		"%s.required_qualification_ids" % path,
		errors,
		false
	)
	for required_id: String in required:
		if not entries.has(required_id):
			errors.append("%s требует неизвестную квалификацию %s" % [path, required_id])
	# Two papers may share a prerequisite — that is a diamond, not a cycle. Only
	# coming back round to the paper itself is a chain that can never be earned.
	var origin := String(entry.get("id", ""))
	var visited: Dictionary = {}
	var queue: Array[String] = []
	queue.append_array(required)
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == origin:
			errors.append("%s образует цикл требований" % path)
			return
		if visited.has(current) or not entries.has(current):
			continue
		visited[current] = true
		queue.append_array(
			Array(Dictionary(entries[current]).get("required_qualification_ids", []))
		)


static func find(catalog: Dictionary, qualification_id: String) -> Dictionary:
	for raw_entry: Variant in Array(catalog.get("qualifications", [])):
		if raw_entry is Dictionary and String(raw_entry.get("id", "")) == qualification_id:
			return Dictionary(raw_entry).duplicate(true)
	return {}


## Everything standing between the hero and this paper, in the words he would
## hear at the counter. Empty means it can be taken now.
static func blockers(entry: Dictionary, run_state: RunState, held: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	if run_state == null:
		return ["Состояние попытки недоступно"]
	for raw_required: Variant in Array(entry.get("required_qualification_ids", [])):
		if not held.has(String(raw_required)):
			reasons.append("Сначала нужна другая бумага")
			break
	var ranks: Dictionary = Dictionary(entry.get("required_skill_ranks", {}))
	for raw_skill: Variant in ranks:
		var skill_id := String(raw_skill)
		if run_state.get_skill_rank(skill_id) < int(ranks[raw_skill]):
			reasons.append("Не хватает умения")
			break
	for raw_knowledge: Variant in Array(entry.get("required_knowledge_ids", [])):
		if not run_state.knowledge.has(String(raw_knowledge)):
			reasons.append("Вы ещё не знаете, куда обращаться")
			break
	if run_state.money < int(entry.get("fee_ard", 0)):
		reasons.append("Не хватает денег на пошлину")
	return reasons
