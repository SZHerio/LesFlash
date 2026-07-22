class_name GameCalendar
extends RefCounted

## A configurable civil calendar advanced only by explicit gameplay decisions.
## It deliberately has no dependency on wall-clock time or Engine process time.

var year: int = GameRules.DEFAULT_START_YEAR
var month: int = GameRules.DEFAULT_START_MONTH
var day: int = GameRules.DEFAULT_START_DAY
var minute_of_day: int = GameRules.DEFAULT_START_MINUTE_OF_DAY
var elapsed_minutes: int = 0

var month_lengths: Array[int] = []
var minutes_per_day: int = GameRules.DEFAULT_MINUTES_PER_DAY
var leap_years_enabled: bool = true
var leap_month: int = 2
var leap_every: int = 4
var leap_except_every: int = 100
var leap_include_every: int = 400


func _init(config: Dictionary = {}, stamp: Dictionary = {}) -> void:
	if not configure(config):
		configure(GameRules.default_calendar_config())
	var initial_stamp := GameRules.default_start_stamp()
	for key in stamp:
		initial_stamp[key] = stamp[key]
	if not set_stamp(initial_stamp):
		set_stamp(GameRules.default_start_stamp())


func configure(config: Dictionary) -> bool:
	var candidate := get_config() if not month_lengths.is_empty() else GameRules.default_calendar_config()
	for key in config:
		candidate[key] = config[key]

	if not candidate.has("month_lengths"):
		return false
	var raw_month_lengths: Variant = candidate["month_lengths"]
	var raw_type := typeof(raw_month_lengths)
	if raw_type != TYPE_ARRAY and raw_type != TYPE_PACKED_INT32_ARRAY and raw_type != TYPE_PACKED_INT64_ARRAY:
		return false
	if raw_month_lengths.is_empty() or raw_month_lengths.size() > 24:
		return false
	var parsed_month_lengths: Array[int] = []
	for raw_length in raw_month_lengths:
		if not _is_integral_number(raw_length):
			return false
		var parsed_length := int(raw_length)
		if parsed_length < 1 or parsed_length > 1_000:
			return false
		parsed_month_lengths.append(parsed_length)

	var integer_keys := [
		"minutes_per_day",
		"leap_month",
		"leap_every",
		"leap_except_every",
		"leap_include_every",
	]
	for key in integer_keys:
		if not candidate.has(key) or not _is_integral_number(candidate[key]):
			return false
	if not candidate.has("leap_years_enabled") or typeof(candidate["leap_years_enabled"]) != TYPE_BOOL:
		return false

	var parsed_minutes_per_day := int(candidate["minutes_per_day"])
	var parsed_leap_month := int(candidate["leap_month"])
	var parsed_leap_every := int(candidate["leap_every"])
	var parsed_leap_except_every := int(candidate["leap_except_every"])
	var parsed_leap_include_every := int(candidate["leap_include_every"])
	var parsed_leap_enabled: bool = candidate["leap_years_enabled"]
	if parsed_minutes_per_day < 1 or parsed_minutes_per_day > 100_000:
		return false
	if parsed_leap_month < 1 or parsed_leap_month > parsed_month_lengths.size():
		return false
	if parsed_leap_every < 0 or parsed_leap_except_every < 0 or parsed_leap_include_every < 0:
		return false
	if parsed_leap_enabled and parsed_leap_every == 0:
		return false

	month_lengths = parsed_month_lengths
	minutes_per_day = parsed_minutes_per_day
	leap_years_enabled = parsed_leap_enabled
	leap_month = parsed_leap_month
	leap_every = parsed_leap_every
	leap_except_every = parsed_leap_except_every
	leap_include_every = parsed_leap_include_every
	return true


func get_config() -> Dictionary:
	return {
		"month_lengths": month_lengths.duplicate(),
		"minutes_per_day": minutes_per_day,
		"leap_years_enabled": leap_years_enabled,
		"leap_month": leap_month,
		"leap_every": leap_every,
		"leap_except_every": leap_except_every,
		"leap_include_every": leap_include_every,
	}


func current_stamp() -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"minute_of_day": minute_of_day,
		"elapsed_minutes": elapsed_minutes,
	}


func set_stamp(stamp: Dictionary) -> bool:
	if not is_valid_stamp(stamp, true):
		return false
	year = int(stamp["year"])
	month = int(stamp["month"])
	day = int(stamp["day"])
	minute_of_day = int(stamp["minute_of_day"])
	elapsed_minutes = int(stamp["elapsed_minutes"])
	return true


func is_valid_stamp(stamp: Dictionary, require_elapsed: bool = false) -> bool:
	for key in ["year", "month", "day", "minute_of_day"]:
		if not stamp.has(key) or not _is_integral_number(stamp[key]):
			return false
	if require_elapsed and (not stamp.has("elapsed_minutes") or not _is_integral_number(stamp["elapsed_minutes"])):
		return false
	var stamp_year := int(stamp["year"])
	var stamp_month := int(stamp["month"])
	var stamp_day := int(stamp["day"])
	var stamp_minute := int(stamp["minute_of_day"])
	if stamp_year < -1_000_000 or stamp_year > 1_000_000:
		return false
	if stamp_month < 1 or stamp_month > month_lengths.size():
		return false
	if stamp_day < 1 or stamp_day > days_in_month(stamp_year, stamp_month):
		return false
	if stamp_minute < 0 or stamp_minute >= minutes_per_day:
		return false
	if stamp.has("elapsed_minutes"):
		if not _is_integral_number(stamp["elapsed_minutes"]) or int(stamp["elapsed_minutes"]) < 0:
			return false
	return true


func is_leap_year(value: int) -> bool:
	if not leap_years_enabled or leap_every <= 0:
		return false
	if value % leap_every != 0:
		return false
	if leap_include_every > 0 and value % leap_include_every == 0:
		return true
	if leap_except_every > 0 and value % leap_except_every == 0:
		return false
	return true


func days_in_month(for_year: int, for_month: int) -> int:
	if for_month < 1 or for_month > month_lengths.size():
		return 0
	var result: int = month_lengths[for_month - 1]
	if for_month == leap_month and is_leap_year(for_year):
		result += 1
	return result


func advance_minutes(amount: int) -> bool:
	if amount < 0 or amount > GameRules.MAX_TIME_ADVANCE_MINUTES:
		return false
	if amount == 0:
		return true
	if elapsed_minutes > 9_000_000_000_000_000 - amount:
		return false
	var previous_stamp := current_stamp()
	var combined_minutes := minute_of_day + amount
	@warning_ignore("integer_division")
	var whole_days := combined_minutes / minutes_per_day
	minute_of_day = combined_minutes % minutes_per_day
	_advance_date_days(whole_days)
	if year < -1_000_000 or year > 1_000_000:
		year = int(previous_stamp["year"])
		month = int(previous_stamp["month"])
		day = int(previous_stamp["day"])
		minute_of_day = int(previous_stamp["minute_of_day"])
		elapsed_minutes = int(previous_stamp["elapsed_minutes"])
		return false
	elapsed_minutes += amount
	return true


func advance_hours(amount: int) -> bool:
	if amount < 0:
		return false
	@warning_ignore("integer_division")
	var minutes_per_hour := minutes_per_day / 24
	if minutes_per_hour <= 0:
		return false
	if amount > GameRules.MAX_TIME_ADVANCE_MINUTES / minutes_per_hour:
		return false
	return advance_minutes(amount * minutes_per_hour)


func advance_days(amount: int) -> bool:
	if amount < 0 or amount > GameRules.MAX_TIME_ADVANCE_MINUTES / minutes_per_day:
		return false
	return advance_minutes(amount * minutes_per_day)


func future_stamp(minutes_from_now: int) -> Dictionary:
	if minutes_from_now < 0:
		return {}
	var future := clone()
	if not future.advance_minutes(minutes_from_now):
		return {}
	return future.current_stamp()


func is_stamp_due(due: Dictionary) -> bool:
	if not is_valid_stamp(due, false):
		return false
	return compare_stamps(due, current_stamp()) <= 0


static func compare_stamps(left: Dictionary, right: Dictionary) -> int:
	for key in ["year", "month", "day", "minute_of_day"]:
		if not left.has(key) or not right.has(key):
			return 0
		var left_value := int(left[key])
		var right_value := int(right[key])
		if left_value < right_value:
			return -1
		if left_value > right_value:
			return 1
	return 0


func to_dict() -> Dictionary:
	return {
		"config": get_config(),
		"stamp": current_stamp(),
	}


static func from_dict(data: Dictionary) -> GameCalendar:
	if typeof(data.get("config", null)) != TYPE_DICTIONARY:
		return null
	if typeof(data.get("stamp", null)) != TYPE_DICTIONARY:
		return null
	var result := GameCalendar.new()
	if not result.configure(data["config"]):
		return null
	if not result.set_stamp(data["stamp"]):
		return null
	var validation := result.validate()
	return result if validation["ok"] else null


func clone() -> GameCalendar:
	var result := GameCalendar.from_dict(to_dict())
	if result == null:
		push_error("GameCalendar clone failed validation; using a default calendar.")
		return GameCalendar.new()
	return result


func validate() -> Dictionary:
	var errors: Array[String] = []
	if month_lengths.is_empty():
		errors.append("calendar.month_lengths must not be empty")
	elif month_lengths.size() > 24:
		errors.append("calendar.month_lengths contains too many months")
	for index in range(month_lengths.size()):
		if month_lengths[index] < 1 or month_lengths[index] > 1_000:
			errors.append("calendar.month_lengths[%d] is outside allowed range" % index)
	if minutes_per_day < 1 or minutes_per_day > 100_000:
		errors.append("calendar.minutes_per_day is outside allowed range")
	if leap_month < 1 or leap_month > month_lengths.size():
		errors.append("calendar.leap_month is outside configured months")
	if leap_every < 0 or leap_except_every < 0 or leap_include_every < 0:
		errors.append("calendar leap intervals cannot be negative")
	if leap_years_enabled and leap_every <= 0:
		errors.append("calendar.leap_every must be positive when leap years are enabled")
	if not is_valid_stamp(current_stamp(), true):
		errors.append("calendar current stamp is invalid")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
	}


func _advance_date_days(amount: int) -> void:
	var remaining := amount
	while remaining > 0:
		var days_left_in_month := days_in_month(year, month) - day
		if remaining <= days_left_in_month:
			day += remaining
			return
		remaining -= days_left_in_month + 1
		day = 1
		month += 1
		if month > month_lengths.size():
			month = 1
			year += 1


static func _is_integral_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var float_value := float(value)
	return is_finite(float_value) and float_value == floor(float_value)
