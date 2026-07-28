class_name CommerceWorldFactors
extends RefCounted

## Turns the objective state of the district into the numbers commerce already
## knows how to consume.
##
## Nothing here is invented for the shop screen: every factor traces back to one
## metric, one process stage or one relationship, and every one of them is
## returned as a named cause so the player can be told why bread costs more this
## week instead of watching a number move for no visible reason.

const WorldProcessProjectionScript := preload("res://game/world/world_process_projection.gd")

const NEUTRAL := 10_000

const SUPPLY_METRIC := "metric_riverside_goods_supply"
const SANITATION_METRIC := "metric_riverside_sanitation"
const PRESSURE_METRIC := "metric_riverside_institution_pressure"

## The value each metric holds in an untouched district. A metric sitting at its
## own default must leave prices exactly neutral, otherwise a brand new run
## would already look like something had happened.
const SUPPLY_BASELINE := 52
const SANITATION_BASELINE := 42
const PRESSURE_BASELINE := 35

const SUPPLY_PRICE_STEP := 40
const CATEGORY_PRICE_STEP := 25
const PRESSURE_PRICE_STEP := 15
const RELATIONSHIP_TRUST_STEP := 30

const MIN_FACTOR := 7_000
const MAX_FACTOR := 13_000

const FOOD_CATEGORIES := ["prepared_food", "preserved_food"]
const MEDICAL_CATEGORIES := ["medicine", "medical_supply"]
const SALVAGE_CATEGORIES := ["component", "electronics"]

## A yard that is being inspected, or has been restricted, stops feeding the
## commission shop with parts, and the shelf shows it before anybody says so.
const SALVAGE_STAGE_FACTORS := {
	"preparation": 10_500,
	"inspection": 11_500,
	"restricted": 12_000,
	"closed_temporarily": 12_500,
}
const SALVAGE_STAGE_OFFER_DELTA := {
	"inspection": -1,
	"restricted": -1,
	"closed_temporarily": -2,
}


static func build(
	world_state: WorldState,
	social_state: SocialState,
	store: Dictionary
) -> Dictionary:
	var causes: Array[Dictionary] = []
	if world_state == null:
		return _neutral()
	var supply := world_state.metric_value(SUPPLY_METRIC, SUPPLY_BASELINE)
	var sanitation := world_state.metric_value(SANITATION_METRIC, SANITATION_BASELINE)
	var pressure := world_state.metric_value(PRESSURE_METRIC, PRESSURE_BASELINE)
	var stage := _recycling_stage(world_state)

	var consumer_price_index := _bounded(
		NEUTRAL + (SUPPLY_BASELINE - supply) * SUPPLY_PRICE_STEP
	)
	_record(
		causes,
		"district_supply",
		"Снабжение района",
		consumer_price_index,
		"Товары приходят реже обычного" if consumer_price_index > NEUTRAL else "Товары приходят чаще обычного"
	)
	var district := _bounded(NEUTRAL + (pressure - PRESSURE_BASELINE) * PRESSURE_PRICE_STEP)
	if district != NEUTRAL:
		_record(
			causes,
			"institution_pressure",
			"Внимание учреждений",
			district,
			"Проверки делают торговлю осторожнее" if district > NEUTRAL else "Учреждения смотрят в другую сторону"
		)

	var category_supply: Dictionary = {}
	var food_factor := _bounded(NEUTRAL + (SUPPLY_BASELINE - supply) * CATEGORY_PRICE_STEP)
	for category_id: String in FOOD_CATEGORIES:
		category_supply[category_id] = food_factor
	var medical_factor := _bounded(
		NEUTRAL + (SANITATION_BASELINE - sanitation) * CATEGORY_PRICE_STEP
	)
	for category_id: String in MEDICAL_CATEGORIES:
		category_supply[category_id] = medical_factor
	if medical_factor != NEUTRAL:
		_record(
			causes,
			"sanitation",
			"Санитарное состояние",
			medical_factor,
			"Медикаменты расходятся быстрее" if medical_factor > NEUTRAL else "Медикаментов хватает"
		)
	var salvage_factor := int(SALVAGE_STAGE_FACTORS.get(stage, NEUTRAL))
	for category_id: String in SALVAGE_CATEGORIES:
		category_supply[category_id] = salvage_factor
	if salvage_factor != NEUTRAL:
		_record(
			causes,
			"recycling_inspection",
			"Проверка пункта вторсырья",
			salvage_factor,
			"Разбор техники и деталей стал реже"
		)

	var relationship := _relationship_factor(social_state, store, causes)
	return {
		"consumer_price_index_basis_points": consumer_price_index,
		"district_basis_points": district,
		"category_supply_basis_points": category_supply,
		"relationship_basis_points": relationship,
		"supply_offer_delta": _offer_delta(supply, stage),
		"causes": causes,
	}


## Fewer things on the shelf, not merely dearer ones. A shortage the player can
## only read as a price is a shortage he can ignore.
static func _offer_delta(supply: int, stage: String) -> int:
	var delta := 0
	if supply <= 25:
		delta -= 1
	elif supply >= 80:
		delta += 1
	delta += int(SALVAGE_STAGE_OFFER_DELTA.get(stage, 0))
	return clampi(delta, -2, 1)


static func _relationship_factor(
	social_state: SocialState,
	store: Dictionary,
	causes: Array[Dictionary]
) -> int:
	var owner_id := String(store.get("owner_npc_id", ""))
	if social_state == null or owner_id.is_empty():
		return NEUTRAL
	var relationship := social_state.relationship(owner_id)
	var trust := int(relationship.get("trust", 0))
	if trust == 0:
		return NEUTRAL
	# Being trusted is a discount, being distrusted is a surcharge; the shop
	# owner is a person with an opinion, not a price list.
	var factor := _bounded(NEUTRAL - trust * RELATIONSHIP_TRUST_STEP)
	_record(
		causes,
		"owner_relationship",
		"Отношение продавца",
		factor,
		"Здесь вам не доверяют" if factor > NEUTRAL else "Здесь вас узнают"
	)
	return factor


static func _recycling_stage(world_state: WorldState) -> String:
	var projection := WorldProcessProjectionScript.recycling_inspection(world_state)
	return String(projection.get("stage_id", "")) if bool(projection.get("ok", false)) else ""


static func _record(
	causes: Array[Dictionary],
	cause_id: String,
	title: String,
	factor: int,
	detail: String
) -> void:
	if factor == NEUTRAL:
		return
	causes.append({
		"id": cause_id,
		"title": title,
		"detail": detail,
		"factor_basis_points": factor,
		"direction": "up" if factor > NEUTRAL else "down",
	})


static func _bounded(value: int) -> int:
	return clampi(value, MIN_FACTOR, MAX_FACTOR)


static func _neutral() -> Dictionary:
	return {
		"consumer_price_index_basis_points": NEUTRAL,
		"district_basis_points": NEUTRAL,
		"category_supply_basis_points": {},
		"relationship_basis_points": NEUTRAL,
		"supply_offer_delta": 0,
		"causes": [],
	}
