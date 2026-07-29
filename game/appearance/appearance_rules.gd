class_name AppearanceRules
extends RefCounted

## Как героя читают, не спрашивая.
##
## Нигде не хранится и нигде не показывается числом — выводится из того, что уже
## записано: что надето, цело ли оно, сколько дней без мытья и есть ли крыша.
## Игрок узнаёт своё положение из того, что с ним разговаривают иначе, пускают
## иначе и останавливают иначе.
##
## Это единственная из осей, которую нельзя купить один раз. Куртка не портится
## за ночь, а неделя без бани — портится, и поэтому вид требует внимания, а не
## одной покупки.

const EquipmentRulesScript := preload("res://game/equipment/equipment_rules.gd")
const ItemCatalogScript := preload("res://core/inventory/item_catalog.gd")

## Одежда, которую видно. Инструмент и сумка не в счёт: по ним не судят.
const VISIBLE_SLOTS := ["torso", "feet", "gloves"]

## После скольких дней без мытья это становится заметно, и после скольких —
## первым, что о человеке узнают.
const NOTICEABLE_DAYS := 3
const UNMISTAKABLE_DAYS := 8

const RESPECTABLE := "respectable"
const ORDINARY := "ordinary"
const ROUGH := "rough"
const DERELICT := "derelict"

## От худшего к лучшему — порядок нужен, чтобы «не хуже такого-то» имело смысл.
const ORDER := [DERELICT, ROUGH, ORDINARY, RESPECTABLE]

const BANDS := {
	DERELICT: {
		"title": "как есть",
		"note": "Смотрят и отходят. Разговор начинается с того, что вас просят отойти.",
	},
	ROUGH: {
		"title": "обношенный",
		"note": "Видно, что с улицы, но подходить не боятся.",
	},
	ORDINARY: {
		"title": "обыкновенный",
		"note": "Никто не оборачивается. Для большинства мест этого достаточно.",
	},
	RESPECTABLE: {
		"title": "прилично",
		"note": "Принимают за своего, пока не заговорите о ночлеге.",
	},
}


## Насколько героя видно с хорошей стороны, от 0 до 100. Наружу это число не
## выходит — только полоса, которая из него следует.
static func score_of(run_state: RunState, has_roof: bool = false) -> int:
	if run_state == null:
		return 0
	var score := 30
	for raw_stack: Variant in EquipmentRulesScript.equipped_stacks(run_state.inventory):
		var stack: Dictionary = raw_stack
		var definition: Variant = ItemCatalogScript.definition(String(stack.get("item_id", "")))
		if definition == null:
			continue
		if String(definition.call("equip_slot")) not in VISIBLE_SLOTS:
			continue
		# Целое считается за целое; изношенное видно, и оно засчитывается хуже.
		var condition := clampi(int(stack.get("condition", 100)), 0, 100)
		score += 15 * condition / 100
	var unwashed := run_state.days_unwashed()
	if unwashed >= UNMISTAKABLE_DAYS:
		score -= 40
	elif unwashed >= NOTICEABLE_DAYS:
		score -= 18
	# Крыша — это не только тепло: где-то же надо привести себя в порядок.
	if has_roof:
		score += 12
	return clampi(score, 0, 100)


static func band_of(run_state: RunState, has_roof: bool = false) -> String:
	var score := score_of(run_state, has_roof)
	if score >= 75:
		return RESPECTABLE
	if score >= 50:
		return ORDINARY
	if score >= 25:
		return ROUGH
	return DERELICT


static func title_of(band_id: String) -> String:
	return String(Dictionary(BANDS.get(band_id, {})).get("title", ""))


static func note_of(band_id: String) -> String:
	return String(Dictionary(BANDS.get(band_id, {})).get("note", ""))


## Не хуже требуемого. Полосы упорядочены, поэтому «пустят, если не хуже
## обношенного» — это одно сравнение, а не список.
static func at_least(band_id: String, required_id: String) -> bool:
	var have := ORDER.find(band_id)
	var need := ORDER.find(required_id)
	return have >= 0 and need >= 0 and have >= need


static func is_band(band_id: String) -> bool:
	return BANDS.has(band_id)


## Проверка самой шкалы: каждая полоса должна быть достижима, и худшая — тоже.
## Полоса, в которую нельзя попасть, — это описание, которого никто не увидит.
static func validate() -> Dictionary:
	var errors: Array[String] = []
	for band_id: String in ORDER:
		if not BANDS.has(band_id):
			errors.append("полоса %s объявлена в порядке, но не описана" % band_id)
			continue
		if String(BANDS[band_id].get("title", "")).strip_edges().is_empty():
			errors.append("%s: нет названия" % band_id)
		if String(BANDS[band_id].get("note", "")).strip_edges().is_empty():
			errors.append("%s: нечего сказать о том, как это выглядит" % band_id)
	if BANDS.size() != ORDER.size():
		errors.append("описанных полос больше, чем упорядоченных")
	return {"ok": errors.is_empty(), "errors": errors}
