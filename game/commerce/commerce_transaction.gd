class_name CommerceTransaction
extends RefCounted

## Stable facade. Buy and sell responsibilities live in separate command modules.

const Buy := preload("res://game/commerce/commerce_buy_transaction.gd")
const Sell := preload("res://game/commerce/commerce_sell_transaction.gd")


static func prepare_buy(
	run_state: Variant,
	world_state: Variant,
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	return Buy.prepare(run_state, world_state, store_id, offer_id, quantity, target_container_id, command_id, expected_revision)


static func prepare_buy_snapshot(
	run_state: Variant,
	snapshot: Dictionary,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	return Buy.prepare_snapshot(run_state, snapshot, offer_id, quantity, target_container_id, command_id, expected_revision)


static func prepare_sell(
	run_state: Variant,
	world_state: Variant,
	product_catalog: Dictionary,
	store_catalog: Dictionary,
	store_id: String,
	stack_id: String,
	quantity: int,
	pricing_context: Dictionary,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	return Sell.prepare(run_state, world_state, product_catalog, store_catalog, store_id, stack_id, quantity, pricing_context, command_id, expected_revision)


static func prepare_sell_snapshot(
	run_state: Variant,
	snapshot: Dictionary,
	product_catalog: Dictionary,
	store_catalog: Dictionary,
	store_id: String,
	stack_id: String,
	quantity: int,
	pricing_context: Dictionary,
	command_id: String,
	expected_revision: int
) -> Dictionary:
	return Sell.prepare_snapshot(run_state, snapshot, product_catalog, store_catalog, store_id, stack_id, quantity, pricing_context, command_id, expected_revision)
