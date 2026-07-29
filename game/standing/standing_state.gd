class_name StandingState
extends RefCounted

## Что о герое знают: надёжен он или опасен.
##
## Две репутации, а не одна шкала морали. Копятся раздельно и **несовместимы**:
## один поступок не может растить обе, и рост одной сбивает другую. Высокая
## надёжность открывает то, что закрывает высокая опасность, и наоборот.
##
## Отличие от бумаги, которое и делает это отыгрышем: бумагу можно получить
## заново, **славу — нельзя**. Поэтому здесь ничего не убывает само по себе.
##
## Семя уже было посеяно: в зонах поиска давно написаны «попросить разрешения»
## против «пройти незамеченным», «разговориться со сторожем» против «отжать
## петлю». Эта ось просто ничего не копила.

const JsonValidator := preload("res://core/save/json_value_validator.gd")

const SCHEMA_VERSION := 1

## Поступок, растящий одну сторону, сбивает другую вот на столько от прироста.
## Не до нуля: человек, которого боятся, не перестаёт быть надёжным работником —
## но и обоими сразу его не считают.
const CROSS_DAMPING_PERCENT := 60

## Сколько нужно, чтобы это стало тем, с чего о человеке начинают разговор.
const NOTICED := 3
const KNOWN := 8

var reliable: int = 0
var feared: int = 0

## Кто уже слышал. Слух не мгновенный: сделанное на паперти доходит до приёмки,
## когда там окажется кто-то, кто знает.
var heard_by: Dictionary = {}


static func fresh() -> StandingState:
	return StandingState.new()


## Записывает поступок. `weight` положителен всегда; сторону выбирает `kind`.
func record(kind: String, weight: int = 1) -> bool:
	if weight <= 0:
		return false
	match kind:
		"reliable":
			reliable += weight
			feared = maxi(feared - _cross_damage(weight), 0)
		"feared":
			feared += weight
			reliable = maxi(reliable - _cross_damage(weight), 0)
		_:
			return false
	# Новое ещё никто не знает: слуху нужно время и люди.
	heard_by.clear()
	return true


## Насколько поступок сбивает противоположную сторону. Не меньше единицы: при
## целочисленном делении одиночный поступок сбивал ноль, и обе репутации росли
## одновременно — ровно то, чего эта пара осей не должна допускать.
static func _cross_damage(weight: int) -> int:
	return maxi(weight * CROSS_DAMPING_PERCENT / 100, 1)


## Кто-то узнал — потому что видел сам или потому что рассказали.
func spread_to(npc_id: String) -> bool:
	if npc_id.strip_edges().is_empty() or heard_by.has(npc_id):
		return false
	heard_by[npc_id] = true
	return true


func has_heard(npc_id: String) -> bool:
	return heard_by.has(npc_id)


## Чем он считается — тем, что о нём говорят громче. Ничем, пока не о чем.
func label() -> String:
	if reliable < NOTICED and feared < NOTICED:
		return ""
	return "reliable" if reliable >= feared else "feared"


func is_known_for(kind: String) -> bool:
	match kind:
		"reliable":
			return reliable >= KNOWN
		"feared":
			return feared >= KNOWN
	return false


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"reliable": reliable,
		"feared": feared,
		"heard_by": heard_by.duplicate(true),
	}


static func from_dict(data: Variant) -> StandingState:
	if not data is Dictionary:
		return null
	var source: Dictionary = data
	if int(source.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := StandingState.new()
	for field: String in ["reliable", "feared"]:
		var value: Variant = SerializedValue.parse_integral(source.get(field, 0))
		if value == null or int(value) < 0:
			return null
		state.set(field, int(value))
	if not source.get("heard_by", {}) is Dictionary:
		return null
	for raw_id: Variant in Dictionary(source["heard_by"]):
		if typeof(raw_id) != TYPE_STRING or String(raw_id).strip_edges().is_empty():
			return null
		state.heard_by[String(raw_id)] = true
	return state if bool(state.validate().get("ok", false)) else null


func clone() -> StandingState:
	var copy := StandingState.new()
	copy.reliable = reliable
	copy.feared = feared
	copy.heard_by = heard_by.duplicate(true)
	return copy


func replace_from(other: StandingState) -> bool:
	if other == null or not bool(other.validate().get("ok", false)):
		return false
	reliable = other.reliable
	feared = other.feared
	heard_by = other.heard_by.duplicate(true)
	return true


func validate() -> Dictionary:
	var errors: Array[String] = []
	for raw: Variant in Array(JsonValidator.validate(to_dict(), "standing_state").get("errors", [])):
		errors.append(String(raw))
	if reliable < 0 or feared < 0:
		errors.append("standing_state: репутация не может быть отрицательной")
	for raw_id: Variant in heard_by:
		if typeof(heard_by[raw_id]) != TYPE_BOOL or not bool(heard_by[raw_id]):
			errors.append("standing_state.heard_by содержит неверную запись")
	return {"ok": errors.is_empty(), "errors": errors}
