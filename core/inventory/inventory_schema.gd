extends RefCounted

const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const Metadata := preload("res://core/inventory/inventory_metadata.gd")
const SCHEMA_VERSION := 1
const CORE_CONTAINER_IDS := ["hands", "pockets", "backpack"]
const LEGACY_QUANTITY_ENCODING := "legacy_v2_compact"
const LEGACY_QUANTITY_MAX := 1_000_000


static func fresh() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"selected_stack_id": "",
		"next_stack_sequence": 1,
		"containers": {
			"hands": make_container("hands", "В руках", "hands", true, 1500, 850, 9000),
			"pockets": make_container("pockets", "Карманы", "pockets", true, 1000, 180, 3200),
			"backpack": make_container("backpack", "Рюкзак", "backpack", false, 3000, 700, 24000),
		},
		"external_containers": {},
	}


static func make_container(
	container_id: String,
	title: String,
	kind: String,
	active: bool,
	base_mass: int,
	mass_per_strength: int,
	volume: int
) -> Dictionary:
	return {
		"id": container_id,
		"title": title,
		"kind": kind,
		"active": active,
		"base_mass_capacity_grams": base_mass,
		"mass_per_strength_grams": mass_per_strength,
		"volume_capacity_ml": volume,
		"stacks": [],
	}


static func normalize_serialized(value: Dictionary) -> Dictionary:
	return _normalize_numbers(value)


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["inventory must be a dictionary"]}
	var inventory: Dictionary = value
	if int(inventory.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("inventory.schema_version is unsupported")
	if typeof(inventory.get("selected_stack_id", null)) != TYPE_STRING:
		errors.append("inventory.selected_stack_id must be a string")
	var next_sequence: Variant = inventory.get("next_stack_sequence", null)
	if typeof(next_sequence) != TYPE_INT or int(next_sequence) < 1:
		errors.append("inventory.next_stack_sequence must be a positive integer")
	for field in ["containers", "external_containers"]:
		if not inventory.get(field, null) is Dictionary:
			errors.append("inventory.%s must be a dictionary" % field)
	for container_id in CORE_CONTAINER_IDS:
		var containers: Dictionary = inventory.get("containers", {})
		if not containers.has(container_id):
			errors.append("inventory.containers.%s is missing" % container_id)
	var stack_ids: Dictionary = {}
	for group_name in ["containers", "external_containers"]:
		var group: Dictionary = inventory.get(group_name, {})
		for raw_container_id in group:
			_validate_container(
				String(raw_container_id),
				group[raw_container_id],
				"inventory.%s.%s" % [group_name, raw_container_id],
				stack_ids,
				errors
			)
	var selected := String(inventory.get("selected_stack_id", ""))
	if not selected.is_empty() and not stack_ids.has(selected):
		errors.append("inventory.selected_stack_id points to a missing stack")
	if not bool(ItemCatalog.validation().get("ok", false)):
		errors.append("item catalog is invalid")
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_container(
	container_id: String,
	value: Variant,
	path: String,
	stack_ids: Dictionary,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("%s must be a dictionary" % path)
		return
	var container: Dictionary = value
	if String(container.get("id", "")) != container_id:
		errors.append("%s.id disagrees with its key" % path)
	for field in ["title", "kind"]:
		if typeof(container.get(field, null)) != TYPE_STRING or String(container[field]).is_empty():
			errors.append("%s.%s must be a non-empty string" % [path, field])
	if typeof(container.get("active", null)) != TYPE_BOOL:
		errors.append("%s.active must be boolean" % path)
	for field in ["base_mass_capacity_grams", "volume_capacity_ml"]:
		if typeof(container.get(field, null)) != TYPE_INT or int(container[field]) < -1:
			errors.append("%s.%s must be an integer >= -1" % [path, field])
	if (
		typeof(container.get("mass_per_strength_grams", null)) != TYPE_INT
		or int(container.get("mass_per_strength_grams", -1)) < 0
	):
		errors.append("%s.mass_per_strength_grams must be non-negative" % path)
	if not container.get("stacks", null) is Array:
		errors.append("%s.stacks must be an array" % path)
		return
	for index in range(container["stacks"].size()):
		_validate_stack(container["stacks"][index], "%s.stacks[%d]" % [path, index], stack_ids, errors)


static func _validate_stack(
	value: Variant,
	path: String,
	stack_ids: Dictionary,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("%s must be a dictionary" % path)
		return
	var stack: Dictionary = value
	var stack_id := String(stack.get("stack_id", ""))
	var item_id := String(stack.get("item_id", ""))
	if stack_id.is_empty() or stack_ids.has(stack_id):
		errors.append("%s.stack_id is empty or duplicated" % path)
	else:
		stack_ids[stack_id] = true
	if item_id.is_empty():
		errors.append("%s.item_id is empty" % path)
	var quantity: Variant = stack.get("quantity", null)
	if typeof(quantity) != TYPE_INT or int(quantity) < 1:
		errors.append("%s.quantity must be a positive integer" % path)
	var quantity_encoding: Variant = stack.get("quantity_encoding", null)
	var has_quantity_encoding := stack.has("quantity_encoding")
	if has_quantity_encoding and (
		typeof(quantity_encoding) != TYPE_STRING
		or String(quantity_encoding) != LEGACY_QUANTITY_ENCODING
	):
		errors.append("%s.quantity_encoding is unsupported" % path)
	if typeof(quantity) == TYPE_INT and int(quantity) >= 1:
		if has_quantity_encoding and quantity_encoding == LEGACY_QUANTITY_ENCODING:
			if int(quantity) > LEGACY_QUANTITY_MAX:
				errors.append("%s.quantity exceeds the legacy migration limit" % path)
		elif int(quantity) > ItemCatalog.definition(item_id).stack_limit():
			errors.append("%s.quantity exceeds the item stack limit" % path)
	var condition: Variant = stack.get("condition", null)
	if typeof(condition) != TYPE_INT or int(condition) < 0 or int(condition) > 100:
		errors.append("%s.condition must be in 0..100" % path)
	var metadata: Variant = stack.get("metadata", null)
	if not metadata is Dictionary:
		errors.append("%s.metadata must be a dictionary" % path)
	else:
		var metadata_validation := Metadata.validate(metadata, "%s.metadata" % path)
		for error in Array(metadata_validation.get("errors", [])):
			errors.append(String(error))


static func _normalize_numbers(value: Variant) -> Variant:
	return Metadata.normalize(value)
