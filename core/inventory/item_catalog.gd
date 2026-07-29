class_name ItemCatalog
extends RefCounted

const ItemDefinitionScript := preload("res://core/inventory/item_definition.gd")
const DATA_PATH := "res://game/items/data/item_catalog_v1.json"
const SCHEMA_VERSION := 1
const ACTION_IDS := [
	"use",
	"equip",
	"disassemble",
	## Making something out of this and whatever else the recipe asks for. One
	## per item, because the item is what names the recipe: a broken radio is
	## repaired, wire is twisted, tea is brewed strong.
	"craft",
	"drop",
	"give",
	"sell",
]

## One slot holds one item. `bag` is the only slot whose item carries other
## things, so it is the only slot allowed to declare a container.
const EQUIP_SLOT_IDS := ["torso", "feet", "gloves", "tool", "bedding", "bag"]
const EQUIP_MODIFIER_IDS := ["warmth", "travel_stamina", "work_safety", "search_reach"]
const EQUIP_MODIFIER_MAX := 100
const EQUIP_CONTAINER_FIELDS := [
	"base_mass_capacity_grams",
	"mass_per_strength_grams",
	"volume_capacity_ml",
]

static var _definitions: Dictionary = {}
static var _validation: Dictionary = {}


static func definition(item_id: String) -> RefCounted:
	_ensure_loaded()
	if _definitions.has(item_id):
		return _definitions[item_id] as RefCounted
	return ItemDefinitionScript.new({
		"id": item_id,
		"title": "Неизвестный предмет",
		"description": "Предмет из старого сохранения. Его можно сохранить или выбросить; данные не были удалены.",
		"tags": ["legacy", "unknown"],
		"stack_limit": 999,
		"mass_grams": 100,
		"volume_ml": 100,
		"base_value": 0,
		"actions": {
			"drop": {
				"title": "Оставить",
				"duration_minutes": 0,
				"conditions": [],
				"effects": [],
			},
		},
		"unknown_fallback": true,
	})


static func all_definitions() -> Array:
	_ensure_loaded()
	var ids: Array = _definitions.keys()
	ids.sort()
	var result: Array = []
	for item_id in ids:
		result.append(_definitions[item_id])
	return result


static func has(item_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(item_id)


static func validation() -> Dictionary:
	_ensure_loaded()
	return _validation.duplicate(true)


static func reset_cache_for_tests() -> void:
	_definitions.clear()
	_validation.clear()


static func _ensure_loaded() -> void:
	if not _validation.is_empty():
		return
	var errors: Array[String] = []
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_validation = {"ok": false, "errors": ["Не удалось открыть каталог предметов."]}
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		_validation = {"ok": false, "errors": ["Каталог предметов содержит некорректный JSON."]}
		return
	var root: Dictionary = parser.data
	if int(root.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("Ожидалась версия каталога %d." % SCHEMA_VERSION)
	var raw_items: Variant = root.get("items", null)
	if not raw_items is Array:
		errors.append("Поле items должно быть массивом.")
	else:
		for index in range(raw_items.size()):
			_validate_and_add(raw_items[index], index, errors)
	for definition_value in _definitions.values():
		var item: Variant = definition_value
		var disassemble: Dictionary = item.action("disassemble")
		for output_value in Array(disassemble.get("outputs", [])):
			if not output_value is Dictionary:
				continue
			var output_id := String(output_value.get("item_id", ""))
			if not _definitions.has(output_id):
				errors.append("%s: разбор ссылается на неизвестный предмет %s." % [item.id(), output_id])
	for required_id in ["cardboard_sheet", "simple_meal", "scrap_wire", "recyclables"]:
		if not _definitions.has(required_id):
			errors.append("Отсутствует legacy-предмет %s." % required_id)
	_validation = {"ok": errors.is_empty(), "errors": errors}
	if not errors.is_empty():
		_definitions.clear()


static func _validate_and_add(raw_value: Variant, index: int, errors: Array[String]) -> void:
	if not raw_value is Dictionary:
		errors.append("items[%d] должен быть объектом." % index)
		return
	var raw: Dictionary = raw_value
	var item_id := String(raw.get("id", "")).strip_edges()
	if item_id.is_empty():
		errors.append("items[%d].id не задан." % index)
		return
	if _definitions.has(item_id):
		errors.append("Повторяющийся id предмета: %s." % item_id)
		return
	for field in ["title", "description"]:
		if typeof(raw.get(field, null)) != TYPE_STRING or String(raw[field]).strip_edges().is_empty():
			errors.append("%s.%s должен содержать русский текст." % [item_id, field])
	for field in ["stack_limit", "mass_grams", "volume_ml", "base_value"]:
		if not _is_non_negative_integer(raw.get(field, null)):
			errors.append("%s.%s должен быть целым неотрицательным числом." % [item_id, field])
	if int(raw.get("stack_limit", 0)) < 1:
		errors.append("%s.stack_limit должен быть не меньше 1." % item_id)
	if not raw.get("tags", null) is Array:
		errors.append("%s.tags должен быть массивом." % item_id)
	var actions: Variant = raw.get("actions", null)
	if not actions is Dictionary:
		errors.append("%s.actions должен быть объектом." % item_id)
		return
	for action_id in actions:
		if String(action_id) not in ACTION_IDS:
			errors.append("%s содержит неизвестное действие %s." % [item_id, action_id])
		var action_value: Variant = actions[action_id]
		if not action_value is Dictionary:
			errors.append("%s.actions.%s должен быть объектом." % [item_id, action_id])
			continue
		var action: Dictionary = action_value
		if typeof(action.get("title", null)) != TYPE_STRING or String(action["title"]).is_empty():
			errors.append("%s.actions.%s.title не задан." % [item_id, action_id])
		if not _is_non_negative_integer(action.get("duration_minutes", 0)):
			errors.append("%s.actions.%s.duration_minutes некорректен." % [item_id, action_id])
		if action.has("consumes") and typeof(action["consumes"]) != TYPE_BOOL:
			errors.append("%s.actions.%s.consumes должен быть булевым." % [item_id, action_id])
		if not action.get("conditions", []) is Array or not action.get("effects", []) is Array:
			errors.append("%s.actions.%s conditions/effects должны быть массивами." % [item_id, action_id])
		if String(action_id) == "equip":
			_validate_equip(item_id, action, errors)
	_definitions[item_id] = ItemDefinitionScript.new(raw)


static func _validate_equip(item_id: String, action: Dictionary, errors: Array[String]) -> void:
	var slot := String(action.get("slot", ""))
	if slot not in EQUIP_SLOT_IDS:
		errors.append("%s.actions.equip.slot должен быть одним из %s." % [item_id, str(EQUIP_SLOT_IDS)])
	var modifiers: Variant = action.get("modifiers", null)
	if not modifiers is Dictionary:
		errors.append("%s.actions.equip.modifiers должен быть объектом." % item_id)
	else:
		for raw_modifier_id: Variant in Dictionary(modifiers):
			var modifier_id := String(raw_modifier_id)
			if modifier_id not in EQUIP_MODIFIER_IDS:
				errors.append("%s.actions.equip.modifiers содержит неизвестный модификатор %s." % [item_id, modifier_id])
				continue
			var value: Variant = Dictionary(modifiers)[raw_modifier_id]
			if not _is_non_negative_integer(value) or int(value) > EQUIP_MODIFIER_MAX:
				errors.append("%s.actions.equip.modifiers.%s должен быть целым числом от 0 до %d." % [
					item_id, modifier_id, EQUIP_MODIFIER_MAX,
				])
	var container: Variant = action.get("container", null)
	if container == null:
		if slot == "bag":
			errors.append("%s занимает слот bag и обязан описывать переносимый контейнер." % item_id)
		return
	if slot != "bag":
		errors.append("%s описывает контейнер, но не занимает слот bag." % item_id)
	if not container is Dictionary:
		errors.append("%s.actions.equip.container должен быть объектом." % item_id)
		return
	var spec: Dictionary = container
	for field: String in ["title", "kind"]:
		if typeof(spec.get(field, null)) != TYPE_STRING or String(spec[field]).strip_edges().is_empty():
			errors.append("%s.actions.equip.container.%s не задан." % [item_id, field])
	for field: String in EQUIP_CONTAINER_FIELDS:
		if not _is_non_negative_integer(spec.get(field, null)):
			errors.append("%s.actions.equip.container.%s должен быть целым неотрицательным числом." % [item_id, field])


static func _is_non_negative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= 0.0
