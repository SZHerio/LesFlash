class_name IconRegistry
extends RefCounted

## Stable IDs for the first authored icon package. Screens store IDs and never
## depend on asset paths directly.

const ICON_PATHS := {
	&"nav_place": "res://assets/icons/nav_place.svg",
	&"nav_map": "res://assets/icons/nav_map.svg",
	&"nav_hero": "res://assets/icons/nav_hero.svg",
	&"nav_items": "res://assets/icons/nav_items.svg",
	&"nav_tasks": "res://assets/icons/nav_tasks.svg",
	&"action_observe": "res://assets/icons/action_observe.svg",
	&"action_search": "res://assets/icons/action_search.svg",
	&"action_talk": "res://assets/icons/action_talk.svg",
	&"action_work": "res://assets/icons/action_work.svg",
	&"action_trade": "res://assets/icons/action_trade.svg",
	&"action_food": "res://assets/icons/action_food.svg",
	&"action_rest": "res://assets/icons/action_rest.svg",
	&"action_study": "res://assets/icons/action_study.svg",
	&"action_shelter": "res://assets/icons/action_shelter.svg",
	&"meta_time": "res://assets/icons/meta_time.svg",
	&"currency_arden_compact": "res://assets/icons/currency_arden_compact.svg",
	&"currency_arden_full": "res://assets/icons/currency_arden_full.svg",
	&"meta_energy": "res://assets/icons/meta_energy.svg",
	&"meta_risk": "res://assets/icons/meta_risk.svg",
	&"meta_item": "res://assets/icons/meta_item.svg",
	&"meta_knowledge": "res://assets/icons/meta_knowledge.svg",
	&"meta_relationship": "res://assets/icons/meta_relationship.svg",
	&"place_station": "res://assets/icons/place_station.svg",
	&"place_underpass": "res://assets/icons/place_underpass.svg",
	&"place_market": "res://assets/icons/place_market.svg",
	&"place_recycling": "res://assets/icons/place_recycling.svg",
	&"place_clinic": "res://assets/icons/place_clinic.svg",
	&"place_embankment": "res://assets/icons/place_embankment.svg",
	&"transport_walk": "res://assets/icons/transport_walk.svg",
	&"transport_bus": "res://assets/icons/transport_bus.svg",
	&"transport_tram": "res://assets/icons/transport_tram.svg",
	&"utility_settings": "res://assets/icons/utility_settings.svg",
	&"utility_info": "res://assets/icons/utility_info.svg",
	&"utility_chevron_right": "res://assets/icons/utility_chevron_right.svg",
	&"utility_locked": "res://assets/icons/utility_locked.svg",
}

static var _texture_cache: Dictionary = {}


static func has(icon_id: StringName) -> bool:
	return ICON_PATHS.has(icon_id)


static func path_for(icon_id: StringName) -> String:
	return String(ICON_PATHS.get(icon_id, ""))


## Missing and invalid resources return null and are not cached. That keeps an
## incomplete asset package safe and allows a later import to be picked up.
static func texture(icon_id: StringName) -> Texture2D:
	if not has(icon_id):
		return null
	var cached: Variant = _texture_cache.get(icon_id)
	if cached is Texture2D and is_instance_valid(cached):
		return cached as Texture2D
	var asset_path := path_for(icon_id)
	if asset_path.is_empty() or not ResourceLoader.exists(asset_path, "Texture2D"):
		return null
	var loaded := ResourceLoader.load(
		asset_path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_REUSE
	) as Texture2D
	if loaded == null:
		return null
	_texture_cache[icon_id] = loaded
	return loaded


static func all_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_id: Variant in ICON_PATHS.keys():
		result.append(StringName(raw_id))
	result.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return result
