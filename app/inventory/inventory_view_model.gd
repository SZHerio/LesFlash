class_name InventoryViewModel
extends RefCounted

const InventoryState := preload("res://core/inventory/inventory_state.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const ActionView := preload("res://app/inventory/inventory_action_view.gd")
const UiModels := preload("res://app/ui_model_factory.gd")
const EquipmentRules := preload("res://game/equipment/equipment_rules.gd")

const CONTAINER_ORDER := ["pockets", "backpack", "hands"]
const CONTAINER_ICONS := {
	"pockets": "К",
	"backpack": "Р",
	"hands": "РК",
	"equipped": "Н",
}
const MODIFIER_TITLES := {
	"warmth": "Тепло",
	"travel_stamina": "Выносливость",
	"work_safety": "Безопасность",
	"search_reach": "Инструмент",
}
const TAG_TITLES := {
	"food": "Еда",
	"medical": "Медицина",
	"repair": "Ремонт",
	"material": "Материал",
	"recyclable": "Вторсырьё",
	"shelter": "Ночлег",
	"tool": "Инструмент",
	"equipment": "Снаряжение",
	"unknown": "Неизвестно",
}
const TAG_ICON_IDS := {
	"food": &"action_food",
	"medical": &"meta_item",
	"repair": &"action_work",
	"material": &"meta_item",
	"recyclable": &"place_recycling",
	"shelter": &"action_shelter",
	"tool": &"action_work",
	"equipment": &"nav_items",
	"unknown": &"meta_item",
}
const TAG_ICON_PRIORITY := [
	"food", "medical", "tool", "repair", "shelter", "equipment",
	"recyclable", "material", "unknown",
]


static func build(
	raw_model: Dictionary,
	shell_model: Dictionary,
	reduced_motion: bool,
	font_scale: float
) -> Dictionary:
	var inventory: Dictionary = Dictionary(raw_model.get("inventory", {})).duplicate(true)
	var strength := int(raw_model.get("strength", 1))
	var status: Dictionary = Dictionary(shell_model.get("status", {}))
	var calendar: Dictionary = Dictionary(status.get("calendar", {}))
	var containers := _containers(inventory, strength)
	var items := _items(
		inventory,
		containers,
		String(raw_model.get("location_id", ""))
	)
	var summary := _summary(containers)
	return {
		"header": {
			"district_title": "ПРИРЕЧНЫЙ РАЙОН",
			"location_title": "Вещи",
			"date_text": UiModels.format_date(calendar, font_scale >= 1.5),
			"time_text": UiModels.format_time(calendar),
			"money": int(status.get("money", 0)),
			"show_settings": true,
		},
		"location_title": String(raw_model.get("location_title", "Текущее место")),
		"summary": summary,
		"equipment": _equipment(Dictionary(raw_model.get("equipment", {}))),
		"containers": containers,
		"items": items,
		"selected_stack_id": String(inventory.get("selected_stack_id", "")),
		"reduced_motion": reduced_motion,
		"font_scale": font_scale,
	}


static func _containers(inventory: Dictionary, strength: int) -> Array:
	var result: Array = []
	var raw_containers: Dictionary = inventory.get("containers", {})
	for container_id in _container_order(raw_containers):
		if not raw_containers.has(container_id):
			continue
		var source: Dictionary = raw_containers[container_id]
		var limits := InventoryState.capacity(inventory, container_id, strength)
		var count := Array(source.get("stacks", [])).size()
		result.append({
			"id": container_id,
			"title": String(source.get("title", container_id)),
			"icon_text": String(CONTAINER_ICONS.get(container_id, "•")),
			"active": bool(source.get("active", true)),
			"count": count,
			"mass": _dimension(
				int(limits.get("mass_used_grams", 0)),
				int(limits.get("mass_capacity_grams", 0)),
				"mass"
			),
			"volume": _dimension(
				int(limits.get("volume_used_ml", 0)),
				int(limits.get("volume_capacity_ml", 0)),
				"volume"
			),
			"overloaded": bool(limits.get("mass_overloaded", false))
				or bool(limits.get("volume_overloaded", false)),
			"managed": EquipmentRules.is_managed_container_id(container_id),
			"worn": container_id == EquipmentRules.EQUIPPED_CONTAINER_ID,
		})
	var external: Dictionary = inventory.get("external_containers", {})
	for container_id in external:
		var source: Dictionary = external[container_id]
		result.append({
			"id": String(container_id),
			"title": String(source.get("title", "Рядом")),
			"icon_text": "Р",
			"active": true,
			"external": true,
			"count": Array(source.get("stacks", [])).size(),
			"mass": _dimension(0, -1, "mass"),
			"volume": _dimension(0, -1, "volume"),
			"overloaded": false,
			"managed": false,
			"worn": false,
		})
	return result


## Pockets, the pack and the hands keep their fixed order because the player
## learns it; anything a worn bag adds follows, sorted so the list never jumps.
static func _container_order(raw_containers: Dictionary) -> Array[String]:
	var result: Array[String] = []
	result.assign(CONTAINER_ORDER)
	var extra: Array[String] = []
	for raw_id: Variant in raw_containers:
		var container_id := String(raw_id)
		if container_id not in CONTAINER_ORDER:
			extra.append(container_id)
	extra.sort()
	result.append_array(extra)
	return result


static func _items(
	inventory: Dictionary,
	containers: Array,
	location_id: String
) -> Array:
	var container_titles: Dictionary = {}
	var movable_targets: Array = []
	for raw_container in containers:
		if not raw_container is Dictionary:
			continue
		var container: Dictionary = raw_container
		container_titles[String(container.get("id", ""))] = String(container.get("title", ""))
		# What is worn is put on and taken off, never dragged like cargo, so the
		# worn container is not offered as a destination.
		if (
			bool(container.get("active", false))
			and not bool(container.get("external", false))
			and not bool(container.get("worn", false))
		):
			movable_targets.append({
				"id": String(container.get("id", "")),
				"title": String(container.get("title", "")),
			})
	var result: Array = []
	for raw_stack in InventoryState.all_stacks(inventory):
		if not raw_stack is Dictionary:
			continue
		var stack: Dictionary = raw_stack
		var definition: Variant = ItemCatalog.definition(String(stack.get("item_id", "")))
		var quantity := int(stack.get("quantity", 0))
		var actions: Array = []
		var external := bool(stack.get("external", false))
		var worn := String(stack.get("container_id", "")) == EquipmentRules.EQUIPPED_CONTAINER_ID
		if external:
			actions.append(ActionView.build("pick_up", "Забрать", {}, quantity, "accent"))
		elif worn:
			actions.append(ActionView.build("unequip", "Снять", {}, 1, "normal"))
		else:
			if movable_targets.size() > 1:
				actions.append(ActionView.build("move", "Переложить", {}, quantity, "move"))
			if not String(definition.equip_slot()).is_empty():
				var equip_action: Dictionary = definition.action("equip")
				actions.append(ActionView.build(
					"equip",
					String(equip_action.get("title", "Надеть")),
					equip_action,
					1,
					"accent"
				))
			for action_id in definition.allowed_actions():
				if action_id in ["use", "disassemble", "drop"]:
					var action: Dictionary = definition.action(action_id)
					actions.append(ActionView.build(
						action_id,
						String(action.get("title", action_id)),
						action,
						quantity,
						"danger" if action_id == "drop" else "normal"
					))
			if location_id == "recycling_point" and "recyclable" in definition.tags():
				actions.append(ActionView.build(
					"sell",
					"Сдать в приёмный пункт",
					{},
					quantity,
					"accent"
				))
		result.append({
			"stack_id": String(stack.get("stack_id", "")),
			"item_id": definition.id(),
			"title": definition.title(),
			"description": definition.description(),
			"quantity": quantity,
			"quantity_text": "×%d" % quantity if quantity > 1 else "",
			"container_id": String(stack.get("container_id", "")),
			"container_title": String(container_titles.get(stack.get("container_id", ""), "Неизвестное место")),
			"mass_text": _format_mass(definition.mass_grams() * quantity),
			"volume_text": _format_volume(definition.volume_ml() * quantity),
			"mass_grams": definition.mass_grams() * quantity,
			"volume_ml": definition.volume_ml() * quantity,
			"condition": int(stack.get("condition", 100)),
			"condition_text": _condition_text(int(stack.get("condition", 100))),
			"tags": _tag_titles(definition.tags()),
			"item_icon_id": _item_icon_id(definition.tags()),
			"actions": actions,
			"move_targets": movable_targets.duplicate(true),
			"unknown_fallback": definition.is_unknown(),
			"external": external,
			"worn": worn,
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("title", "")).naturalnocasecmp_to(String(right.get("title", ""))) < 0
	)
	return result


## What the outfit is doing right now, in the hero's words rather than in the
## keys the domain uses. An empty slot says nothing at all.
static func _equipment(source: Dictionary) -> Dictionary:
	var slots: Array = []
	for raw_slot: Variant in Array(source.get("slots", [])):
		if not raw_slot is Dictionary:
			continue
		var slot: Dictionary = raw_slot
		slots.append({
			"slot_id": String(slot.get("slot_id", "")),
			"title": String(slot.get("title", "")),
			"occupied": bool(slot.get("occupied", false)),
			"stack_id": String(slot.get("stack_id", "")),
			"item_title": String(slot.get("item_title", "")),
			"value_text": String(slot.get("item_title", "")) if bool(slot.get("occupied", false)) else "Пусто",
		})
	var effects: Array = []
	var modifiers: Dictionary = Dictionary(source.get("modifiers", {}))
	for modifier_id: String in MODIFIER_TITLES:
		var value := int(modifiers.get(modifier_id, 0))
		if value <= 0:
			continue
		effects.append({
			"id": modifier_id,
			"title": String(MODIFIER_TITLES[modifier_id]),
			"value": value,
			"value_text": "+%d" % value,
		})
	return {
		"slots": slots,
		"effects": effects,
		"message": (
			"Снаряжение работает, пока надето."
			if not effects.is_empty()
			else "Ничего не надето: холод, работа и поиск обходятся дороже."
		),
	}


static func _summary(containers: Array) -> Dictionary:
	var mass_used := 0
	var mass_capacity := 0
	var volume_used := 0
	var volume_capacity := 0
	var overloaded := false
	for raw_container in containers:
		if not raw_container is Dictionary:
			continue
		var container: Dictionary = raw_container
		if not bool(container.get("active", false)) or bool(container.get("external", false)):
			continue
		var mass: Dictionary = container.get("mass", {})
		var volume: Dictionary = container.get("volume", {})
		mass_used += int(mass.get("used", 0))
		mass_capacity += maxi(int(mass.get("capacity", 0)), 0)
		volume_used += int(volume.get("used", 0))
		volume_capacity += maxi(int(volume.get("capacity", 0)), 0)
		overloaded = overloaded or bool(container.get("overloaded", false))
	return {
		"mass": _dimension(mass_used, mass_capacity, "mass"),
		"volume": _dimension(volume_used, volume_capacity, "volume"),
		"overloaded": overloaded,
		"message": (
			"Перегруз виден заранее: переложите или оставьте часть вещей."
			if overloaded
			else "Сила увеличивает переносимую массу, но не объём контейнеров."
		),
	}


static func _dimension(used: int, capacity: int, kind: String) -> Dictionary:
	var ratio := 0.0 if capacity <= 0 else float(used) / float(capacity)
	return {
		"used": used,
		"capacity": capacity,
		"ratio": clampf(ratio, 0.0, 1.5),
		"value_text": (
			"%s / %s" % [_format_mass(used), _format_mass(capacity)]
			if kind == "mass"
			else "%s / %s" % [_format_volume(used), _format_volume(capacity)]
		),
		"state": "overload" if ratio > 1.0 else ("warning" if ratio >= 0.8 else "normal"),
	}


static func _format_mass(grams: int) -> String:
	if grams < 1000:
		return "%d г" % grams
	return ("%.1f кг" % (float(grams) / 1000.0)).replace(".", ",")


static func _format_volume(ml: int) -> String:
	if ml < 1000:
		return "%d мл" % ml
	return ("%.1f л" % (float(ml) / 1000.0)).replace(".", ",")


static func _condition_text(value: int) -> String:
	if value >= 85:
		return "Хорошее состояние"
	if value >= 55:
		return "Изношено"
	if value >= 25:
		return "Сильно изношено"
	return "Почти испорчено"


static func _tag_titles(raw_tags: Array) -> Array:
	var result: Array = []
	for raw_tag in raw_tags:
		var tag := String(raw_tag)
		if TAG_TITLES.has(tag):
			result.append(String(TAG_TITLES[tag]))
	return result.slice(0, 3)


static func _item_icon_id(raw_tags: Array) -> StringName:
	for tag: String in TAG_ICON_PRIORITY:
		if tag in raw_tags:
			return StringName(TAG_ICON_IDS[tag])
	return &"meta_item"
