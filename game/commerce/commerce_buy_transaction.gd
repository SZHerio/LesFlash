class_name CommerceBuyTransaction
extends RefCounted

const Access := preload("res://game/commerce/commerce_candidate_access.gd")
const Support := preload("res://game/commerce/commerce_transaction_support.gd")
const StockSnapshotScript := preload("res://game/commerce/stock_snapshot.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")


static func prepare(
	run_state: Variant,
	world_state: Variant,
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	var snapshot := Access.stock_snapshot(world_state, store_id)
	if snapshot.is_empty():
		return Support.failure("missing_stock", "store has no persisted stock snapshot")
	return Support.attach_world_candidate(
		prepare_snapshot(run_state, snapshot, offer_id, quantity, target_container_id, command_id, expected_revision),
		world_state,
		store_id
	)


static func prepare_snapshot(
	run_state: Variant,
	snapshot: Dictionary,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	var guard := Support.guard_snapshot(snapshot, command_id, expected_revision)
	if not bool(guard.get("ok", false)):
		return guard
	if bool(guard.get("already_applied", false)):
		return Support.idempotent_candidate(run_state, snapshot)
	if offer_id.is_empty() or quantity <= 0:
		return Support.failure("invalid_purchase", "offer and positive quantity are required")
	var offer_index := StockSnapshotScript.find_offer_index(snapshot, offer_id)
	if offer_index < 0:
		return Support.failure("missing_offer", "the selected offer no longer exists")
	var offers: Array = Array(snapshot["offers"]).duplicate(true)
	var offer: Dictionary = offers[offer_index]
	if quantity > int(offer["quantity"]):
		return Support.failure("insufficient_stock", "the store has fewer units than requested")
	var total_result := Support.checked_total(int(offer["unit_price"]), quantity)
	if not bool(total_result.get("ok", false)):
		return total_result
	var total_price := int(total_result["total"])
	var clone_result := Access.clone_candidate(run_state, "run_state")
	if not bool(clone_result.get("ok", false)):
		return clone_result
	var candidate: Variant = clone_result["candidate"]
	var current_money: Variant = Access.money(candidate)
	if current_money == null or int(current_money) < total_price:
		return Support.failure("insufficient_funds", "not enough ardens for this purchase")
	var inventory := Access.inventory(candidate)
	if inventory.is_empty():
		return Support.failure("missing_inventory", "run state has no valid inventory")
	var addition := InventoryStateScript.add_item(
		inventory,
		String(offer["item_id"]),
		quantity,
		int(offer["condition"]),
		target_container_id,
		Access.strength(candidate),
		false,
		{"commerce": {
			"store_id": String(snapshot["store_id"]),
			"offer_id": offer_id,
			"batch_id": String(offer["batch_id"]),
			"quality": int(offer["quality"]),
		}}
	)
	if not bool(addition.get("ok", false)):
		return Support.failure(String(addition.get("code", "inventory_conflict")), String(addition.get("error", "inventory rejected the purchase")), addition)
	if not Access.set_inventory(candidate, addition["inventory"]):
		return Support.failure("inventory_write_failed", "run candidate does not expose writable inventory")
	if not Access.change_money(candidate, -total_price):
		return Support.failure("money_write_failed", "run candidate rejected the payment")
	var remaining := int(offer["quantity"]) - quantity
	if remaining == 0:
		offers.remove_at(offer_index)
	else:
		offer["quantity"] = remaining
		offers[offer_index] = offer
	return Support.finish_snapshot_candidate(candidate, snapshot, offers, command_id, {
		"kind": "buy",
		"offer_id": offer_id,
		"quantity": quantity,
		"total_price": total_price,
	})
