class_name EventContentValidator
extends RefCounted

const JsonValidator := preload("res://core/save/json_value_validator.gd")
const ConditionEvaluator := preload("res://game/events/event_condition_evaluator.gd")

const SCHEMA_VERSION := 1
const MIN_CARDS := 30
const MAX_CARDS := 90
const TONES := ["adverse", "neutral", "positive"]
const EFFECT_TYPES := [
	"advance_time",
	"change_state",
	"change_money",
	"add_item",
	"remove_item",
	"shift_polarity",
	"unlock_skill",
	"advance_skill",
	"mastery",
	"deferred",
	"knowledge",
]
const OPERATORS := [">=", ">", "==", "!=", "<", "<="]


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"ok": false, "errors": ["Каталог событий должен быть объектом"]}
	var catalog: Dictionary = value
	if catalog.get("schema_version", null) != SCHEMA_VERSION:
		errors.append("catalog.schema_version должен быть равен %d" % SCHEMA_VERSION)
	if not _valid_id(catalog.get("catalog_id", null)):
		errors.append("catalog.catalog_id должен быть стабильным идентификатором")
	var cards_value: Variant = catalog.get("cards", null)
	if not cards_value is Array:
		errors.append("catalog.cards должен быть массивом")
	else:
		if cards_value.size() < MIN_CARDS or cards_value.size() > MAX_CARDS:
			errors.append(
				"catalog.cards должен содержать от %d до %d карточек" % [MIN_CARDS, MAX_CARDS]
			)
		_validate_cards(cards_value, errors)
	var json_result := JsonValidator.validate(catalog, "event_catalog")
	for raw_error: Variant in Array(json_result.get("errors", [])):
		errors.append(String(raw_error))
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_cards(cards: Array, errors: Array[String]) -> void:
	var ids: Dictionary = {}
	var option_ids: Dictionary = {}
	var deferred_ids: Dictionary = {}
	for index: int in cards.size():
		var raw_card: Variant = cards[index]
		var path := "cards[%d]" % index
		if not raw_card is Dictionary:
			errors.append("%s должен быть объектом" % path)
			continue
		var card: Dictionary = raw_card
		var card_id := String(card.get("id", ""))
		if not _valid_id(card_id) or ids.has(card_id):
			errors.append("%s.id пуст, повторяется или имеет неверный формат" % path)
		else:
			ids[card_id] = true
		_validate_text(card.get("title", null), "%s.title" % path, 3, 80, errors)
		_validate_text(card.get("body", null), "%s.body" % path, 20, 420, errors)
		if String(card.get("tone", "")) not in TONES:
			errors.append("%s.tone должен быть adverse, neutral или positive" % path)
		if not _integer_range(card.get("base_weight", null), 1, 10_000):
			errors.append("%s.base_weight должен быть целым числом 1–10000" % path)
		if not _integer_range(card.get("luck_bias", null), -1_000, 1_000):
			errors.append("%s.luck_bias должен быть целым числом −1000–1000" % path)
		if not _integer_range(card.get("cooldown_minutes", null), 0, 100_000):
			errors.append("%s.cooldown_minutes должен быть неотрицательным целым числом" % path)
		_validate_string_array(card.get("locations", null), "%s.locations" % path, true, errors)
		_validate_string_array(
			card.get("source_kinds", null),
			"%s.source_kinds" % path,
			true,
			errors
		)
		_validate_string_array(card.get("tags", null), "%s.tags" % path, false, errors)
		_validate_conditions(card.get("conditions", null), "%s.conditions" % path, errors)
		_validate_options(
			card.get("options", null),
			card_id,
			path,
			option_ids,
			deferred_ids,
			errors
		)


static func _validate_options(
	raw_options: Variant,
	card_id: String,
	path: String,
	option_ids: Dictionary,
	deferred_ids: Dictionary,
	errors: Array[String]
) -> void:
	if not raw_options is Array or raw_options.is_empty():
		errors.append("%s.options должен быть непустым массивом" % path)
		return
	var has_unconditional_exit := false
	for index: int in raw_options.size():
		var raw_option: Variant = raw_options[index]
		var option_path := "%s.options[%d]" % [path, index]
		if not raw_option is Dictionary:
			errors.append("%s должен быть объектом" % option_path)
			continue
		var option: Dictionary = raw_option
		var option_id := String(option.get("id", ""))
		var qualified_id := "%s:%s" % [card_id, option_id]
		if not _valid_id(option_id) or option_ids.has(qualified_id):
			errors.append("%s.id пуст, повторяется или имеет неверный формат" % option_path)
		else:
			option_ids[qualified_id] = true
		_validate_text(option.get("label", null), "%s.label" % option_path, 2, 120, errors)
		_validate_text(option.get("outcome", null), "%s.outcome" % option_path, 8, 300, errors)
		var conditions: Variant = option.get("conditions", null)
		_validate_conditions(conditions, "%s.conditions" % option_path, errors)
		if conditions is Array and conditions.is_empty():
			has_unconditional_exit = true
		_validate_effects(
			option.get("effects", null),
			card_id,
			option_path,
			deferred_ids,
			errors
		)
	if not has_unconditional_exit:
		errors.append("%s должен иметь хотя бы один безусловный выход" % path)


static func _validate_conditions(
	raw_conditions: Variant,
	path: String,
	errors: Array[String]
) -> void:
	if not raw_conditions is Array:
		errors.append("%s должен быть массивом" % path)
		return
	for index: int in raw_conditions.size():
		var raw_condition: Variant = raw_conditions[index]
		var condition_path := "%s[%d]" % [path, index]
		if not raw_condition is Dictionary:
			errors.append("%s должен быть объектом" % condition_path)
			continue
		var condition: Dictionary = raw_condition
		if String(condition.get("kind", "")) not in ConditionEvaluator.SUPPORTED_KINDS:
			errors.append("%s.kind неизвестен" % condition_path)
		if String(condition.get("operator", "==")) not in OPERATORS:
			errors.append("%s.operator неизвестен" % condition_path)
		if not condition.has("value"):
			errors.append("%s.value отсутствует" % condition_path)
		if String(condition.get("kind", "")) not in ["location", "era", "weather"]:
			if not _valid_id(condition.get("id", null)):
				errors.append("%s.id должен быть стабильным идентификатором" % condition_path)
		if condition.has("blocked_reason"):
			_validate_text(
				condition.get("blocked_reason"),
				"%s.blocked_reason" % condition_path,
				4,
				180,
				errors
			)


static func _validate_effects(
	raw_effects: Variant,
	card_id: String,
	path: String,
	deferred_ids: Dictionary,
	errors: Array[String]
) -> void:
	if not raw_effects is Array:
		errors.append("%s.effects должен быть массивом" % path)
		return
	for index: int in raw_effects.size():
		var raw_effect: Variant = raw_effects[index]
		var effect_path := "%s.effects[%d]" % [path, index]
		if not raw_effect is Dictionary:
			errors.append("%s должен быть объектом" % effect_path)
			continue
		var effect: Dictionary = raw_effect
		var effect_type := String(effect.get("type", ""))
		if effect_type not in EFFECT_TYPES:
			errors.append("%s.type неизвестен" % effect_path)
			continue
		if effect_type == "advance_time" and not _integer_range(
			effect.get("minutes", null),
			0,
			GameRules.MAX_TIME_ADVANCE_MINUTES
		):
			errors.append("%s.minutes некорректно" % effect_path)
		elif effect_type == "deferred":
			_validate_deferred(effect, card_id, effect_path, deferred_ids, errors)


static func _validate_deferred(
	effect: Dictionary,
	card_id: String,
	path: String,
	deferred_ids: Dictionary,
	errors: Array[String]
) -> void:
	var deferred_id := String(effect.get("deferred_id", ""))
	if not _valid_id(deferred_id) or deferred_ids.has(deferred_id):
		errors.append("%s.deferred_id пуст, повторяется или имеет неверный формат" % path)
	else:
		deferred_ids[deferred_id] = true
	if String(effect.get("source_id", "")) != card_id:
		errors.append("%s.source_id должен ссылаться на карточку %s" % [path, card_id])
	if not _valid_id(effect.get("effect_id", null)):
		errors.append("%s.effect_id некорректен" % path)
	if not _integer_range(effect.get("delay_minutes", null), 1, 100_000):
		errors.append("%s.delay_minutes должен быть положительным целым числом" % path)
	if not effect.get("payload", null) is Dictionary:
		errors.append("%s.payload должен быть объектом" % path)


static func _validate_string_array(
	value: Variant,
	path: String,
	require_non_empty: bool,
	errors: Array[String]
) -> void:
	if not value is Array or (require_non_empty and value.is_empty()):
		errors.append("%s должен быть%s массивом строк" % [
			path,
			" непустым" if require_non_empty else "",
		])
		return
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not _valid_id(entry) or seen.has(String(entry)):
			errors.append("%s содержит пустое, повторное или некорректное значение" % path)
			return
		seen[String(entry)] = true


static func _validate_text(
	value: Variant,
	path: String,
	minimum: int,
	maximum: int,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_STRING:
		errors.append("%s должен быть строкой" % path)
		return
	var text := String(value).strip_edges()
	if text.length() < minimum or text.length() > maximum:
		errors.append("%s должен содержать %d–%d символов" % [path, minimum, maximum])


static func _integer_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := String(value)
	if identifier.is_empty() or identifier != identifier.to_lower():
		return false
	for character: String in identifier:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true
