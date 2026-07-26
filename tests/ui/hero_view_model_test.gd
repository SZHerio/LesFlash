extends SceneTree

## The hero screen is the one place that shows everything at once, so the model
## is checked against a real RunState rather than an invented dictionary.

const RunStateScript = preload("res://core/state/run_state.gd")
const HeroModels = preload("res://app/hero/hero_view_model.gd")
const PsycheScaleScript = preload("res://core/state/psyche_scale.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_raw_reads_only_earned_state()
	_test_unlearned_skills_are_absent()
	_test_polarity_readings_name_the_pole()
	_test_bands_cover_the_whole_range()
	_test_unformed_profile_says_so()
	_test_psyche_word_replaces_the_number()
	_test_age_agrees_with_its_number()
	_test_header_follows_the_shell()
	if _failures.is_empty():
		print("HERO VIEW MODEL TEST PASSED: 8/8")
		quit(0)
		return
	for failure in _failures:
		push_error("HERO VIEW MODEL: %s" % failure)
	quit(1)


func _state() -> RunState:
	return RunStateScript.new(
		{"strength": 6, "charisma": 3, "intelligence": 5, "luck": 4}, 4242
	)


func _built(state: RunState) -> Dictionary:
	return HeroModels.build(HeroModels.raw(state), _shell(), false, 1.0)


func _shell() -> Dictionary:
	return {
		"status": {
			"money": 240,
			"calendar": {"year": 2024, "month": 9, "day": 12, "minute_of_day": 615},
		},
	}


func _test_raw_reads_only_earned_state() -> void:
	var raw: Dictionary = HeroModels.raw(_state())
	_require(not raw.is_empty(), "raw model is empty for a valid run state")
	_require(int(raw.get("age_years", 0)) > 0, "raw model lost the age")
	_require(
		Dictionary(raw.get("characteristics", {})).get("strength", 0) == 6,
		"raw model lost an allocated characteristic"
	)
	_require(HeroModels.raw(null).is_empty(), "raw model invented data for a missing run state")


## Rule 3.4: a locked row still tells the player the mechanic exists.
func _test_unlearned_skills_are_absent() -> void:
	var state := _state()
	var fresh: Dictionary = _built(state)
	_require(
		Array(fresh.get("skills", [])).is_empty(),
		"a hero who has learned nothing was shown a skill list"
	)
	state.set_skill_rank("cooking", 2)
	var learned: Dictionary = _built(state)
	var skills: Array = learned.get("skills", [])
	_require(skills.size() == 1, "learning one skill produced %d rows" % skills.size())
	if skills.is_empty():
		return
	var row: Dictionary = skills[0]
	_require(String(row.get("id", "")) == "cooking", "skill row lost its id")
	_require(
		String(row.get("rank_title", "")) == "уверенное владение",
		"rank 2 reads as «%s»" % String(row.get("rank_title", ""))
	)


## An axis reads as a phrase picked by its value, never as a number: «35» does
## not tell the player whether 35 is a lot.
func _test_polarity_readings_name_the_pole() -> void:
	var state := _state()
	state.set_polarity("physical_specialization", -35)
	state.set_polarity("execution_style", 40)
	var readings: Dictionary = {}
	for raw_axis: Variant in Array(_built(state).get("polarities", [])):
		var axis: Dictionary = raw_axis
		readings[String(axis["id"])] = String(axis["reading"])
	_require(
		String(readings.get("physical_specialization", "")) == "Мощный",
		"−35 reads as «%s»" % String(readings.get("physical_specialization", ""))
	)
	_require(
		String(readings.get("execution_style", "")) == "Держит контроль",
		"+40 reads as «%s»" % String(readings.get("execution_style", ""))
	)
	_require(
		String(readings.get("influence_style", "")) == "По-разному",
		"the centre reads as «%s» instead of a state of its own"
			% String(readings.get("influence_style", ""))
	)
	for key: Variant in readings:
		var text := String(readings[key])
		for character: String in text:
			_require(
				not character.is_valid_int(),
				"«%s» still shows the player a raw number" % text
			)


## Every value in the domain range must land on a phrase, and a fresh hero — all
## axes at 0 — must not already be described as leaning either way.
func _test_bands_cover_the_whole_range() -> void:
	var tables := [HeroModels.POLARITIES, HeroModels.PROFILES]
	var expected: int = HeroModels.BAND_MAX.size() + 1
	for raw_table: Variant in tables:
		var table: Dictionary = raw_table
		for key: String in table:
			var bands: Array = Dictionary(table[key])["bands"]
			_require(
				bands.size() == expected,
				"%s carries %d phrases, expected %d" % [key, bands.size(), expected]
			)
			var seen: Dictionary = {}
			for phrase: Variant in bands:
				_require(
					not String(phrase).strip_edges().is_empty(),
					"%s has an empty phrase" % key
				)
				_require(not seen.has(phrase), "%s repeats «%s»" % [key, String(phrase)])
				seen[phrase] = true
	var used: Dictionary = {}
	for value: int in range(GameRules.POLARITY_MIN, GameRules.POLARITY_MAX + 1):
		var index := HeroModels.band_index(value)
		_require(
			index >= 0 and index < expected,
			"value %d falls outside every band" % value
		)
		used[index] = true
	_require(used.size() == expected, "%d bands of %d are unreachable" % [expected - used.size(), expected])
	var neutral := HeroModels.band_index(0)
	_require(
		neutral == HeroModels.band_index(-1) and neutral == HeroModels.band_index(1),
		"zero does not sit inside the neutral band"
	)


## An empty address book is not a perfectly balanced circle of friends.
func _test_unformed_profile_says_so() -> void:
	var profiles: Array = _built(_state()).get("profiles", [])
	_require(profiles.size() == 2, "expected two computed profiles, got %d" % profiles.size())
	for raw_profile: Variant in profiles:
		var profile: Dictionary = raw_profile
		_require(
			not bool(profile.get("formed", true)),
			"%s claimed to be formed on a fresh run" % String(profile.get("id", ""))
		)
		_require(
			String(profile.get("reading", "")) == "не сформирован",
			"unformed profile reads as «%s»" % String(profile.get("reading", ""))
		)
		_require(int(profile.get("value", 1)) == 0, "unformed profile leaked a position")


func _test_psyche_word_replaces_the_number() -> void:
	var state := _state()
	state.meters["morale"] = 30
	var psyche: Dictionary = _built(state).get("psyche", {})
	var word := String(psyche.get("step", ""))
	_require(word == "уныние", "morale 30 reads as «%s»" % word)
	_require(word == PsycheScaleScript.title_for(30), "the screen and the scale disagree")
	for key: Variant in psyche:
		_require(
			not str(psyche[key]).is_valid_int(),
			"the psyche section still exposes a raw number"
		)


func _test_age_agrees_with_its_number() -> void:
	var expected := {
		21: "21 год", 22: "22 года", 25: "25 лет",
		11: "11 лет", 14: "14 лет", 41: "41 год", 44: "44 года",
	}
	for years: int in expected:
		var text := String(HeroModels.build(
			{"age_years": years}, _shell(), false, 1.0
		).get("age_text", ""))
		_require(
			text == String(expected[years]),
			"age %d reads as «%s», expected «%s»" % [years, text, String(expected[years])]
		)


func _test_header_follows_the_shell() -> void:
	var header: Dictionary = _built(_state()).get("header", {})
	_require(int(header.get("money", 0)) == 240, "the hero header invented its own money")
	_require(
		not String(header.get("date_text", "")).is_empty(),
		"the hero header dropped the date the other screens show"
	)
	_require(
		String(header.get("location_title", "")) == "Герой",
		"the hero header does not name the screen"
	)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
