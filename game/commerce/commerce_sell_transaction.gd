class_name CommerceSellTransaction
extends RefCounted

const Access := preload("res://game/commerce/commerce_candidate_access.gd")
const Support := preload("res://game/commerce/commerce_transaction_support.gd")
const CatalogValidator := preload("res://game/commerce/commerce_catalog_validator.gd")
const ProductCatalogScript := preload("res://game/commerce/product_catalog.gd")
const StoreCatalogScript := preload("res://game/commerce/store_catalog.gd")
const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")
const InventoryStateScript := preload("res://core/inventory/inventory_state.gd")


static func prepare(
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
	var snapshot := Access.stock_snapshot(world_state, store_id)
	if snapshot.is_empty():
		return Support.failure("missing_stock", "store has no persisted stock snapshot")
	return Support.attach_world_candidate(
		prepare_snapshot(run_state, snapshot, product_catalog, store_catalog, store_id, stack_id, quantity, pricing_context, command_id, expected_revision),
		world_state,
		store_id
	)


static func prepare_snapshot(
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
	var references := CatalogValidator.validate_references(
		product_catalog,
		store_catalog,
		ProductCatalogScript.known_item_ids()
	)
	if not bool(references.get("ok", false)):
		return Support.failure("invalid_catalog", "commerce catalogs are invalid", references)
	var guard := Support.guard_snapshot(snapshot, command_id, expected_revision, store_id)
	if not bool(guard.get("ok", false)):
		return guard
	if bool(guard.get("already_applied", false)):
		return Support.idempotent_candidate(run_state, snapshot)
	if stack_id.is_empty() or quantity <= 0:
		return Support.failure("invalid_sale", "stack and positive quantity are required")
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return Support.failure("unknown_store", "unknown store %s" % store_id)
	var buyback: Dictionary = Dictionary(profile["archetype"]).get("buyback_policy", {})
	if not bool(buyback.get("enabled", false)):
		return Support.failure("buyback_disabled", "this store does not buy items")
	var stack := InventoryStateScript.find_stack(Access.inventory(run_state), stack_id)
	if stack.is_empty() or bool(stack.get("external", false)):
		return Support.failure("missing_stack", "only carried inventory can be sold")
	if quantity > int(stack.get("quantity", 0)):
		return Support.failure("invalid_quantity", "the stack contains fewer units than requested")
	var product := _sale_product(product_catalog, stack, buyback, snapshot, pricing_context)
	if product.is_empty():
		return Support.failure("item_not_accepted", "the store does not accept this item")
	var quality := int(pricing_context.get("quality", stack.get("condition", 100)))
	if quality < 0 or quality > 100:
		return Support.failure("invalid_quality", "sale quality must be from 0 to 100")
	var retail_result := _sale_retail_price(product, profile, stack, quality, pricing_context)
	if not bool(retail_result.get("ok", false)):
		return retail_result
	var payout_result := PriceResolverScript.apply_basis_points(int(retail_result["unit_price"]), buyback["payout_basis_points"])
	if not bool(payout_result.get("ok", false)):
		return payout_result
	var total_result := Support.checked_total(int(payout_result["value"]), quantity)
	if not bool(total_result.get("ok", false)):
		return total_result
	var clone_result := Access.clone_candidate(run_state, "run_state")
	if not bool(clone_result.get("ok", false)):
		return clone_result
	var candidate: Variant = clone_result["candidate"]
	var removal := InventoryStateScript.remove_stack(Access.inventory(candidate), stack_id, quantity)
	if not bool(removal.get("ok", false)):
		return Support.failure(String(removal.get("code", "inventory_conflict")), String(removal.get("error", "inventory rejected the sale")), removal)
	if not Access.set_inventory(candidate, removal["inventory"]):
		return Support.failure("inventory_write_failed", "run candidate does not expose writable inventory")
	if not Access.change_money(candidate, int(total_result["total"])):
		return Support.failure("money_write_failed", "run candidate rejected the payout")
	var offers: Array = Array(snapshot["offers"]).duplicate(true)
	offers.append(_buyback_offer(product, stack, quality, quantity, int(retail_result["unit_price"]), command_id, int(snapshot["revision"])))
	return Support.finish_snapshot_candidate(candidate, snapshot, offers, command_id, {
		"kind": "sell",
		"stack_id": stack_id,
		"quantity": quantity,
		"unit_payout": int(payout_result["value"]),
		"total_payout": int(total_result["total"]),
	})


## Shared by the confirmed sale and by the list that shows what a shop would
## pay, so the row the player reads and the arden he receives are one number.
static func unit_payout(
	product_catalog: Dictionary,
	store_catalog: Dictionary,
	store_id: String,
	stack: Dictionary,
	quality: int,
	pricing_context: Dictionary
) -> Dictionary:
	var profile := StoreCatalogScript.profile_for_store(store_catalog, store_id)
	if profile.is_empty():
		return Support.failure("unknown_store", "unknown store %s" % store_id)
	var buyback: Dictionary = Dictionary(profile["archetype"]).get("buyback_policy", {})
	if not bool(buyback.get("enabled", false)):
		return Support.failure("buyback_disabled", "this store does not buy items")
	var product := _sale_product(product_catalog, stack, buyback, {}, pricing_context)
	if product.is_empty():
		return Support.failure("item_not_accepted", "the store does not accept this item")
	var retail_result := _sale_retail_price(product, profile, stack, quality, pricing_context)
	if not bool(retail_result.get("ok", false)):
		return retail_result
	var payout_result := PriceResolverScript.apply_basis_points(
		int(retail_result["unit_price"]),
		buyback["payout_basis_points"]
	)
	if not bool(payout_result.get("ok", false)):
		return payout_result
	return {
		"ok": true,
		"code": "ok",
		"unit_payout": int(payout_result["value"]),
		"unit_retail": int(retail_result["unit_price"]),
		"product": product.duplicate(true),
	}


static func _sale_product(
	product_catalog: Dictionary,
	stack: Dictionary,
	buyback: Dictionary,
	snapshot: Dictionary,
	context: Dictionary
) -> Dictionary:
	var default_year := int(Dictionary(snapshot.get("generated_at", {})).get("year", 1980))
	var year := int(context.get("year", default_year))
	var accepted: Array = buyback.get("accepted_category_ids", [])
	var matches := ProductCatalogScript.find_by_item(product_catalog, String(stack["item_id"]))
	matches.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["product_id"]) < String(right["product_id"])
	)
	for raw_product: Variant in matches:
		var product: Dictionary = raw_product
		if String(product["category_id"]) not in accepted or year < int(product["available_from"]):
			continue
		if product.has("legacy_until") and year > int(product["legacy_until"]):
			continue
		return product
	return {}


static func _sale_retail_price(
	product: Dictionary,
	profile: Dictionary,
	stack: Dictionary,
	quality: int,
	context: Dictionary
) -> Dictionary:
	var store: Dictionary = profile["store"]
	var band_result := PriceResolverScript.apply_basis_points(int(store["markup_basis_points"]), context.get("price_band_basis_points", 10_000))
	if not bool(band_result.get("ok", false)):
		return band_result
	var supply: Dictionary = context.get("category_supply_basis_points", {})
	return PriceResolverScript.resolve(int(product["base_value_1980"]), PriceResolverScript.neutral_factors({
		"consumer_price_index_basis_points": context.get("consumer_price_index_basis_points", 10_000),
		"category_supply_basis_points": supply.get(String(product["category_id"]), 10_000),
		"district_basis_points": context.get("district_basis_points", 10_000),
		"store_markup_basis_points": int(band_result["value"]),
		"condition_quality_basis_points": 5_000 + int(stack["condition"]) * 25 + quality * 25,
		"relationship_basis_points": context.get("relationship_basis_points", 10_000),
	}))


static func _buyback_offer(
	product: Dictionary,
	stack: Dictionary,
	quality: int,
	quantity: int,
	unit_price: int,
	command_id: String,
	revision: int
) -> Dictionary:
	var token := Support.stable_token(command_id)
	return {
		"offer_id": "offer:buyback:%s:%d" % [token, revision],
		"product_id": String(product["product_id"]),
		"item_id": String(product["item_id"]),
		"category_id": String(product["category_id"]),
		"quantity": quantity,
		"unit_price": unit_price,
		"condition": int(stack["condition"]),
		"quality": quality,
		"expires_at": -1,
		"batch_id": "batch:buyback:%s" % token,
	}
