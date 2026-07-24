class_name SearchContentValidator
extends RefCounted

const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")

const OBJECT_TYPES := [
	"open",
	"hidden",
	"locked",
	"heavy",
	"social",
	"trespass",
	"technical",
	"hazardous",
]
const REQUIRED_FIRST_ZONE_TYPES := [
	"open",
	"hidden",
	"locked",
	"heavy",
	"social",
	"trespass",
	"technical",
]


static func validate(template: Dictionary, node_ids: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var table_ids := _validate_loot_tables(template.get("loot_tables", null), errors)
	_validate_objects(template.get("objects", null), table_ids, node_ids, template, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_loot_tables(raw_tables: Variant, errors: Array[String]) -> Dictionary:
	var table_ids: Dictionary = {}
	if not raw_tables is Dictionary or raw_tables.is_empty():
		errors.append("loot_tables должен быть непустым объектом")
		return table_ids
	for raw_table_id: Variant in raw_tables:
		var table_id := String(raw_table_id).strip_edges()
		var table_value: Variant = raw_tables[raw_table_id]
		if table_id.is_empty() or table_ids.has(table_id):
			errors.append("loot_tables содержит пустой или повторный id")
			continue
		table_ids[table_id] = true
		if not table_value is Dictionary:
			errors.append("loot_tables.%s должен быть объектом" % table_id)
			continue
		var table: Dictionary = table_value
		if not _valid_pair(table.get("rolls", null), 1, 12):
			errors.append("loot_tables.%s.rolls должен быть диапазоном 1–12" % table_id)
		var entries: Variant = table.get("entries", null)
		if not entries is Array or entries.is_empty():
			errors.append("loot_tables.%s.entries должен быть непустым массивом" % table_id)
			continue
		var positive_weight := false
		for index: int in entries.size():
			var raw_entry: Variant = entries[index]
			var prefix := "loot_tables.%s.entries[%d]" % [table_id, index]
			if not raw_entry is Dictionary:
				errors.append("%s должен быть объектом" % prefix)
				continue
			var item_id := String(raw_entry.get("item_id", "")).strip_edges()
			if not ItemCatalogScript.has(item_id):
				errors.append("%s ссылается на неизвестный предмет «%s»" % [prefix, item_id])
			if not _non_negative_number(raw_entry.get("weight", null)):
				errors.append("%s.weight должен быть неотрицательным числом" % prefix)
			elif float(raw_entry.get("weight", 0.0)) > 0.0:
				positive_weight = true
			if not _valid_pair(raw_entry.get("quantity", null), 1, 999):
				errors.append("%s.quantity содержит недопустимый диапазон" % prefix)
			if not _valid_pair(raw_entry.get("condition", null), 0, 100):
				errors.append("%s.condition содержит недопустимый диапазон" % prefix)
			if not _integer_in_range(raw_entry.get("luck_bias", 0), -10, 10):
				errors.append("%s.luck_bias должен быть целым числом от -10 до 10" % prefix)
		if not positive_weight:
			errors.append("loot_tables.%s не содержит положительного веса" % table_id)
	return table_ids


static func _validate_objects(
	raw_objects: Variant,
	table_ids: Dictionary,
	node_ids: Dictionary,
	template: Dictionary,
	errors: Array[String]
) -> void:
	if not raw_objects is Array or raw_objects.size() < 6 or raw_objects.size() > 10:
		errors.append("objects должен содержать от 6 до 10 объектов первой зоны")
		return
	var map_size: Variant = null
	var map_value: Variant = template.get("map", null)
	if map_value is Dictionary:
		map_size = _point(map_value.get("size", null))
	var seen_ids: Dictionary = {}
	var seen_types: Dictionary = {}
	for index: int in raw_objects.size():
		var raw_object: Variant = raw_objects[index]
		var prefix := "objects[%d]" % index
		if not raw_object is Dictionary:
			errors.append("%s должен быть объектом" % prefix)
			continue
		var object_id := String(raw_object.get("id", "")).strip_edges()
		var title := String(raw_object.get("title", "")).strip_edges()
		var object_type := String(raw_object.get("type", "")).strip_edges()
		var position: Variant = _point(raw_object.get("position", null))
		var approach_node := String(raw_object.get("approach_node", "")).strip_edges()
		var loot_table_id := String(raw_object.get("loot_table_id", "")).strip_edges()
		if object_id.is_empty() or seen_ids.has(object_id):
			errors.append("%s содержит пустой или повторный id" % prefix)
		else:
			seen_ids[object_id] = true
		if title.is_empty():
			errors.append("%s.title не заполнен" % prefix)
		if object_type not in OBJECT_TYPES:
			errors.append("%s.type «%s» не поддерживается" % [prefix, object_type])
		else:
			seen_types[object_type] = true
		if position == null or (map_size is Vector2 and not _inside(position, map_size)):
			errors.append("%s.position находится за пределами карты" % prefix)
		if not node_ids.has(approach_node):
			errors.append("%s.approach_node ссылается на неизвестный узел" % prefix)
		if not table_ids.has(loot_table_id):
			errors.append("%s.loot_table_id ссылается на неизвестную таблицу" % prefix)
		_validate_approaches(raw_object.get("approaches", null), prefix, errors)
	for required_type: String in REQUIRED_FIRST_ZONE_TYPES:
		if not seen_types.has(required_type):
			errors.append("Первая зона не содержит обязательный тип объекта «%s»" % required_type)


static func _validate_approaches(raw_approaches: Variant, prefix: String, errors: Array[String]) -> void:
	if not raw_approaches is Array or raw_approaches.is_empty():
		errors.append("%s.approaches должен быть непустым массивом" % prefix)
		return
	var seen: Dictionary = {}
	for index: int in raw_approaches.size():
		var raw_approach: Variant = raw_approaches[index]
		var path := "%s.approaches[%d]" % [prefix, index]
		if not raw_approach is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var approach_id := String(raw_approach.get("id", "")).strip_edges()
		if approach_id.is_empty() or seen.has(approach_id):
			errors.append("%s содержит пустой или повторный id" % path)
		else:
			seen[approach_id] = true
		if String(raw_approach.get("title", "")).strip_edges().is_empty():
			errors.append("%s.title не заполнен" % path)
		if not _integer_in_range(raw_approach.get("duration_minutes", null), 1, 1440):
			errors.append("%s.duration_minutes должен быть целым положительным числом" % path)
		if not _integer_in_range(raw_approach.get("energy_cost", null), 0, 100):
			errors.append("%s.energy_cost должен быть целым числом от 0 до 100" % path)
		_validate_conditions(raw_approach.get("conditions", null), path, errors)
		var risk: Variant = raw_approach.get("risk", null)
		if not risk is Dictionary:
			errors.append("%s.risk должен быть объектом" % path)
		else:
			for risk_id: String in ["noise", "trespass"]:
				if not _integer_in_range(risk.get(risk_id, null), -10, 100):
					errors.append("%s.risk.%s должен быть целым числом от -10 до 100" % [path, risk_id])


static func _validate_conditions(raw_conditions: Variant, prefix: String, errors: Array[String]) -> void:
	if not raw_conditions is Array:
		errors.append("%s.conditions должен быть массивом" % prefix)
		return
	for index: int in raw_conditions.size():
		var raw_condition: Variant = raw_conditions[index]
		var path := "%s.conditions[%d]" % [prefix, index]
		if not raw_condition is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var condition_type := String(raw_condition.get("type", ""))
		var identifier := String(raw_condition.get("id", "")).strip_edges()
		var minimum: Variant = raw_condition.get("minimum", null)
		match condition_type:
			"characteristic":
				if not GameRules.is_known_characteristic(identifier) or not _integer_in_range(minimum, 1, 10):
					errors.append("%s содержит неизвестную характеристику или порог" % path)
			"skill":
				if not GameRules.is_known_skill(identifier) or not _integer_in_range(minimum, 0, GameRules.SKILL_MAX_RANK):
					errors.append("%s содержит неизвестный навык или ранг" % path)
			"item":
				if not ItemCatalogScript.has(identifier) or not _integer_in_range(minimum, 1, 999):
					errors.append("%s содержит неизвестный предмет или количество" % path)
			_:
				errors.append("%s.type «%s» не поддерживается" % [path, condition_type])


static func _valid_pair(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is Array or value.size() != 2:
		return false
	if not _integer_in_range(value[0], minimum, maximum):
		return false
	if not _integer_in_range(value[1], minimum, maximum):
		return false
	return int(value[0]) <= int(value[1])


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT:
		return false
	return int(value) >= minimum and int(value) <= maximum


static func _non_negative_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(value)) and float(value) >= 0.0


static func _point(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	if typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var point := Vector2(float(value[0]), float(value[1]))
	return point if is_finite(point.x) and is_finite(point.y) else null


static func _inside(point: Vector2, size: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= size.x and point.y <= size.y
