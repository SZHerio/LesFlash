class_name StoreViewModel
extends RefCounted

## Enriches the pure stock snapshot with Russian display text and stable icons.

const ProductCatalogScript := preload("res://game/commerce/product_catalog.gd")

const CATEGORY_ICONS := {
	"prepared_food": &"action_food",
	"preserved_food": &"action_food",
	"medicine": &"place_clinic",
	"medical_supply": &"place_clinic",
	"tool": &"action_work",
	"equipment": &"nav_items",
	"outerwear": &"nav_items",
	"print": &"action_study",
}


static func build(raw_model: Dictionary, reduced_motion: bool = false) -> Dictionary:
	var result := raw_model.duplicate(true)
	result["reduced_motion"] = reduced_motion
	result["target_container_id"] = "pockets"
	var loaded := ProductCatalogScript.load_default()
	if not bool(loaded.get("ok", false)):
		return result
	var catalog: Dictionary = loaded["catalog"]
	var offers: Array = []
	for raw_offer: Variant in Array(raw_model.get("offers", [])):
		if not raw_offer is Dictionary:
			continue
		var offer: Dictionary = Dictionary(raw_offer).duplicate(true)
		var product := ProductCatalogScript.find(
			catalog,
			String(offer.get("product_id", ""))
		)
		offer["title"] = String(product.get("title", offer.get("item_id", "Товар")))
		offer["icon_id"] = CATEGORY_ICONS.get(
			String(offer.get("category_id", "")),
			&"meta_item"
		)
		offers.append(offer)
	result["offers"] = offers
	var sell_offers: Array = []
	for raw_sale: Variant in Array(raw_model.get("sell_offers", [])):
		if not raw_sale is Dictionary:
			continue
		var sale: Dictionary = Dictionary(raw_sale).duplicate(true)
		sale["mode"] = "sell"
		sale["unit_price"] = int(sale.get("unit_payout", 0))
		sale["quality"] = int(sale.get("condition", 0))
		sale["icon_id"] = CATEGORY_ICONS.get(
			String(sale.get("category_id", "")),
			&"meta_item"
		)
		sell_offers.append(sale)
	result["sell_offers"] = sell_offers
	return result
