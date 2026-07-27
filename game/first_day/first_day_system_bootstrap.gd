class_name FirstDaySystemBootstrap
extends RefCounted

## Builds the versioned systems owned by a fresh run without coupling the
## legacy first-day flow to catalog loading and world construction details.

const WorldDefinitionCatalog := preload(
	"res://game/content/catalogs/world_definition_catalog.gd"
)
const WorldStateFactory := preload("res://game/content/world_state_factory.gd")


static func create_world(run_state: RunState) -> Dictionary:
	if run_state == null or run_state.calendar == null:
		return _failure("missing_run_state", "Не удалось определить время новой жизни")
	var loaded := WorldDefinitionCatalog.load_default()
	if not bool(loaded.get("ok", false)):
		return _failure(
			"world_catalog_failed",
			"Каталог состояния мира не прошёл проверку",
			{"errors": Array(loaded.get("errors", [])).duplicate(true)}
		)
	var world_state := WorldStateFactory.from_catalog(
		Dictionary(loaded.get("catalog", {})),
		run_state.calendar.current_stamp()
	)
	if world_state == null:
		return _failure(
			"world_bootstrap_failed",
			"Не удалось создать начальное состояние мира"
		)
	return {"ok": true, "code": "ok", "error": "", "world_state": world_state}


static func _failure(code: String, error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": error}
	result.merge(extra, true)
	return result
