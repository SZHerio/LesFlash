class_name ShelterCatalogValidator
extends RefCounted

## Strict schema validation for data-authored shelter options.
##
## The validator deliberately accepts only passive JSON values. Shelter content
## cannot carry scripts, callables or state mutations of its own.

const SCHEMA_VERSION := 1
const REQUIRED_CATEGORIES := ["street", "night_shelter", "paid_room"]
const ROOT_FIELDS := [
	"schema_version",
	"catalog_id",
	"catalog_version",
	"currency_code",
	"options",
]
const OPTION_FIELDS := [
	"shelter_id",
	"category_id",
	"title",
	"description",
	"location_ids",
	"check_in_windows",
	"wake_minute",
	"minimum_sleep_minutes",
	"price_arden",
	"meter_effects",
]
const WINDOW_FIELDS := ["opens_minute", "closes_minute"]


static func validate(catalog: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not catalog is Dictionary:
		return _result(["shelter catalog must be a dictionary"])
	var source: Dictionary = catalog
	_check_known_fields(source, ROOT_FIELDS, "shelters", errors)
	_expect_exact_int(source.get("schema_version", null), SCHEMA_VERSION, "shelters.schema_version", errors)
	_expect_positive_int(source.get("catalog_version", null), "shelters.catalog_version", errors)
	_expect_id(source.get("catalog_id", null), "shelters.catalog_id", errors)
	if source.get("currency_code", null) != "ARD":
		errors.append("shelters.currency_code must be ARD")
	var options: Variant = source.get("options", null)
	if not options is Array:
		errors.append("shelters.options must be an array")
		return _result(errors)
	if options.size() < REQUIRED_CATEGORIES.size():
		errors.append("shelters.options must contain at least three options")
	_validate_options(options, errors)
	return _result(errors)


static func _validate_options(options: Array, errors: Array[String]) -> void:
	var seen_ids: Dictionary = {}
	var seen_categories: Dictionary = {}
	for index in range(options.size()):
		var path := "shelters.options[%d]" % index
		if not options[index] is Dictionary:
			errors.append("%s must be a dictionary" % path)
			continue
		var option: Dictionary = options[index]
		_check_known_fields(option, OPTION_FIELDS, path, errors)
		var shelter_id := _expect_id(option.get("shelter_id", null), "%s.shelter_id" % path, errors)
		if not shelter_id.is_empty() and seen_ids.has(shelter_id):
			errors.append("duplicate shelter_id: %s" % shelter_id)
		seen_ids[shelter_id] = true
		var category_id := String(option.get("category_id", ""))
		if category_id not in REQUIRED_CATEGORIES:
			errors.append("%s.category_id is unknown" % path)
		else:
			seen_categories[category_id] = true
		_expect_russian_text(option.get("title", null), "%s.title" % path, errors)
		_expect_russian_text(option.get("description", null), "%s.description" % path, errors)
		_validate_id_array(option.get("location_ids", null), "%s.location_ids" % path, errors)
		_validate_windows(option.get("check_in_windows", null), "%s.check_in_windows" % path, errors)
		_expect_int_range(option.get("wake_minute", null), 0, 1439, "%s.wake_minute" % path, errors)
		_expect_int_range(option.get("minimum_sleep_minutes", null), 1, 1440, "%s.minimum_sleep_minutes" % path, errors)
		_validate_price(option.get("price_arden", null), category_id, "%s.price_arden" % path, errors)
		_validate_meter_effects(option.get("meter_effects", null), "%s.meter_effects" % path, errors)
	for category_id: String in REQUIRED_CATEGORIES:
		if not seen_categories.has(category_id):
			errors.append("shelters.options must include category %s" % category_id)


static func _validate_windows(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or value.is_empty():
		errors.append("%s must be a non-empty array" % path)
		return
	var occupied: Array[bool] = []
	occupied.resize(1440)
	occupied.fill(false)
	for index in range(value.size()):
		var window_path := "%s[%d]" % [path, index]
		if not value[index] is Dictionary:
			errors.append("%s must be a dictionary" % window_path)
			continue
		var window: Dictionary = value[index]
		_check_known_fields(window, WINDOW_FIELDS, window_path, errors)
		var opens_value: Variant = window.get("opens_minute", null)
		var closes_value: Variant = window.get("closes_minute", null)
		if not _is_int_in_range(opens_value, 0, 1439):
			errors.append("%s.opens_minute must be an integer from 0 to 1439" % window_path)
			continue
		if not _is_int_in_range(closes_value, 1, 1440):
			errors.append("%s.closes_minute must be an integer from 1 to 1440" % window_path)
			continue
		var opens := int(opens_value)
		var closes := int(closes_value)
		if opens == closes:
			errors.append("%s cannot cover zero or twenty-four hours" % window_path)
			continue
		for minute: int in _window_minutes(opens, closes):
			if occupied[minute]:
				errors.append("%s overlaps another check-in window" % window_path)
				break
			occupied[minute] = true


static func _window_minutes(opens: int, closes: int) -> Array[int]:
	var result: Array[int] = []
	if opens < closes:
		for minute in range(opens, closes):
			result.append(minute)
		return result
	for minute in range(opens, 1440):
		result.append(minute)
	for minute in range(0, closes):
		result.append(minute)
	return result


static func _validate_price(value: Variant, category_id: String, path: String, errors: Array[String]) -> void:
	if not _is_int_in_range(value, 0, 1_000_000_000_000):
		errors.append("%s must be a non-negative integer" % path)
		return
	var price := int(value)
	if category_id == "street" and price != 0:
		errors.append("%s must be zero for a street shelter" % path)
	if category_id == "paid_room" and price <= 0:
		errors.append("%s must be positive for a paid room" % path)


static func _validate_meter_effects(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Dictionary or value.is_empty():
		errors.append("%s must be a non-empty dictionary" % path)
		return
	var effects: Dictionary = value
	for raw_key: Variant in effects:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in GameRules.METER_KEYS:
			errors.append("%s contains an unknown meter: %s" % [path, String(raw_key)])
			continue
		if not _is_int_in_range(effects[raw_key], -100, 100) or int(effects[raw_key]) == 0:
			errors.append("%s.%s must be a non-zero integer from -100 to 100" % [path, raw_key])
	if typeof(effects.get("energy", null)) != TYPE_INT or int(effects.get("energy", 0)) <= 0:
		errors.append("%s.energy must provide positive recovery" % path)


static func _validate_id_array(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or value.is_empty():
		errors.append("%s must be a non-empty array" % path)
		return
	var seen: Dictionary = {}
	for index in range(value.size()):
		var identifier := _expect_id(value[index], "%s[%d]" % [path, index], errors)
		if not identifier.is_empty() and seen.has(identifier):
			errors.append("%s repeats %s" % [path, identifier])
		seen[identifier] = true


static func _expect_id(value: Variant, path: String, errors: Array[String]) -> String:
	if typeof(value) != TYPE_STRING:
		errors.append("%s must be a lower_snake_case string" % path)
		return ""
	var identifier := String(value)
	if identifier.is_empty() or identifier[0] == "_" or identifier[-1] == "_":
		errors.append("%s must be a lower_snake_case string" % path)
		return ""
	for character: String in identifier:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			errors.append("%s must be a lower_snake_case string" % path)
			return ""
	return identifier


static func _expect_russian_text(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append("%s must be non-empty text" % path)
		return
	var text := String(value)
	for character: String in text:
		if (character >= "А" and character <= "я") or character in ["Ё", "ё"]:
			return
	errors.append("%s must contain Russian text" % path)


static func _check_known_fields(source: Dictionary, allowed: Array, path: String, errors: Array[String]) -> void:
	for raw_key: Variant in source:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in allowed:
			errors.append("%s contains unknown field %s" % [path, String(raw_key)])


static func _expect_exact_int(value: Variant, expected: int, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_INT or int(value) != expected:
		errors.append("%s must be integer %d" % [path, expected])


static func _expect_positive_int(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_INT or int(value) <= 0:
		errors.append("%s must be a positive integer" % path)


static func _expect_int_range(value: Variant, minimum: int, maximum: int, path: String, errors: Array[String]) -> void:
	if not _is_int_in_range(value, minimum, maximum):
		errors.append("%s must be an integer from %d to %d" % [path, minimum, maximum])


static func _is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _result(errors: Array) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}
