class_name EquipmentRules
extends RefCounted

## Pure rules for worn equipment and the containers a worn bag adds.
##
## Everything lives inside the existing inventory dictionary: worn items sit in
## one managed container and a worn bag owns a container of its own. Nothing
## here mutates a live session — callers work on candidates and commit through
## their own atomic transaction.

const Schema := preload("res://core/inventory/inventory_schema.gd")
const Query := preload("res://core/inventory/inventory_query.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")

const EQUIPPED_CONTAINER_ID := "equipped"
const EQUIPPED_CONTAINER_TITLE := "Надето"
const EQUIPPED_CONTAINER_KIND := "equipped"
const BAG_CONTAINER_PREFIX := "bag:"

## Worn gear hangs on the body rather than being packed, so volume never binds
## it; mass does, and strength is what decides how much a person can wear at
## once. Strength 1 carries the jacket or the boots, not both.
const EQUIPPED_BASE_MASS_GRAMS := 2500
const EQUIPPED_MASS_PER_STRENGTH_GRAMS := 800
const EQUIPPED_VOLUME_ML := 30_000

const MODIFIER_IDS := ItemCatalog.EQUIP_MODIFIER_IDS
const MODIFIER_MAX := 100

const SLOT_TITLES := {
	"torso": "Верх",
	"feet": "Обувь",
	"gloves": "Руки",
	"tool": "Инструмент",
	"bedding": "Спальное",
	"bag": "Сумка",
}


static func neutral_modifiers() -> Dictionary:
	var result: Dictionary = {}
	for modifier_id: String in MODIFIER_IDS:
		result[modifier_id] = 0
	return result


static func bag_container_id(stack_id: String) -> String:
	return "%s%s" % [BAG_CONTAINER_PREFIX, stack_id]


static func is_bag_container_id(container_id: String) -> bool:
	return container_id.begins_with(BAG_CONTAINER_PREFIX)


static func is_managed_container_id(container_id: String) -> bool:
	return container_id == EQUIPPED_CONTAINER_ID or is_bag_container_id(container_id)


static func ensure_equipped_container(inventory: Dictionary) -> Dictionary:
	var candidate := inventory.duplicate(true)
	var containers: Dictionary = candidate.get("containers", {})
	if not containers.has(EQUIPPED_CONTAINER_ID):
		containers[EQUIPPED_CONTAINER_ID] = Schema.make_container(
			EQUIPPED_CONTAINER_ID,
			EQUIPPED_CONTAINER_TITLE,
			EQUIPPED_CONTAINER_KIND,
			true,
			EQUIPPED_BASE_MASS_GRAMS,
			EQUIPPED_MASS_PER_STRENGTH_GRAMS,
			EQUIPPED_VOLUME_ML
		)
	candidate["containers"] = containers
	return candidate


static func add_bag_container(
	inventory: Dictionary,
	stack_id: String,
	specification: Dictionary
) -> Dictionary:
	var container_id := bag_container_id(stack_id)
	var candidate := inventory.duplicate(true)
	var containers: Dictionary = candidate.get("containers", {})
	if containers.has(container_id):
		return {"ok": false, "code": "bag_already_open", "error": "Эта сумка уже носится"}
	containers[container_id] = Schema.make_container(
		container_id,
		String(specification.get("title", "Сумка")),
		String(specification.get("kind", "bag")),
		true,
		int(specification.get("base_mass_capacity_grams", 0)),
		int(specification.get("mass_per_strength_grams", 0)),
		int(specification.get("volume_capacity_ml", 0))
	)
	candidate["containers"] = containers
	return {"ok": true, "code": "ok", "error": "", "inventory": candidate, "container_id": container_id}


static func remove_bag_container(inventory: Dictionary, stack_id: String) -> Dictionary:
	var container_id := bag_container_id(stack_id)
	var candidate := inventory.duplicate(true)
	var containers: Dictionary = candidate.get("containers", {})
	if not containers.has(container_id):
		return {"ok": true, "code": "ok", "error": "", "inventory": candidate}
	var container: Dictionary = containers[container_id]
	if not Array(container.get("stacks", [])).is_empty():
		return {
			"ok": false,
			"code": "bag_not_empty",
			"error": "Сначала выложите вещи из сумки",
			"container_id": container_id,
		}
	containers.erase(container_id)
	candidate["containers"] = containers
	return {"ok": true, "code": "ok", "error": "", "inventory": candidate}


static func equipped_stacks(inventory: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var located := Query.locate_container(inventory, EQUIPPED_CONTAINER_ID)
	if located.is_empty():
		return result
	for raw_stack: Variant in Array(Dictionary(located["container"]).get("stacks", [])):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = Dictionary(raw_stack).duplicate(true)
		stack["container_id"] = EQUIPPED_CONTAINER_ID
		result.append(stack)
	return result


static func is_equipped(inventory: Dictionary, stack_id: String) -> bool:
	for stack: Dictionary in equipped_stacks(inventory):
		if String(stack.get("stack_id", "")) == stack_id:
			return true
	return false


static func slot_of_stack(stack: Dictionary) -> String:
	var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
	return String(definition.equip_slot())


static func slot_occupant(inventory: Dictionary, slot_id: String) -> Dictionary:
	for stack: Dictionary in equipped_stacks(inventory):
		if slot_of_stack(stack) == slot_id:
			return stack
	return {}


## One number per effect, summed over everything worn and bounded, so a consumer
## never has to know which item produced it.
static func modifiers(inventory: Dictionary) -> Dictionary:
	var result := neutral_modifiers()
	for stack: Dictionary in equipped_stacks(inventory):
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		var authored: Dictionary = definition.equip_modifiers()
		var condition := clampi(int(stack.get("condition", 100)), 0, 100)
		for raw_id: Variant in authored:
			var modifier_id := String(raw_id)
			if modifier_id not in MODIFIER_IDS:
				continue
			# Worn-out gear protects less than the same gear in good repair.
			@warning_ignore("integer_division")
			var scaled: int = int(authored[raw_id]) * condition / 100
			result[modifier_id] = mini(int(result[modifier_id]) + scaled, MODIFIER_MAX)
	return result


static func modifier(inventory: Dictionary, modifier_id: String) -> int:
	return int(modifiers(inventory).get(modifier_id, 0))


static func slots_model(inventory: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id: String in ItemCatalog.EQUIP_SLOT_IDS:
		var occupant := slot_occupant(inventory, slot_id)
		var definition: Variant = ItemCatalog.definition(String(occupant.get("item_id", "")))
		result.append({
			"slot_id": slot_id,
			"title": String(SLOT_TITLES.get(slot_id, slot_id)),
			"occupied": not occupant.is_empty(),
			"stack_id": String(occupant.get("stack_id", "")),
			"item_id": String(occupant.get("item_id", "")),
			"item_title": String(definition.title()) if not occupant.is_empty() else "",
			"condition": int(occupant.get("condition", 0)) if not occupant.is_empty() else 0,
		})
	return result


static func open_bag_container_ids(inventory: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in Dictionary(inventory.get("containers", {})):
		var container_id := String(raw_id)
		if is_bag_container_id(container_id):
			result.append(container_id)
	result.sort()
	return result
