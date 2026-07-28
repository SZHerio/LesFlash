class_name StockOfferGenerator
extends RefCounted

## Deterministically selects eligible products and resolves persisted offers.

const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")


static func build(
	eligible_products: Array,
	store: Dictionary,
	archetype: Dictionary,
	request: Dictionary,
	rng: Variant
) -> Dictionary:
	var eligible := eligible_products.duplicate()
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["product_id"]) < String(right["product_id"])
	)
	var count_range: Array = archetype["offer_count_range"]
	# The draw stays on the seed; the district only shifts the result, so a
	# shortage is reproducible and never turns the shelf into a lottery.
	var drawn: int = rng.next_int(int(count_range[0]), int(count_range[1]))
	var shifted := maxi(drawn + int(request.get("supply_offer_delta", 0)), 1)
	var target_count := mini(shifted, eligible.size())
	var selected := _select_products(eligible, archetype, target_count, int(request.get("luck", 5)), rng)
	return _build_offers(selected, store, archetype, request, rng)


static func _select_products(
	eligible: Array,
	archetype: Dictionary,
	target_count: int,
	luck: int,
	rng: Variant
) -> Array:
	var selected: Array = []
	var remaining := eligible.duplicate()
	for raw_id: Variant in Array(archetype["guaranteed_product_ids"]):
		if selected.size() >= target_count:
			break
		var product_id := String(raw_id)
		for index in range(remaining.size()):
			if String(Dictionary(remaining[index])["product_id"]) == product_id:
				selected.append(remaining[index])
				remaining.remove_at(index)
				break
	while selected.size() < target_count and not remaining.is_empty():
		var weights: Array[int] = []
		for raw_product: Variant in remaining:
			weights.append(_selection_weight(raw_product, archetype, luck))
		var selected_index := _weighted_index(weights, rng)
		if selected_index < 0:
			break
		selected.append(remaining[selected_index])
		remaining.remove_at(selected_index)
	return selected


static func _selection_weight(product: Dictionary, archetype: Dictionary, luck: int) -> int:
	var category_weight := int(Dictionary(archetype["category_weights"])[String(product["category_id"])])
	var rarity_factor := 10_000
	match String(product["rarity"]):
		"uncommon":
			rarity_factor = 8_500 + luck * 300
		"rare":
			rarity_factor = 7_000 + luck * 600
	@warning_ignore("integer_division")
	return maxi(1, category_weight * int(product["selection_weight"]) * rarity_factor / 10_000)


static func _weighted_index(weights: Array[int], rng: Variant) -> int:
	var total := 0
	for weight: int in weights:
		total += maxi(weight, 0)
	if total <= 0:
		return -1
	var cursor: int = rng.next_int(1, total)
	for index in range(weights.size()):
		cursor -= weights[index]
		if cursor <= 0:
			return index
	return weights.size() - 1


static func _build_offers(
	products: Array,
	store: Dictionary,
	archetype: Dictionary,
	request: Dictionary,
	rng: Variant
) -> Dictionary:
	var offers: Array = []
	var elapsed := int(Dictionary(request["generated_at"])["elapsed_minutes"])
	var sequence := int(request["restock_sequence"])
	for index in range(products.size()):
		var product: Dictionary = products[index]
		var condition_range := _intersect_ranges(product["condition_range"], archetype["condition_range"])
		var quality_range := _intersect_ranges(product["quality_range"], archetype["quality_band"])
		var quantity_range := _intersect_ranges(product["stock_quantity_range"], archetype["quantity_range"])
		if condition_range.is_empty() or quality_range.is_empty() or quantity_range.is_empty():
			return _failure("incompatible_profile", "store ranges cannot represent %s" % product["product_id"])
		var condition: int = rng.next_int(int(condition_range[0]), int(condition_range[1]))
		var quality: int = rng.next_int(int(quality_range[0]), int(quality_range[1]))
		var quantity: int = rng.next_int(int(quantity_range[0]), int(quantity_range[1]))
		var price_result := _resolve_price(product, store, archetype, request, condition, quality, rng)
		if not bool(price_result.get("ok", false)):
			return _failure("price_resolution_failed", str(price_result.get("error", "price resolution failed")))
		var expires_at := -1
		if product.has("perishable_days"):
			expires_at = elapsed + int(product["perishable_days"]) * 1440
		var product_id := String(product["product_id"])
		offers.append({
			"offer_id": "offer:%s:%d:%s" % [store["store_id"], sequence, product_id],
			"product_id": product_id,
			"item_id": String(product["item_id"]),
			"category_id": String(product["category_id"]),
			"quantity": quantity,
			"unit_price": int(price_result["unit_price"]),
			"condition": condition,
			"quality": quality,
			"expires_at": expires_at,
			"batch_id": "batch:%s:%d:%d" % [store["store_id"], sequence, index],
		})
	return {"ok": true, "offers": offers}


static func _resolve_price(
	product: Dictionary,
	store: Dictionary,
	archetype: Dictionary,
	request: Dictionary,
	condition: int,
	quality: int,
	rng: Variant
) -> Dictionary:
	var price_band: Array = archetype["price_band"]
	var band_factor: int = rng.next_int(int(price_band[0]), int(price_band[1]))
	var markup_result := PriceResolverScript.apply_basis_points(int(store["markup_basis_points"]), band_factor)
	if not bool(markup_result.get("ok", false)):
		return markup_result
	var supply_factors: Dictionary = request.get("category_supply_basis_points", {})
	var category_id := String(product["category_id"])
	return PriceResolverScript.resolve(int(product["base_value_1980"]), PriceResolverScript.neutral_factors({
		"consumer_price_index_basis_points": request.get("consumer_price_index_basis_points", 10_000),
		"category_supply_basis_points": supply_factors.get(category_id, 10_000),
		"district_basis_points": request.get("district_basis_points", 10_000),
		"store_markup_basis_points": int(markup_result["value"]),
		"condition_quality_basis_points": 5_000 + condition * 25 + quality * 25,
		"relationship_basis_points": request.get("relationship_basis_points", 10_000),
	}))


static func _intersect_ranges(left: Array, right: Array) -> Array:
	var minimum := maxi(int(left[0]), int(right[0]))
	var maximum := mini(int(left[1]), int(right[1]))
	return [minimum, maximum] if minimum <= maximum else []


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "errors": [message], "trace": []}
