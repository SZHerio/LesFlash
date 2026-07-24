class_name SearchReadModel
extends RefCounted

## Pure raw model for the search screen.
##
## Every approach carries the same availability the domain would enforce, so the
## sheet can show why something is closed before the player spends anything.
## Reading never advances time, RNG or the session.

const ZoneCatalog := preload("res://game/search/search_zone_catalog.gd")
const InteractionResolver := preload(
	"res://game/search/search_interaction_resolver.gd"
)
const InteractionTransaction := preload(
	"res://game/search/search_interaction_transaction.gd"
)
const RiskResolver := preload("res://game/search/search_risk_resolver.gd")
const SessionTransaction := preload(
	"res://game/search/search_session_transaction.gd"
)
const InventoryQuery := preload("res://core/inventory/inventory_query.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")

## Pockets first, then a backpack if the hero owns one. Hands are last: carrying
## a find in your hands is what stops you doing anything else with them.
const PREFERRED_CONTAINERS := ["pockets", "backpack", "hands"]


## Returns the authored zone that belongs to a location, or {} when that place
## has nothing to search.
static func zone_for_location(location_id: String) -> Dictionary:
	var loaded := ZoneCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return {}
	var template: Dictionary = loaded["template"]
	if String(template.get("location_id", "")) != location_id:
		return {}
	return template


static func build(session: Object) -> Dictionary:
	var active := SessionTransaction.require_active(session)
	if not bool(active.get("ok", false)):
		return {}
	var snapshot: Dictionary = active["snapshot"]
	var loaded := ZoneCatalog.load_default()
	var template: Dictionary = loaded.get("template", {}) if bool(
		loaded.get("ok", false)
	) else {}
	var run_state: RunState = session.get("run_state")
	return {
		"zone_id": String(snapshot.get("template_id", "")),
		"snapshot": snapshot,
		"template": template,
		"approaches": _approach_overrides(run_state, snapshot),
		"loot_tray": _loot_tray(run_state, snapshot),
		"quick_search": _quick_search(run_state, snapshot),
		"warning_threshold": RiskResolver.ENCOUNTER_THRESHOLD,
		"path": Array(
			Dictionary(snapshot.get("player", {})).get("planned_path", [])
		).duplicate(true),
	}


static func _approach_overrides(
	run_state: RunState,
	snapshot: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	if run_state == null:
		return result
	var encounter_pending := not SessionTransaction.pending_encounter(
		snapshot
	).is_empty()
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if not raw_object is Dictionary:
			continue
		var object: Dictionary = raw_object
		var object_id := String(object.get("id", ""))
		var overrides: Dictionary = {}
		for raw_approach: Variant in Array(object.get("approaches", [])):
			if not raw_approach is Dictionary:
				continue
			var approach_id := String(raw_approach.get("id", ""))
			if approach_id.is_empty():
				continue
			overrides[approach_id] = _approach_state(
				run_state,
				snapshot,
				object_id,
				approach_id,
				encounter_pending
			)
		result[object_id] = overrides
	return result


static func _approach_state(
	run_state: RunState,
	snapshot: Dictionary,
	object_id: String,
	approach_id: String,
	encounter_pending: bool
) -> Dictionary:
	if encounter_pending:
		return {
			"enabled": false,
			"blocked_reasons": ["Сначала ответьте на то, что происходит рядом."],
		}
	var preview := InteractionResolver.preview(
		run_state,
		snapshot,
		object_id,
		approach_id,
		true
	)
	if not bool(preview.get("ok", false)):
		return {"enabled": false, "blocked_reasons": ["Способ сейчас недоступен."]}
	var reasons: Array[String] = []
	for raw_reason: Variant in Array(preview.get("blocked_reasons", [])):
		if raw_reason is Dictionary:
			reasons.append(String(raw_reason.get("message", "Условие не выполнено.")))
	return {
		"enabled": bool(preview.get("allowed", false)),
		"blocked_reasons": reasons,
	}


static func _loot_tray(run_state: RunState, snapshot: Dictionary) -> Array:
	var result: Array = []
	if run_state == null:
		return result
	for raw_ref: Variant in Array(snapshot.get("ground_items", [])):
		if not raw_ref is Dictionary:
			continue
		var entry: Dictionary = Dictionary(raw_ref).duplicate(true)
		entry["target_container_id"] = _suggested_container(
			run_state,
			String(entry.get("item_id", "")),
			int(entry.get("quantity", 1))
		)
		result.append(entry)
	return result


## The next place a find could go after `exclude_container_id` turned out to be
## full. Returns "" when the hero has no other place to try.
static func alternative_container(
	session: Object,
	stack_id: String,
	exclude_container_id: String
) -> String:
	var active := SessionTransaction.require_active(session)
	if not bool(active.get("ok", false)):
		return ""
	var run_state: RunState = session.get("run_state")
	if run_state == null:
		return ""
	for raw_ref: Variant in Array(Dictionary(active["snapshot"]).get("ground_items", [])):
		if not raw_ref is Dictionary:
			continue
		if String(raw_ref.get("stack_id", "")) != stack_id:
			continue
		return _suggested_container(
			run_state,
			String(raw_ref.get("item_id", "")),
			int(raw_ref.get("quantity", 1)),
			exclude_container_id
		)
	return ""


## Always names a container, even when nothing fits. A full inventory should
## open the comparison sheet on tap, not leave the player with a dead button.
static func _suggested_container(
	run_state: RunState,
	item_id: String,
	quantity: int,
	exclude_container_id: String = ""
) -> String:
	var definition: Variant = ItemCatalog.definition(item_id)
	var strength := run_state.get_characteristic("strength")
	var fallback := ""
	for container_id: String in PREFERRED_CONTAINERS:
		if container_id == exclude_container_id:
			continue
		var limits := InventoryQuery.capacity(
			run_state.inventory,
			container_id,
			strength
		)
		if limits.is_empty() or not bool(limits.get("active", false)):
			continue
		if fallback.is_empty():
			fallback = container_id
		if InventoryQuery.can_add(
			run_state.inventory,
			container_id,
			definition,
			quantity,
			strength
		):
			return container_id
	return fallback


static func _quick_search(run_state: RunState, snapshot: Dictionary) -> Dictionary:
	var resolved := InteractionResolver.exhausted_count(snapshot)
	var required := InteractionTransaction.QUICK_SEARCH_RESOLVED_REQUIRED
	if run_state == null:
		return {"visible": false, "enabled": false, "blocked_reason": ""}
	if resolved < required or run_state.get_skill_rank("search") < 1:
		return {
			"visible": true,
			"enabled": false,
			"progress_text": "%d/%d" % [mini(resolved, required), required],
			"blocked_reason": "Быстрый поиск откроется, когда вы разберётесь с %d объектами зоны: сейчас %d." % [
				required,
				resolved,
			],
		}
	if not SessionTransaction.pending_encounter(snapshot).is_empty():
		return {
			"visible": true,
			"enabled": false,
			"progress_text": "",
			"blocked_reason": "Сначала ответьте на то, что происходит рядом.",
		}
	return {
		"visible": true,
		"enabled": true,
		"progress_text": "",
		"blocked_reason": "",
	}
