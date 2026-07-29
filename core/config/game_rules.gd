class_name GameRules
extends RefCounted

## Central, data-only limits for the M1 simulation core.
##
## Values that are likely to change during balancing live here so the state model
## and content resolvers do not have to duplicate magic numbers.

const RUN_STATE_VERSION_V1 := 1
const RUN_STATE_VERSION_V2 := 2
const RUN_STATE_VERSION_V3 := 3
const RUN_STATE_VERSION_V4 := 4
const RUN_STATE_VERSION_V5 := 5
const RUN_STATE_VERSION_V6 := 6
const RUN_STATE_VERSION_V7 := 7
const LEGACY_SAVE_VERSION := RUN_STATE_VERSION_V1
const PREVIOUS_SAVE_VERSION := RUN_STATE_VERSION_V6
const SAVE_VERSION := RUN_STATE_VERSION_V7

const CHARACTERISTIC_MIN := 1
const CHARACTERISTIC_MAX := 10
const CHARACTERISTIC_BUDGET := 18
const CHARACTERISTIC_KEYS := [
	"strength",
	"charisma",
	"intelligence",
	"luck",
]
const DEFAULT_CHARACTERISTICS := {
	"strength": 5,
	"charisma": 5,
	"intelligence": 4,
	"luck": 4,
}

const METER_MIN := 0
const METER_MAX := 100
const METER_KEYS := [
	"health",
	"hunger",
	"energy",
	"tension",
	"mental_state",
]
const DEFAULT_METERS := {
	"health": 100,
	"hunger": 0,
	"energy": 100,
	"tension": 0,
	"mental_state": 50,
}

const POLARITY_MIN := -100
const POLARITY_MAX := 100
const STORED_POLARITY_KEYS := [
	"physical_specialization", # Power (-) <-> Endurance (+)
	"execution_style", # Pace (-) <-> Control (+)
	"influence_style", # Pressure (-) <-> Authority (+)
	"attention_distribution", # Concentration (-) <-> Overview (+)
	"uncertainty_behavior", # Reconnaissance (-) <-> Mastery (+)
	"decision_priority", # Opportunity (-) <-> Safety (+)
]
const COMPUTED_PROFILE_KEYS := [
	"relationship_investment", # Reach (-) <-> Depth (+)
	"knowledge_profile", # Specialization (-) <-> Erudition (+)
]
const PROFILE_FORMATION_EVIDENCE := 5

const SKILL_MIN_RANK := 0
const SKILL_MAX_RANK := 3
const SKILL_KEYS := [
	"city_navigation",
	"cargo_handling",
	"cooking",
	"repair",
	"first_aid",
	"trade",
	"search",
]
const LEGACY_SKILL_KEYS := [
	"city_navigation",
	"cargo_handling",
	"cooking",
	"repair",
	"first_aid",
	"trade",
]
## A skill grows from varied practice, never from repetition. What counts is
## how many *different* things the hero has done with it: sorting the same
## bundle twenty times teaches the twentieth nothing the second did not.
##
## The thresholds are distinct practice sources, not attempts.
const SKILL_PRACTICE_FOR_RANK := [3, 7, 12]
const SKILL_PRACTICE_SOURCES_MAX := 64


## The rank a given number of distinct practice sources has earned.
static func rank_for_practice(distinct_sources: int) -> int:
	var rank := 0
	for index: int in SKILL_PRACTICE_FOR_RANK.size():
		if distinct_sources >= int(SKILL_PRACTICE_FOR_RANK[index]):
			rank = index + 1
	return mini(rank, SKILL_MAX_RANK)


static func default_skill_practice() -> Dictionary:
	var result: Dictionary = {}
	for key: String in SKILL_KEYS:
		result[key] = []
	return result


const MASTERY_POINTS_MIN := 0
const MASTERY_POINTS_MAX := 1_000_000

## Exact integer range shared by JSON and IEEE-754 doubles. Larger exact
## values must be serialized as strings, as RNG seed/state already are.
const JSON_SAFE_INTEGER_MAX := 9_007_199_254_740_991

## A single confirmed decision may skip up to ten leap-length years. Longer
## passages are split into life chapters, which keeps calendar work bounded.
## How long a run may last before it stops on its own. Seven days was the
## prototype's whole horizon; a game about a life needs somewhere for years to
## happen, and the number is here rather than in the survival state so it reads
## as a rule of the game and not an implementation detail.
const DEFAULT_RUN_HORIZON_DAYS := 400
const DEFAULT_RUN_HORIZON_MINUTES := DEFAULT_RUN_HORIZON_DAYS * DEFAULT_MINUTES_PER_DAY

const MAX_TIME_ADVANCE_MINUTES := 10 * 366 * 24 * 60

const KNOWLEDGE_LEVEL_MIN := 1
const KNOWLEDGE_LEVEL_MAX := 3

## Money is stored in the smallest unit of the fictional currency.
## The cap remains below JSON's exact-integer limit (2^53 - 1).
const MONEY_MIN := 0
const MONEY_MAX := 1_000_000_000_000
const INVENTORY_QUANTITY_MIN := 1
const INVENTORY_QUANTITY_MAX := 1_000_000

const START_AGE_YEARS := 18
const DEFAULT_START_YEAR := 1980
## Июнь. Игра начиналась в сентябре — во второй по тяжести поре года, — и
## приёмочная проверка показала, чем это кончается: ночи бьют по здоровью,
## герой лечится каждый день, деньги уходят в аптеку вместо еды, и на пятый
## день он умирает от голода, ни разу не замёрзнув.
##
## Лето — это не поблажка. Осень приходит через три месяца и остаётся тяжёлой,
## зима тяжелее вдвое. Просто вступление перестаёт быть игрой про аптеку.
const DEFAULT_START_MONTH := 6
const DEFAULT_START_DAY := 1
const DEFAULT_START_MINUTE_OF_DAY := 8 * 60
const DEFAULT_MONTH_LENGTHS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const DEFAULT_MINUTES_PER_DAY := 24 * 60

const DEFAULT_RNG_SEED := 1_980_180_001


static func default_characteristics() -> Dictionary:
	return DEFAULT_CHARACTERISTICS.duplicate(true)


static func default_meters() -> Dictionary:
	return DEFAULT_METERS.duplicate(true)


static func default_stored_polarities() -> Dictionary:
	var result: Dictionary = {}
	for key in STORED_POLARITY_KEYS:
		result[key] = 0
	return result


static func default_computed_profiles() -> Dictionary:
	var result: Dictionary = {}
	for key in COMPUTED_PROFILE_KEYS:
		result[key] = {
			"value": 0,
			"formed": false,
			"evidence": 0,
		}
	return result


static func default_skills() -> Dictionary:
	var result: Dictionary = {}
	for key in SKILL_KEYS:
		result[key] = 0
	return result


static func default_calendar_config() -> Dictionary:
	return {
		"month_lengths": DEFAULT_MONTH_LENGTHS.duplicate(),
		"minutes_per_day": DEFAULT_MINUTES_PER_DAY,
		"leap_years_enabled": true,
		"leap_month": 2,
		"leap_every": 4,
		"leap_except_every": 100,
		"leap_include_every": 400,
	}


static func default_start_stamp() -> Dictionary:
	return {
		"year": DEFAULT_START_YEAR,
		"month": DEFAULT_START_MONTH,
		"day": DEFAULT_START_DAY,
		"minute_of_day": DEFAULT_START_MINUTE_OF_DAY,
		"elapsed_minutes": 0,
	}


static func is_known_characteristic(key: String) -> bool:
	return key in CHARACTERISTIC_KEYS


static func is_known_meter(key: String) -> bool:
	return key in METER_KEYS


static func is_stored_polarity(key: String) -> bool:
	return key in STORED_POLARITY_KEYS


static func is_computed_profile(key: String) -> bool:
	return key in COMPUTED_PROFILE_KEYS


static func is_known_skill(key: String) -> bool:
	return key in SKILL_KEYS


static func clamp_characteristic(value: int) -> int:
	return clampi(value, CHARACTERISTIC_MIN, CHARACTERISTIC_MAX)


static func clamp_meter(value: int) -> int:
	return clampi(value, METER_MIN, METER_MAX)


static func clamp_polarity(value: int) -> int:
	return clampi(value, POLARITY_MIN, POLARITY_MAX)


static func clamp_skill_rank(value: int) -> int:
	return clampi(value, SKILL_MIN_RANK, SKILL_MAX_RANK)


static func characteristics_use_budget(values: Dictionary) -> bool:
	if values.size() != CHARACTERISTIC_KEYS.size():
		return false
	var total := 0
	for key in CHARACTERISTIC_KEYS:
		if not values.has(key) or typeof(values[key]) != TYPE_INT:
			return false
		var value: int = values[key]
		if value < CHARACTERISTIC_MIN or value > CHARACTERISTIC_MAX:
			return false
		total += value
	return total == CHARACTERISTIC_BUDGET
