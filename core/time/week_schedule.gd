class_name WeekSchedule
extends RefCounted

## The week as the game divides it: seven days, four stretches in each.
##
## A routine is written against these stretches rather than against the clock,
## because "утром на площадку" is a plan a person actually keeps and "в 7:12 на
## площадку" is not. The stretches are wide enough that arriving late still
## counts as keeping the plan, and narrow enough that the day has a shape.
##
## Day-of-week used to be derived inline wherever it was needed — the shop
## schedule had its own copy — which is how two parts of one game end up
## disagreeing about what day it is.

const DAYS_PER_WEEK := 7

## Written out because a plan is read, not computed. Index 0 is unused so the
## array is indexed by the same 1..7 the shop schedules already use.
const DAY_TITLES := [
	"",
	"понедельник",
	"вторник",
	"среда",
	"четверг",
	"пятница",
	"суббота",
	"воскресенье",
]

const MORNING := "morning"
const DAY := "day"
const EVENING := "evening"
const NIGHT := "night"

const BLOCK_IDS := [MORNING, DAY, EVENING, NIGHT]

## Where each stretch begins and ends, in minutes from midnight. Night wraps past
## midnight and is stored as the tail of the day it belongs to.
const BLOCKS := {
	MORNING: {"title": "утро", "starts_minute": 6 * 60, "ends_minute": 12 * 60},
	DAY: {"title": "день", "starts_minute": 12 * 60, "ends_minute": 18 * 60},
	EVENING: {"title": "вечер", "starts_minute": 18 * 60, "ends_minute": 23 * 60},
	NIGHT: {"title": "ночь", "starts_minute": 23 * 60, "ends_minute": 30 * 60},
}


## 1..7, where 1 is Monday. The run starts on a Monday, so elapsed days and the
## week line up without a lookup table.
static func day_of_week(elapsed_minutes: int, minutes_per_day: int = GameRules.DEFAULT_MINUTES_PER_DAY) -> int:
	var per_day := maxi(minutes_per_day, 1)
	@warning_ignore("integer_division")
	var elapsed_days := int(elapsed_minutes) / per_day
	return posmod(elapsed_days, DAYS_PER_WEEK) + 1


static func day_title(day_index: int) -> String:
	if day_index < 1 or day_index >= DAY_TITLES.size():
		return ""
	return String(DAY_TITLES[day_index])


## Which stretch a clock reading falls in. Everything before six in the morning
## belongs to the night that started the evening before.
static func block_of_minute(minute_of_day: int) -> String:
	var minute := posmod(int(minute_of_day), GameRules.DEFAULT_MINUTES_PER_DAY)
	if minute < int(BLOCKS[MORNING]["starts_minute"]):
		return NIGHT
	for block_id: String in BLOCK_IDS:
		var block: Dictionary = BLOCKS[block_id]
		if minute >= int(block["starts_minute"]) and minute < int(block["ends_minute"]):
			return block_id
	return NIGHT


static func block_title(block_id: String) -> String:
	return String(Dictionary(BLOCKS.get(block_id, {})).get("title", ""))


static func is_block(block_id: String) -> bool:
	return BLOCKS.has(block_id)


## Minutes from now until the given stretch begins. Zero when it is already
## running, so a caller can ask "how long until evening" without special cases.
static func minutes_until_block(minute_of_day: int, block_id: String) -> int:
	if not BLOCKS.has(block_id):
		return -1
	if block_of_minute(minute_of_day) == block_id:
		return 0
	var minute := posmod(int(minute_of_day), GameRules.DEFAULT_MINUTES_PER_DAY)
	var starts := int(Dictionary(BLOCKS[block_id])["starts_minute"])
	if starts >= GameRules.DEFAULT_MINUTES_PER_DAY:
		starts -= GameRules.DEFAULT_MINUTES_PER_DAY
	var delta := starts - minute
	return delta if delta >= 0 else delta + GameRules.DEFAULT_MINUTES_PER_DAY


## How many minutes of the current stretch are left. A stretch that has already
## ended reports zero rather than a negative remainder.
static func minutes_left_in_block(minute_of_day: int) -> int:
	var block_id := block_of_minute(minute_of_day)
	var minute := posmod(int(minute_of_day), GameRules.DEFAULT_MINUTES_PER_DAY)
	if block_id == NIGHT and minute < int(BLOCKS[MORNING]["starts_minute"]):
		return int(BLOCKS[MORNING]["starts_minute"]) - minute
	var ends := int(Dictionary(BLOCKS[block_id])["ends_minute"])
	if ends > GameRules.DEFAULT_MINUTES_PER_DAY:
		ends -= GameRules.DEFAULT_MINUTES_PER_DAY
		return ends + (GameRules.DEFAULT_MINUTES_PER_DAY - minute)
	return maxi(ends - minute, 0)


## The stretch after this one, wrapping into the next day.
static func next_block(block_id: String) -> String:
	var index := BLOCK_IDS.find(block_id)
	if index < 0:
		return MORNING
	return String(BLOCK_IDS[(index + 1) % BLOCK_IDS.size()])


## A stable key for one stretch of one day of the run, so a routine can tell
## "this morning" from "the morning a week ago" without storing timestamps.
static func slot_key(elapsed_minutes: int, minute_of_day: int) -> String:
	@warning_ignore("integer_division")
	var elapsed_days := int(elapsed_minutes) / GameRules.DEFAULT_MINUTES_PER_DAY
	return "%d:%s" % [elapsed_days, block_of_minute(minute_of_day)]
