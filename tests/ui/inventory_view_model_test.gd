extends SceneTree

const InventoryModels := preload("res://app/inventory/inventory_view_model.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")
const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")


func _init() -> void:
	var state := RunState.new({
		"strength": 3,
		"charisma": 5,
		"intelligence": 6,
		"luck": 4,
	}, 51_001)
	state.add_item("cardboard_sheet", 1)
	state.add_item("medicine_blister", 1)
	state.add_item("forgotten_v2_item", 1)
	state.inventory = InventoryStateScript.ensure_external_container(
		state.inventory,
		"ground:underpass",
		"На земле"
	)
	var ground_addition := InventoryStateScript.add_item(
		state.inventory,
		"plastic_bottle",
		2,
		100,
		"ground:underpass",
		state.get_characteristic("strength")
	)
	if not bool(ground_addition.get("ok", false)):
		_fail("external pickup fixture could not be created")
		return
	state.inventory = ground_addition["inventory"]
	var first: Dictionary = InventoryStateScript.all_stacks(state.inventory)[0]
	state.inventory = InventoryStateScript.set_selected_stack(
		state.inventory,
		String(first.get("stack_id", ""))
	)
	var raw := {
		"inventory": state.inventory.duplicate(true),
		"strength": state.get_characteristic("strength"),
		"location_title": "Подземный переход",
	}
	var shell := {
		"status": {
			"money": 17,
			"calendar": state.calendar.current_stamp(),
		},
	}
	var before := raw.duplicate(true)
	var model := InventoryModels.build(raw, shell, true, 2.0)
	if raw != before:
		_fail("builder mutated its domain input")
		return
	if not bool(model.get("reduced_motion", false)):
		_fail("reduced motion was lost")
		return
	if String(Dictionary(model.get("header", {})).get("date_text", "")).is_empty():
		_fail("header date was not formatted")
		return
	var items: Array = model.get("items", [])
	if items.size() != 4:
		_fail("carried and external stacks did not become four item cards")
		return
	for item: Dictionary in items:
		var item_icon_id := StringName(item.get("item_icon_id", &""))
		if not IconRegistryScript.has(item_icon_id):
			_fail("item card has no registered explicit icon ID")
			return
	var unknown := _item(items, "forgotten_v2_item")
	if not bool(unknown.get("unknown_fallback", false)):
		_fail("unknown legacy item was not marked as fallback")
		return
	if Array(unknown.get("actions", [])).size() != 2:
		_fail("fallback should expose only move and drop")
		return
	var external := _item(items, "plastic_bottle")
	var pickup_actions: Array = external.get("actions", [])
	if (
		not bool(external.get("external", false))
		or pickup_actions.size() != 1
		or String(Dictionary(pickup_actions[0]).get("id", "")) != "pick_up"
		or not bool(Dictionary(pickup_actions[0]).get("quantity_adjustable", false))
	):
		_fail("external stack must expose only adjustable pickup")
		return
	var medicine := _item(items, "medicine_blister")
	var use_action: Dictionary = _action(Array(medicine.get("actions", [])), "use")
	if (
		int(use_action.get("duration_minutes", -1)) != 3
		or Array(use_action.get("effect_lines", [])).size() != 2
	):
		_fail("item action must expose exact duration and effects")
		return
	var mass_text := String(Dictionary(Dictionary(model["summary"]).get("mass", {})).get("value_text", ""))
	if not ("кг" in mass_text or "г" in mass_text):
		_fail("mass summary has no Russian unit")
		return
	if model.get("selected_stack_id") != first.get("stack_id"):
		_fail("selected stack was not restored")
		return
	print("M3C INVENTORY VIEW-MODEL TEST PASSED: pure, Russian units, fallback and selection")
	quit(0)


func _item(items: Array, item_id: String) -> Dictionary:
	for raw_item in items:
		if raw_item is Dictionary and String(raw_item.get("item_id", "")) == item_id:
			return raw_item
	return {}


func _action(actions: Array, action_id: String) -> Dictionary:
	for raw_action in actions:
		if raw_action is Dictionary and String(raw_action.get("id", "")) == action_id:
			return raw_action
	return {}


func _fail(message: String) -> void:
	push_error("M3C INVENTORY VIEW-MODEL FAILED: %s" % message)
	quit(1)
