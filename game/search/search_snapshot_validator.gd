class_name SearchSnapshotValidator
extends RefCounted

const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")
const RngScript := preload("res://core/random/deterministic_rng.gd")
const GraphValidator := preload("res://game/search/search_graph_validator.gd")
const ContentValidator := preload("res://game/search/search_content_validator.gd")

const SCHEMA_VERSION := 1
const OBJECT_STATES := ["concealed", "available", "exhausted"]


static func validate(value: Variant, template: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["Snapshot поисковой зоны должен быть объектом"]}
	var snapshot: Dictionary = value
	if snapshot.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("Ожидалась версия snapshot %d" % SCHEMA_VERSION)
	if String(snapshot.get("template_id", "")).strip_edges().is_empty():
		errors.append("snapshot.template_id не задан")
	if not _positive_integer(snapshot.get("template_version", null)):
		errors.append("snapshot.template_version должен быть положительным целым числом")
	if not _positive_integer(snapshot.get("visit_index", null)):
		errors.append("snapshot.visit_index должен быть положительным целым числом")

	_validate_graph(snapshot, errors)
	var node_ids := GraphValidator.node_ids(snapshot)
	_validate_rng(snapshot.get("rng", null), errors)
	_validate_player(snapshot.get("player", null), node_ids, errors)
	_validate_risk(snapshot.get("risk", null), errors)
	_validate_objects(snapshot.get("objects", null), node_ids, errors)
	_validate_ground(snapshot.get("ground_items", null), errors)
	_validate_command_ids(snapshot.get("applied_command_ids", null), errors)
	_validate_context(snapshot.get("generation_context", null), errors)
	if not template.is_empty():
		_validate_against_template(snapshot, template, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_graph(snapshot: Dictionary, errors: Array[String]) -> void:
	var graph_validation := GraphValidator.validate(snapshot)
	for raw_error: Variant in Array(graph_validation.get("errors", [])):
		errors.append("snapshot.%s" % String(raw_error))


static func _validate_rng(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.rng должен быть объектом")
		return
	var stream_id := String(value.get("stream_id", "")).strip_edges()
	if stream_id.is_empty():
		errors.append("snapshot.rng.stream_id не задан")
	if RngScript.from_dict(value) == null:
		errors.append("snapshot.rng содержит некорректные seed/state")


static func _validate_player(value: Variant, node_ids: Dictionary, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.player должен быть объектом")
		return
	if not node_ids.has(String(value.get("node_id", ""))):
		errors.append("snapshot.player.node_id неизвестен")
	if _point(value.get("position", null)) == null:
		errors.append("snapshot.player.position некорректна")


static func _validate_risk(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.risk должен быть объектом")
		return
	for risk_id: String in ["noise", "trespass", "repeated_attempts"]:
		if not _integer_in_range(value.get(risk_id, null), 0, 1_000_000):
			errors.append("snapshot.risk.%s должен быть неотрицательным целым числом" % risk_id)


static func _validate_objects(value: Variant, node_ids: Dictionary, errors: Array[String]) -> void:
	if not value is Array or value.size() < 6 or value.size() > 10:
		errors.append("snapshot.objects должен содержать от 6 до 10 объектов")
		return
	var seen_objects: Dictionary = {}
	var seen_loot: Dictionary = {}
	for index: int in value.size():
		var raw_object: Variant = value[index]
		var prefix := "snapshot.objects[%d]" % index
		if not raw_object is Dictionary:
			errors.append("%s должен быть объектом" % prefix)
			continue
		var object_id := String(raw_object.get("id", "")).strip_edges()
		var object_type := String(raw_object.get("type", ""))
		if object_id.is_empty() or seen_objects.has(object_id):
			errors.append("%s содержит пустой или повторный id" % prefix)
		else:
			seen_objects[object_id] = true
		if object_type not in ContentValidator.OBJECT_TYPES:
			errors.append("%s.type неизвестен" % prefix)
		if not node_ids.has(String(raw_object.get("approach_node", ""))):
			errors.append("%s.approach_node неизвестен" % prefix)
		if _point(raw_object.get("position", null)) == null:
			errors.append("%s.position некорректна" % prefix)
		if String(raw_object.get("state", "")) not in OBJECT_STATES:
			errors.append("%s.state неизвестен" % prefix)
		if typeof(raw_object.get("revealed", null)) != TYPE_BOOL:
			errors.append("%s.revealed должен быть bool" % prefix)
		if typeof(raw_object.get("interacted", null)) != TYPE_BOOL:
			errors.append("%s.interacted должен быть bool" % prefix)
		if not raw_object.get("approaches", null) is Array or raw_object["approaches"].is_empty():
			errors.append("%s.approaches должен быть непустым массивом" % prefix)
		var contents: Variant = raw_object.get("contents", null)
		if not contents is Array or contents.is_empty():
			errors.append("%s.contents должен быть разрешён один раз в непустой массив" % prefix)
			continue
		for loot_index: int in contents.size():
			_validate_loot(contents[loot_index], "%s.contents[%d]" % [prefix, loot_index], seen_loot, errors)


static func _validate_loot(
	value: Variant,
	prefix: String,
	seen_loot: Dictionary,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("%s должен быть объектом" % prefix)
		return
	var loot_id := String(value.get("loot_id", "")).strip_edges()
	var item_id := String(value.get("item_id", "")).strip_edges()
	if loot_id.is_empty() or seen_loot.has(loot_id):
		errors.append("%s содержит пустой или повторный loot_id" % prefix)
	else:
		seen_loot[loot_id] = true
	if not ItemCatalogScript.has(item_id):
		errors.append("%s ссылается на неизвестный предмет" % prefix)
	if not _integer_in_range(value.get("quantity", null), 1, 999):
		errors.append("%s.quantity некорректно" % prefix)
	if not _integer_in_range(value.get("condition", null), 0, 100):
		errors.append("%s.condition некорректно" % prefix)
	if typeof(value.get("claimed", null)) != TYPE_BOOL:
		errors.append("%s.claimed должен быть bool" % prefix)


static func _validate_ground(value: Variant, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("snapshot.ground_items должен быть массивом")
		return
	var seen: Dictionary = {}
	for index: int in value.size():
		var raw_item: Variant = value[index]
		var prefix := "snapshot.ground_items[%d]" % index
		if not raw_item is Dictionary:
			errors.append("%s должен быть объектом" % prefix)
			continue
		var ground_id := String(raw_item.get("ground_id", "")).strip_edges()
		if ground_id.is_empty() or seen.has(ground_id):
			errors.append("%s содержит пустой или повторный ground_id" % prefix)
		else:
			seen[ground_id] = true
		if not ItemCatalogScript.has(String(raw_item.get("item_id", ""))):
			errors.append("%s ссылается на неизвестный предмет" % prefix)
		if _point(raw_item.get("position", null)) == null:
			errors.append("%s.position некорректна" % prefix)


static func _validate_command_ids(value: Variant, errors: Array[String]) -> void:
	if not value is Array:
		errors.append("snapshot.applied_command_ids должен быть массивом")
		return
	var seen: Dictionary = {}
	for raw_id: Variant in value:
		var command_id := String(raw_id).strip_edges()
		if command_id.is_empty() or seen.has(command_id):
			errors.append("snapshot.applied_command_ids содержит пустой или повторный id")
			return
		seen[command_id] = true


static func _validate_context(value: Variant, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("snapshot.generation_context должен быть объектом")
		return
	if not _integer_in_range(value.get("luck", null), 1, 10):
		errors.append("snapshot.generation_context.luck должен быть целым числом 1–10")
	if not _integer_in_range(value.get("depletion", null), 0, 1_000_000):
		errors.append("snapshot.generation_context.depletion должен быть неотрицательным целым числом")
	for field: String in ["weather", "time_band"]:
		if typeof(value.get(field, null)) != TYPE_STRING or String(value.get(field, "")).is_empty():
			errors.append("snapshot.generation_context.%s должен быть непустой строкой" % field)


static func _validate_against_template(
	snapshot: Dictionary,
	template: Dictionary,
	errors: Array[String]
) -> void:
	if String(snapshot.get("template_id", "")) != String(template.get("id", "")):
		errors.append("snapshot.template_id не совпадает с шаблоном")
	if int(snapshot.get("template_version", 0)) != int(template.get("template_version", -1)):
		errors.append("snapshot.template_version не совпадает с шаблоном")
	var expected: Dictionary = {}
	for raw_object: Variant in Array(template.get("objects", [])):
		if raw_object is Dictionary:
			expected[String(raw_object.get("id", ""))] = raw_object
	var actual_ids: Dictionary = {}
	for raw_object: Variant in Array(snapshot.get("objects", [])):
		if not raw_object is Dictionary:
			continue
		var object_id := String(raw_object.get("id", ""))
		actual_ids[object_id] = true
		if not expected.has(object_id):
			continue
		var authored: Dictionary = expected[object_id]
		for field: String in ["type", "position", "approach_node", "loot_table_id", "approaches"]:
			if raw_object.get(field, null) != authored.get(field, null):
				errors.append("snapshot объекта «%s» изменил авторское поле %s" % [object_id, field])
		var table_id := String(authored.get("loot_table_id", ""))
		var tables: Dictionary = template.get("loot_tables", {})
		if not tables.has(table_id):
			continue
		var allowed_items: Dictionary = {}
		for raw_entry: Variant in Array(Dictionary(tables[table_id]).get("entries", [])):
			if raw_entry is Dictionary:
				allowed_items[String(raw_entry.get("item_id", ""))] = true
		for raw_loot: Variant in Array(raw_object.get("contents", [])):
			if raw_loot is Dictionary and not allowed_items.has(String(raw_loot.get("item_id", ""))):
				errors.append("snapshot объекта «%s» содержит предмет вне его loot table" % object_id)
	if actual_ids.size() != expected.size():
		errors.append("snapshot.objects не совпадает по набору id с версией шаблона")


static func _positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _point(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	if typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var point := Vector2(float(value[0]), float(value[1]))
	return point if is_finite(point.x) and is_finite(point.y) else null
