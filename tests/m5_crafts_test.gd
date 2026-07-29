extends SceneTree

## M5 stage 4: making something out of what was found.
##
## Crafting is not a new system. An item action already consumed the thing it
## was used on, checked conditions, applied effects and produced outputs — the
## only thing missing was recipes that ask for a skill and for other things in
## the pack. Building a parallel crafting engine would have been the mistake.
##
## What has to hold: a recipe refuses without the skill, refuses without the
## parts, consumes exactly what it says, and teaches the skill it uses.

const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")
const ItemCatalog = preload("res://core/inventory/item_catalog.gd")
const SkillCatalog = preload("res://game/skills/skill_catalog.gd")
const StoreCatalog = preload("res://game/commerce/store_catalog.gd")

## Eighteen points exactly, or the sandbox refuses to start and every check
## below passes by never running.
const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []


func _init() -> void:
	_test_recipes_are_declared_properly()
	_test_a_recipe_refuses_without_the_skill()
	_test_a_recipe_refuses_without_the_parts()
	_test_making_it_consumes_and_produces_and_teaches()
	_test_making_beats_selling_raw()
	_test_the_pawn_counter_pays_best_for_made_things()
	_finish()


func _adapter() -> SandboxSessionAdapter:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		_failures.append("the sandbox refused to start — every check below was skipped")
	return adapter


func _recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Variant in ItemCatalog.all_definitions():
		if not ("craft" in Array(definition.call("allowed_actions"))):
			continue
		var recipe: Dictionary = definition.call("action", "craft")
		if not recipe.is_empty():
			result.append({"item_id": String(definition.call("id")), "action": recipe})
	return result


func _test_recipes_are_declared_properly() -> void:
	var recipes := _recipes()
	_expect(recipes.size() >= 3, "there must be something worth making (found %d)" % recipes.size())
	var loaded := SkillCatalog.load_default()
	var catalog: Dictionary = Dictionary(loaded.get("catalog", {}))
	for recipe: Dictionary in recipes:
		var action: Dictionary = recipe["action"]
		_expect(
			int(action.get("duration_minutes", 0)) > 0,
			"%s is made in no time at all" % String(recipe["item_id"])
		)
		_expect(
			not Array(action.get("outputs", [])).is_empty(),
			"%s makes nothing" % String(recipe["item_id"])
		)
		# Making something is practice, and the catalog has to know which skill.
		var teaches := ""
		for raw_effect: Variant in Array(action.get("effects", [])):
			var effect: Dictionary = raw_effect
			if String(effect.get("type", "")) == "practice_skill":
				teaches = String(effect.get("source_id", ""))
		_expect(not teaches.is_empty(), "%s teaches nothing" % String(recipe["item_id"]))
		if teaches.is_empty():
			continue
		_expect(
			not SkillCatalog.skill_taught_by(catalog, teaches).is_empty(),
			"the skill catalog does not know the recipe source %s" % teaches
		)


func _test_a_recipe_refuses_without_the_skill() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	# Everything the recipe asks for except the hands to do it.
	_expect(session.run_state.add_item("broken_radio", 1, "pockets"), "the radio must go in the pack")
	session.run_state.add_item("small_parts", 2, "pockets")
	session.run_state.add_item("pliers", 1, "pockets")
	_expect_equal(int(session.run_state.get_skill_rank("repair")), 0, "the fixture must start unskilled")
	var stack_id := _stack_of(adapter, "broken_radio")
	_expect(stack_id != "", "the radio is not in the pack")
	if stack_id == "":
		return
	var refused: Dictionary = adapter.perform_inventory_action(stack_id, "craft")
	_expect(not bool(refused.get("ok", true)), "a radio was repaired by someone who cannot repair")
	_expect_equal(int(session.run_state.get_item_count("working_radio")), 0, "a working radio appeared anyway")


func _test_a_recipe_refuses_without_the_parts() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.set_skill_rank("repair", 1)
	_expect(session.run_state.add_item("broken_radio", 1, "pockets"), "the radio must go in the pack")
	session.run_state.add_item("pliers", 1, "pockets")
	var stack_id := _stack_of(adapter, "broken_radio")
	if stack_id == "":
		_failures.append("the radio is not in the pack")
		return
	var refused: Dictionary = adapter.perform_inventory_action(stack_id, "craft")
	_expect(not bool(refused.get("ok", true)), "a radio was repaired without any parts")


func _test_making_it_consumes_and_produces_and_teaches() -> void:
	var adapter: SandboxSessionAdapter = _adapter()
	if adapter == null:
		return
	var session = adapter.get("_session")
	session.run_state.set_skill_rank("repair", 1)
	_expect(session.run_state.add_item("broken_radio", 1, "pockets"), "the radio must go in the pack")
	session.run_state.add_item("small_parts", 2, "pockets")
	session.run_state.add_item("pliers", 1, "pockets")
	var practice_before := int(session.run_state.practice_sources("repair"))
	var stack_id := _stack_of(adapter, "broken_radio")
	if stack_id == "":
		_failures.append("the radio is not in the pack")
		return
	var made: Dictionary = adapter.perform_inventory_action(stack_id, "craft")
	_expect(bool(made.get("ok", false)), "the repair failed: %s" % str(made))
	if not bool(made.get("ok", false)):
		return
	_expect_equal(int(session.run_state.get_item_count("working_radio")), 1, "nothing was made")
	_expect_equal(int(session.run_state.get_item_count("broken_radio")), 0, "the broken radio survived")
	_expect_equal(int(session.run_state.get_item_count("small_parts")), 1, "the parts were not spent")
	_expect_equal(int(session.run_state.get_item_count("pliers")), 1, "the tool was consumed")
	_expect(
		int(session.run_state.practice_sources("repair")) > practice_before,
		"making something taught nothing"
	)


## The question the whole idea rests on: is making a thing worth more than
## selling what it was made of. If not, nobody would ever craft.
func _test_making_beats_selling_raw() -> void:
	for recipe: Dictionary in _recipes():
		var action: Dictionary = recipe["action"]
		var spent := _value_of(String(recipe["item_id"]), 1)
		for raw_effect: Variant in Array(action.get("effects", [])):
			var effect: Dictionary = raw_effect
			if String(effect.get("type", "")) == "remove_item":
				spent += _value_of(String(effect.get("id", "")), int(effect.get("quantity", 1)))
		var gained := 0
		for raw_output: Variant in Array(action.get("outputs", [])):
			var output: Dictionary = raw_output
			gained += _value_of(String(output.get("item_id", "")), int(output.get("quantity", 1)))
		_expect(
			gained > spent,
			"making from %s is worth less than its parts (%d out of %d)" % [
				String(recipe["item_id"]), gained, spent,
			]
		)


## The debt from stage 3: a district you pay a fare to reach has to be worth
## reaching. The pawn counter is what makes a made thing worth carrying across
## the city, so it must pay better than the counters at home.
func _test_the_pawn_counter_pays_best_for_made_things() -> void:
	var loaded := StoreCatalog.load_default()
	_expect(bool(loaded.get("ok", false)), "the store catalog does not load")
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]
	var payouts: Dictionary = {}
	var accepts: Dictionary = {}
	for raw_archetype: Variant in Array(catalog.get("archetypes", [])):
		var archetype: Dictionary = raw_archetype
		var policy: Dictionary = Dictionary(archetype.get("buyback_policy", {}))
		if not bool(policy.get("enabled", false)):
			continue
		payouts[String(archetype.get("archetype_id", ""))] = int(policy.get("payout_basis_points", 0))
		accepts[String(archetype.get("archetype_id", ""))] = Array(policy.get("accepted_category_ids", []))
	var pawn := int(payouts.get("archetype_pawn_row", 0))
	_expect(pawn > 0, "the pawn counter buys nothing")
	for archetype_id: String in payouts:
		if archetype_id == "archetype_pawn_row":
			continue
		_expect(
			pawn > int(payouts[archetype_id]),
			"%s pays as well as the pawn counter, so nobody would make the trip" % archetype_id
		)
	# And it has to take what the hero can actually make.
	for category_id: String in ["crafted"]:
		_expect(
			category_id in Array(accepts.get("archetype_pawn_row", [])),
			"the pawn counter does not take %s, which is everything the hero makes" % category_id
		)


func _value_of(item_id: String, quantity: int) -> int:
	var definition: Variant = ItemCatalog.definition(item_id)
	if definition == null:
		return 0
	return int(definition.call("base_value")) * maxi(quantity, 1)


## The pack model nests the inventory one level down, and containers are keyed
## rather than listed. Reading it the other way found nothing and said so as
## "the radio is not in the pack", which is the least useful true statement.
func _stack_of(adapter: Object, item_id: String) -> String:
	var inventory: Dictionary = Dictionary(adapter.get_inventory_model()).get("inventory", {})
	var containers: Variant = inventory.get("containers", {})
	var groups: Array = []
	if containers is Array:
		groups = containers
	elif containers is Dictionary:
		for key: Variant in Dictionary(containers):
			groups.append(Dictionary(containers)[key])
	for raw_container: Variant in groups:
		if not raw_container is Dictionary:
			continue
		for raw_stack: Variant in Array(Dictionary(raw_container).get("stacks", [])):
			if String(Dictionary(raw_stack).get("item_id", "")) == item_id:
				return String(Dictionary(raw_stack).get("stack_id", ""))
	return ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("M5 CRAFTS TESTS PASSED: 6/6")
		quit(0)
		return
	for failure: String in _failures:
		push_error("M5 CRAFTS: %s" % failure)
	quit(1)
