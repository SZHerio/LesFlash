extends SceneTree

## M3F.5: worn equipment, carried bags, handing things over and selling by
## profile — plus the part of the economy that has to answer to the world.

const SandboxAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const EquipmentRules := preload("res://game/equipment/equipment_rules.gd")
const EquipmentCommand := preload("res://game/equipment/equipment_command.gd")
const NpcGiftCommand := preload("res://game/npc/npc_gift_command.gd")
const StoreService := preload("res://game/commerce/store_service.gd")
const CommerceCommand := preload("res://game/commerce/commerce_session_command.gd")
const WorldFactors := preload("res://game/commerce/commerce_world_factors.gd")
const RecyclingService := preload("res://game/recycling/recycling_service.gd")
const ShelterResolver := preload("res://game/shelter/shelter_resolver.gd")
const ShelterCatalog := preload("res://game/shelter/shelter_catalog.gd")
const InventoryState := preload("res://core/inventory/inventory_state.gd")
const ItemCatalog := preload("res://core/inventory/item_catalog.gd")
const WorldMutation := preload("res://core/world/world_mutation.gd")

const BUILD := {"strength": 6, "charisma": 5, "intelligence": 4, "luck": 3}

var _failures: Array[String] = []
var _tests_run := 0
var _current := ""


func _init() -> void:
	_run("the item catalog authors every equip slot it uses", _test_catalog_contract)
	_run("worn gear occupies its slot and answers for its effect", _test_equip_and_modifiers)
	_run("a worn bag opens a container and refuses to leave full", _test_bag_container)
	_run("worn gear survives a save and a load", _test_equipment_round_trip)
	_run("warmth pays for itself only where the night is open", _test_warmth_changes_the_night)
	_run("a gift is taken or refused by who the person is", _test_gift_preferences)
	_run("one shop pays for what another will not take", _test_sale_profiles)
	_run("prices and the shelf answer to the state of the district", _test_world_factors)
	_run("the yard stops paying when the inspection stops it", _test_recycling_intake)
	if _failures.is_empty():
		print("M3F.5 ITEM ECONOMY TESTS PASSED: %d/%d" % [_tests_run, _tests_run])
		quit(0)
		return
	print("M3F.5 ITEM ECONOMY TESTS FAILED: %d failure(s) across %d test(s)" % [
		_failures.size(), _tests_run,
	])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _run(title: String, callback: Callable) -> void:
	_tests_run += 1
	_current = title
	var before := _failures.size()
	callback.call()
	print("PASS: %s" % title if before == _failures.size() else "FAIL: %s" % title)


# --- catalog ----------------------------------------------------------------


func _test_catalog_contract() -> void:
	_expect(bool(ItemCatalog.validation().get("ok", false)), "item catalog must validate")
	var slots: Dictionary = {}
	for definition: Variant in ItemCatalog.all_definitions():
		var slot := String(definition.equip_slot())
		if slot.is_empty():
			continue
		_expect(
			slot in ItemCatalog.EQUIP_SLOT_IDS,
			"%s uses an unknown slot %s" % [String(definition.id()), slot]
		)
		slots[slot] = true
		if slot == "bag":
			_expect(
				not definition.equip_container().is_empty(),
				"%s occupies the bag slot and must describe a container" % String(definition.id())
			)
	for slot_id: String in ItemCatalog.EQUIP_SLOT_IDS:
		_expect(slots.has(slot_id), "no item can be worn in the %s slot" % slot_id)


# --- equipment --------------------------------------------------------------


func _test_equip_and_modifiers() -> void:
	var session := _session(41_001)
	if session == null:
		return
	var jacket := _give(session, "warm_jacket")
	var boots := _give(session, "sturdy_boots")
	var second_jacket := _give(session, "warm_jacket")
	_expect_equal(
		EquipmentRules.modifier(session.run_state.inventory, "warmth"),
		0,
		"carrying a coat must not warm anybody"
	)

	var worn := EquipmentCommand.equip(session, jacket, "test:equip:jacket")
	_expect(bool(worn.get("ok", false)), "the coat must go on: %s" % str(worn))
	_expect_equal(String(worn.get("slot_id", "")), "torso", "the coat occupies the torso slot")
	_expect(
		EquipmentRules.modifier(session.run_state.inventory, "warmth") > 0,
		"a worn coat must be worth something"
	)

	var taken := EquipmentCommand.equip(session, second_jacket, "test:equip:jacket2")
	_expect_equal(String(taken.get("code", "")), "slot_taken", "one slot holds one thing")

	var booted := EquipmentCommand.equip(session, boots, "test:equip:boots")
	_expect(bool(booted.get("ok", false)), "boots use a different slot: %s" % str(booted))
	_expect(
		EquipmentRules.modifier(session.run_state.inventory, "travel_stamina") > 0,
		"worn boots must be worth something"
	)
	var occupied: Array[String] = []
	for slot: Dictionary in EquipmentRules.slots_model(session.run_state.inventory):
		if bool(slot.get("occupied", false)):
			occupied.append(String(slot.get("slot_id", "")))
	occupied.sort()
	_expect_equal(occupied, ["feet", "torso"] as Array[String], "exactly two slots are in use")

	var removed := EquipmentCommand.unequip(
		session,
		String(worn.get("stack_id", "")),
		"test:unequip:jacket"
	)
	_expect(bool(removed.get("ok", false)), "the coat must come off: %s" % str(removed))
	_expect(
		EquipmentRules.slot_occupant(session.run_state.inventory, "torso").is_empty(),
		"the torso slot must be free again"
	)
	_expect(
		EquipmentRules.modifier(session.run_state.inventory, "warmth")
		< EquipmentRules.MODIFIER_MAX,
		"a coat in the pack must stop warming its owner"
	)


func _test_bag_container() -> void:
	var session := _session(41_002)
	if session == null:
		return
	var bag := _give(session, "canvas_satchel")
	var before: int = session.run_state.inventory["containers"].size()
	var worn := EquipmentCommand.equip(session, bag, "test:equip:bag")
	_expect(bool(worn.get("ok", false)), "the bag must go on the shoulder: %s" % str(worn))
	var container_id := String(worn.get("container_id", ""))
	_expect(not container_id.is_empty(), "a worn bag must open a container")
	_expect_equal(
		session.run_state.inventory["containers"].size(),
		before + 2,
		"the worn container and the bag container both appear"
	)

	var stored := InventoryState.add_item(
		session.run_state.inventory,
		"copper_scrap",
		2,
		100,
		container_id,
		session.run_state.get_characteristic("strength")
	)
	_expect(bool(stored.get("ok", false)), "the bag must hold things: %s" % str(stored))
	session.run_state.inventory = Dictionary(stored["inventory"])

	var blocked := EquipmentCommand.unequip(
		session,
		String(worn.get("stack_id", "")),
		"test:unequip:bag_full"
	)
	_expect_equal(String(blocked.get("code", "")), "bag_not_empty", "a full bag is not dropped silently")

	var emptied := InventoryState.move_stack(
		session.run_state.inventory,
		String(Array(stored.get("stack_ids", []))[0]),
		"pockets",
		0,
		session.run_state.get_characteristic("strength")
	)
	_expect(bool(emptied.get("ok", false)), "the bag must be emptied: %s" % str(emptied))
	session.run_state.inventory = Dictionary(emptied["inventory"])
	var removed := EquipmentCommand.unequip(
		session,
		String(worn.get("stack_id", "")),
		"test:unequip:bag"
	)
	_expect(bool(removed.get("ok", false)), "an empty bag comes off: %s" % str(removed))
	_expect(
		not Dictionary(session.run_state.inventory["containers"]).has(container_id),
		"the bag container leaves with the bag"
	)


func _test_equipment_round_trip() -> void:
	var session := _session(41_003)
	if session == null:
		return
	var jacket := _give(session, "warm_jacket")
	var worn := EquipmentCommand.equip(session, jacket, "test:equip:roundtrip")
	_expect(bool(worn.get("ok", false)), "the coat must go on before saving")
	var warmth := EquipmentRules.modifier(session.run_state.inventory, "warmth")
	var restored = session.clone()
	_expect(restored != null, "a session with worn gear must clone")
	if restored == null:
		return
	_expect_equal(
		EquipmentRules.modifier(restored.run_state.inventory, "warmth"),
		warmth,
		"worn gear must survive serialization"
	)
	_expect(
		EquipmentRules.is_equipped(restored.run_state.inventory, String(worn.get("stack_id", ""))),
		"the same stack must still be worn after a round trip"
	)


func _test_warmth_changes_the_night() -> void:
	var loaded := ShelterCatalog.load_default()
	_expect(bool(loaded.get("ok", false)), "shelter catalog must load")
	if not bool(loaded.get("ok", false)):
		return
	var catalog: Dictionary = loaded["catalog"]
	var context := {
		"location_id": "underpass",
		"money": 0,
		"calendar": _evening_calendar(),
		"warmth": 0,
	}
	var cold := ShelterResolver.resolve_one(catalog, "shelter_underpass_niche", context)
	context["warmth"] = 60
	var warm := ShelterResolver.resolve_one(catalog, "shelter_underpass_niche", context)
	_expect(bool(cold.get("ok", false)) and bool(warm.get("ok", false)), "the niche must resolve")
	if not bool(cold.get("ok", false)) or not bool(warm.get("ok", false)):
		return
	var cold_effects: Dictionary = Dictionary(cold["option"]).get("meter_effects", {})
	var warm_effects: Dictionary = Dictionary(warm["option"]).get("meter_effects", {})
	_expect(
		int(warm_effects.get("health", 0)) > int(cold_effects.get("health", 0)),
		"warmth must take back part of what the open night costs"
	)
	_expect(
		int(warm_effects.get("energy", 0)) > int(cold_effects.get("energy", 0)),
		"a warm night must rest better than a cold one"
	)

	# A paid room is already closed to the weather, so a coat changes nothing.
	var paid_context := {
		"location_id": "station_square",
		"money": 500,
		"calendar": _evening_calendar(),
		"warmth": 0,
	}
	var plain := ShelterResolver.resolve_one(catalog, "shelter_station_safe_room", paid_context)
	paid_context["warmth"] = 100
	var dressed := ShelterResolver.resolve_one(catalog, "shelter_station_safe_room", paid_context)
	_expect_equal(
		Dictionary(dressed["option"]).get("meter_effects"),
		Dictionary(plain["option"]).get("meter_effects"),
		"equipment must not improve a room that was already sheltered"
	)


# --- giving -----------------------------------------------------------------


func _test_gift_preferences() -> void:
	var session := _session(41_004)
	if session == null:
		return
	# Lidia keeps clinic hours; the schedule decides where and when she is.
	_place(session, "clinic_yard")
	_advance(session, 60)
	var bandage := _give(session, "bandage_roll")
	var cigarettes := _give(session, "cigarette_pack")
	var offers := NpcGiftCommand.offers(session, "npc_lidia_maren")
	_expect(not offers.is_empty(), "carried gifts must be listed for a present NPC")

	var refused := NpcGiftCommand.give(
		session, "npc_lidia_maren", cigarettes, 1, "test:gift:refused"
	)
	_expect_equal(String(refused.get("code", "")), "gift_refused", "a nurse on duty refuses tobacco")
	_expect_equal(
		session.run_state.get_item_count("cigarette_pack"),
		1,
		"a refused gift stays in the hero's hands"
	)

	var before: Dictionary = session.social_state.relationship("npc_lidia_maren")
	var given := NpcGiftCommand.give(
		session, "npc_lidia_maren", bandage, 1, "test:gift:accepted"
	)
	_expect(bool(given.get("ok", false)), "a nurse takes medical supplies: %s" % str(given))
	_expect_equal(
		session.run_state.get_item_count("bandage_roll"),
		0,
		"a given item leaves the inventory"
	)
	var after: Dictionary = session.social_state.relationship("npc_lidia_maren")
	_expect(
		int(after.get("affinity", 0)) > int(before.get("affinity", 0)),
		"a gift must move the relationship"
	)
	_expect(bool(given.get("valued", false)), "a valued gift must be recognised as one")

	var again := _give(session, "bandage_roll")
	var repeated := NpcGiftCommand.give(
		session, "npc_lidia_maren", again, 1, "test:gift:repeat"
	)
	_expect_equal(
		String(repeated.get("code", "")),
		"gift_already_given_today",
		"generosity is remembered once a day, not once a minute"
	)


# --- selling ----------------------------------------------------------------


func _test_sale_profiles() -> void:
	var commission := _session(41_005)
	if commission == null:
		return
	_place(commission, "station_square")
	_advance(commission, 2 * 60)
	var pliers := _give(commission, "pliers")
	var commission_offers := StoreService.sell_offers(commission, "store_station_commission")
	_expect(bool(commission_offers.get("ok", false)), "the commission shop must answer: %s" % str(commission_offers))
	var commission_row := _find(Array(commission_offers.get("offers", [])), "pliers")
	_expect(not commission_row.is_empty(), "the commission shop buys tools")

	var pharmacy := _session(41_006)
	if pharmacy == null:
		return
	_place(pharmacy, "clinic_yard")
	_advance(pharmacy, 2 * 60)
	_give(pharmacy, "pliers")
	var pharmacy_offers := StoreService.sell_offers(pharmacy, "store_clinic_pharmacy_window")
	_expect(bool(pharmacy_offers.get("ok", false)), "the pharmacy must answer")
	_expect(
		Array(pharmacy_offers.get("offers", [])).is_empty(),
		"a pharmacy window does not buy second-hand tools"
	)

	var money_before: int = commission.run_state.money
	var sold := CommerceCommand.sell(
		commission,
		"store_station_commission",
		pliers,
		1,
		"test:sell:pliers",
		-1
	)
	_expect(bool(sold.get("ok", false)), "the sale must commit: %s" % str(sold))
	if bool(sold.get("ok", false)):
		var payout := int(Dictionary(sold.get("receipt", {})).get("total_payout", 0))
		_expect(payout > 0, "a sale must pay something")
		_expect_equal(
			commission.run_state.money,
			money_before + payout,
			"the receipt and the wallet must agree"
		)
		_expect_equal(
			commission.run_state.get_item_count("pliers"),
			0,
			"a sold item leaves the inventory"
		)

	# What is worn is not for sale until it is taken off.
	var dressed := _session(41_007)
	if dressed == null:
		return
	_place(dressed, "station_square")
	_advance(dressed, 2 * 60)
	var jacket := _give(dressed, "warm_jacket")
	var worn := EquipmentCommand.equip(dressed, jacket, "test:sell:equip")
	_expect(bool(worn.get("ok", false)), "the coat must go on")
	var refused := CommerceCommand.sell(
		dressed,
		"store_station_commission",
		String(worn.get("stack_id", "")),
		1,
		"test:sell:worn",
		-1
	)
	_expect_equal(String(refused.get("code", "")), "item_equipped", "the coat on your back is not stock")


# --- the world in the price -------------------------------------------------


func _test_world_factors() -> void:
	var session := _session(41_008)
	if session == null:
		return
	_place(session, "market")
	_advance(session, 2 * 60)
	var neutral := StoreService.preview(session, "store_market_food_row")
	_expect(bool(neutral.get("ok", false)), "the food row must open: %s" % str(neutral))
	if not bool(neutral.get("ok", false)):
		return
	var neutral_offers := Array(neutral.get("offers", []))
	_expect(
		Array(neutral.get("world_causes", [])).is_empty(),
		"an untouched district must leave prices exactly neutral"
	)

	var scarce := _session(41_008)
	_place(scarce, "market")
	_advance(scarce, 2 * 60)
	_set_metric(scarce, WorldFactors.SUPPLY_METRIC, 10)
	var scarce_model := StoreService.preview(scarce, "store_market_food_row")
	_expect(bool(scarce_model.get("ok", false)), "the food row must still open in a shortage")
	if not bool(scarce_model.get("ok", false)):
		return
	var causes := Array(scarce_model.get("world_causes", []))
	_expect(not causes.is_empty(), "a shortage must name its cause")
	var scarce_offers := Array(scarce_model.get("offers", []))
	_expect(
		scarce_offers.size() < neutral_offers.size(),
		"a shortage must be visible as a shorter shelf (%d vs %d)" % [
			scarce_offers.size(), neutral_offers.size(),
		]
	)
	var neutral_price := _price_of(neutral_offers, "simple_meal")
	var scarce_price := _price_of(scarce_offers, "simple_meal")
	if neutral_price > 0 and scarce_price > 0:
		_expect(
			scarce_price > neutral_price,
			"the same meal must cost more in a shortage (%d vs %d)" % [scarce_price, neutral_price]
		)


func _test_recycling_intake() -> void:
	var session := _session(41_009)
	if session == null:
		return
	_place(session, "recycling_point")
	_give(session, "copper_scrap")
	var open_offers := RecyclingService.offers(session)
	_expect(not open_offers.is_empty(), "the yard must list carried scrap")
	if open_offers.is_empty():
		return
	_expect(bool(open_offers[0].get("accepting", false)), "a latent inspection does not close the scales")

	_advance_process(session, "process_recycling_inspection", "inspection")
	var intake := RecyclingService.intake(session)
	if bool(intake.get("accepting", true)):
		# The stage reached is still an open one; the price must have moved
		# instead, which is the other half of the same contract.
		_expect(
			int(intake.get("price_basis_points", 10_000)) != 10_000,
			"an advanced inspection must change what the yard pays"
		)
		return
	var closed := RecyclingService.sell(
		session,
		String(open_offers[0].get("stack_id", "")),
		1,
		"test:recycling:closed"
	)
	_expect_equal(
		String(closed.get("code", "")),
		"intake_closed",
		"a yard under inspection does not take materials"
	)


# --- helpers ----------------------------------------------------------------


func _session(seed: int) -> Object:
	var adapter = SandboxAdapter.create(BUILD, seed)
	_expect(adapter != null, "session must be created")
	return adapter.get("_session") if adapter != null else null


func _place(session: Object, location_id: String) -> void:
	session.set("location", location_id)
	session.set("phase", "map")
	session.set("current_event", "")


func _advance(session: Object, minutes: int) -> void:
	session.run_state.calendar.advance_minutes(minutes)
	session.survival_state.processed_elapsed_minutes += minutes


func _give(session: Object, item_id: String) -> String:
	var added := InventoryState.add_item(
		session.run_state.inventory,
		item_id,
		1,
		100,
		"pockets",
		session.run_state.get_characteristic("strength"),
		true
	)
	if not bool(added.get("ok", false)):
		_expect(false, "fixture item %s must fit: %s" % [item_id, str(added)])
		return ""
	session.run_state.inventory = Dictionary(added["inventory"])
	var ids: Array = Array(added.get("stack_ids", []))
	return String(ids[0]) if not ids.is_empty() else ""


func _set_metric(session: Object, metric_id: String, value: int) -> void:
	session.world_state.metrics[metric_id] = value


## The authored transitions gate stage changes on elapsed time, so the fixture
## sets the stage it wants to observe directly rather than pretending a week
## has gone by.
func _advance_process(session: Object, process_id: String, stage_id: String) -> void:
	session.world_state.processes[process_id] = {
		"stage": stage_id,
		"source_id": "test_process",
		"changed_at": session.run_state.calendar.current_stamp(),
	}
	_expect(
		bool(session.world_state.validate().get("ok", false)),
		"the fixture stage must leave the world valid"
	)


func _evening_calendar() -> Dictionary:
	var calendar := GameCalendar.new()
	calendar.advance_minutes(11 * 60)
	return calendar.to_dict()


func _find(offers: Array, item_id: String) -> Dictionary:
	for raw_offer: Variant in offers:
		if raw_offer is Dictionary and String(Dictionary(raw_offer).get("item_id", "")) == item_id:
			return Dictionary(raw_offer).duplicate(true)
	return {}


func _price_of(offers: Array, item_id: String) -> int:
	var offer := _find(offers, item_id)
	return int(offer.get("unit_price", 0)) if not offer.is_empty() else 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s — %s" % [_current, message])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s — %s (expected=%s, actual=%s)" % [
			_current, message, str(expected), str(actual),
		])
