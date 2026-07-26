class_name PsycheScale
extends RefCounted

## Maps the psyche metric onto the seven words the player sees.
##
## The stored value stays 0..100 because event conditions compare against it;
## only the word leaves the domain. Depression is the bottom step of this scale
## and not a separate condition — one word, one meaning.
##
## Steps are deliberately unequal. The widest are равновесие and хандра, the
## ordinary run of life, and the edges are narrow because reaching depression or
## подъём has to mean something. Four steps lead down and two lead up: a game
## about surviving lives in the lower half.
##
## Hysteresis is not applied here. This is a pure reading of a value; the margin
## that stops a wavering number from flickering between two words belongs with
## the gameplay that moves it.

const STEPS := [
	{"id": "depression", "title": "депрессия", "from": 0, "to": 8, "filter": 1.0},
	{"id": "apathy", "title": "апатия", "from": 9, "to": 20, "filter": 0.78},
	{"id": "dejection", "title": "уныние", "from": 21, "to": 33, "filter": 0.52},
	{"id": "gloom", "title": "хандра", "from": 34, "to": 45, "filter": 0.24},
	{"id": "balance", "title": "равновесие", "from": 46, "to": 66, "filter": 0.0},
	{"id": "hope", "title": "надежда", "from": 67, "to": 85, "filter": 0.0},
	{"id": "lift", "title": "подъём", "from": 86, "to": 100, "filter": 0.0},
]


static func step_for(value: int) -> Dictionary:
	var clamped := clampi(value, 0, 100)
	for raw_step: Variant in STEPS:
		var step: Dictionary = raw_step
		if clamped >= int(step["from"]) and clamped <= int(step["to"]):
			return step.duplicate(true)
	return Dictionary(STEPS.back()).duplicate(true)


static func title_for(value: int) -> String:
	return String(step_for(value)["title"])


## Strength of the environment filter for a value. The filter only ever takes
## away: from равновесие upward it does not apply at all, because a world
## brighter than its own photograph would cheapen the fall.
static func filter_for(value: int) -> float:
	return float(step_for(value)["filter"])
