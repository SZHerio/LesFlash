class_name BusinessState
extends RefCounted

## A place the hero owns, and what it has been doing while he was not there.
##
## The rule this exists to satisfy: a business that only earns while the player
## stands in it is not a business, it is another shift. So the takings and the
## costs accrue against the clock, whether or not anyone comes by, and the hero
## settles up when he does.
##
## That cuts both ways, which is the point. Rent and wages accrue too. A man who
## opens a bench, hires a hand and then disappears for a fortnight comes back to
## a debt, and the debt is his.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1

## Empty until the hero buys something. One at a time: a second bench is a
## different game, and this one has to be worth playing first.
var business_id: String = ""

## Materials on hand, in whole units. Work stops when they run out — the bench
## does not invent brass out of nothing, and an idle bench still costs rent.
var stock: int = 0

## People working there besides the hero. Each one raises what the place can do
## in a day and is paid whether or not there was anything to do.
var hands: int = 0

## Elapsed minute of the last settlement. Everything between then and now is
## what the hero has coming, or owes.
var settled_at_minute: int = 0

## Days the place stood idle for want of materials since the last settlement.
## Kept so the hero can be told why the takings were thin, in his own words.
var idle_days: int = 0


static func fresh() -> BusinessState:
	return BusinessState.new()


func owns_anything() -> bool:
	return not business_id.strip_edges().is_empty()


## Whole days between the last settlement and now. Part-days do not pay: the
## bench is reckoned by the day, the way a real one would be.
func days_owed(elapsed_minutes: int, minutes_per_day: int = GameRules.DEFAULT_MINUTES_PER_DAY) -> int:
	if not owns_anything():
		return 0
	var per_day := maxi(minutes_per_day, 1)
	@warning_ignore("integer_division")
	var days := (maxi(elapsed_minutes - settled_at_minute, 0)) / per_day
	return days


func open(next_business_id: String, elapsed_minutes: int) -> bool:
	if owns_anything() or next_business_id.strip_edges().is_empty():
		return false
	business_id = next_business_id.strip_edges()
	stock = 0
	hands = 0
	idle_days = 0
	settled_at_minute = maxi(elapsed_minutes, 0)
	return true


func close() -> void:
	business_id = ""
	stock = 0
	hands = 0
	idle_days = 0
	settled_at_minute = 0


func add_stock(units: int) -> bool:
	if not owns_anything() or units <= 0:
		return false
	stock += units
	return true


func consume_stock(units: int) -> int:
	var taken := mini(maxi(units, 0), stock)
	stock -= taken
	return taken


func set_hands(count: int, maximum: int) -> bool:
	if not owns_anything():
		return false
	if count < 0 or count > maxi(maximum, 0):
		return false
	hands = count
	return true


func mark_settled(elapsed_minutes: int, days: int, idle: int, minutes_per_day: int = GameRules.DEFAULT_MINUTES_PER_DAY) -> void:
	# The remainder of a part-day is carried, not thrown away, or a hero who
	# settles every evening would never be paid at all.
	settled_at_minute += maxi(days, 0) * maxi(minutes_per_day, 1)
	settled_at_minute = mini(settled_at_minute, maxi(elapsed_minutes, 0))
	idle_days = maxi(idle, 0)


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"business_id": business_id,
		"stock": stock,
		"hands": hands,
		"settled_at_minute": settled_at_minute,
		"idle_days": idle_days,
	}


static func from_dict(data: Variant) -> BusinessState:
	if not data is Dictionary:
		return null
	var source: Dictionary = data
	if int(source.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := BusinessState.new()
	if typeof(source.get("business_id", "")) != TYPE_STRING:
		return null
	state.business_id = String(source.get("business_id", ""))
	for field: String in ["stock", "hands", "settled_at_minute", "idle_days"]:
		var value: Variant = SerializedValue.parse_integral(source.get(field, 0))
		if value == null or int(value) < 0:
			return null
		state.set(field, int(value))
	var validation := state.validate()
	return state if bool(validation.get("ok", false)) else null


func clone() -> BusinessState:
	var copy := BusinessState.new()
	copy.business_id = business_id
	copy.stock = stock
	copy.hands = hands
	copy.settled_at_minute = settled_at_minute
	copy.idle_days = idle_days
	return copy


func replace_from(other: BusinessState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	business_id = other.business_id
	stock = other.stock
	hands = other.hands
	settled_at_minute = other.settled_at_minute
	idle_days = other.idle_days
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(JsonValidator.validate(to_dict(), "business_state").get("errors", [])):
		errors.append(String(raw))
	if stock < 0:
		errors.append("business_state.stock не может быть отрицательным")
	if hands < 0:
		errors.append("business_state.hands не может быть отрицательным")
	if settled_at_minute < 0:
		errors.append("business_state.settled_at_minute не может быть отрицательным")
	if not owns_anything() and (stock > 0 or hands > 0):
		errors.append("business_state описывает запас и людей без самого дела")
	return {"ok": errors.is_empty(), "errors": errors}
