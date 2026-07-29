extends SceneTree

## Balance probe for M5 stage 2, run as its own pass after the mechanics.
##
## The catalog can prove a rank is reachable on paper — count the applications,
## compare with the thresholds. What it cannot prove is that a person playing
## normally ever meets three different ones. This measures the gap between the
## two.

const CatalogScript = preload("res://game/skills/skill_catalog.gd")
const JobCatalogScript = preload("res://game/jobs/job_shift_catalog.gd")
const ActionCatalogScript = preload("res://game/sandbox/sandbox_action_catalog.gd")


func _init() -> void:
	var loaded := CatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		print("SKILL BALANCE PROBE: the catalog does not load: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var catalog: Dictionary = loaded["catalog"]
	var reachable := CatalogScript.reachable_ranks(catalog)

	print("SKILL BALANCE PROBE")
	print("  ранг растёт от разных источников: %s" % str(GameRules.SKILL_PRACTICE_FOR_RANK))
	for skill_id: String in GameRules.SKILL_KEYS:
		var entry := CatalogScript.find(catalog, skill_id)
		var by_kind: Dictionary = {}
		for raw_application: Variant in Array(entry.get("applications", [])):
			var kind := String(Dictionary(raw_application).get("kind", ""))
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		print("  %-16s %2d источников -> ранг %d   %s" % [
			skill_id,
			Array(entry.get("applications", [])).size(),
			int(reachable.get(skill_id, 0)),
			_kinds_text(by_kind),
		])

	# A skill reachable only from one kind of thing is reachable only by players
	# who do that thing. Worth seeing, even where it is the right answer.
	print("  --")
	for skill_id: String in GameRules.SKILL_KEYS:
		var entry := CatalogScript.find(catalog, skill_id)
		var kinds: Dictionary = {}
		for raw_application: Variant in Array(entry.get("applications", [])):
			kinds[String(Dictionary(raw_application).get("kind", ""))] = true
		if kinds.size() < 2:
			print("  %s растёт только из одного рода занятий" % skill_id)
	print("SKILL BALANCE PROBE WRITTEN")
	quit(0)


func _kinds_text(by_kind: Dictionary) -> String:
	var parts: Array[String] = []
	for kind: String in ["job_task", "location_action", "search_approach", "event_choice"]:
		if by_kind.has(kind):
			parts.append("%s×%d" % [kind, int(by_kind[kind])])
	return ", ".join(parts)
