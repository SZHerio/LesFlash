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
	_test_unformed_profile_says_so()
	_test_psyche_word_replaces_the_number()
	_test_age_agrees_with_its_number()
	_test_header_follows_the_shell()
	if _failures.is_empty():
		print("HERO VIEW MODEL TEST PASSED: 7/7")
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


## −35 has to read as «Мощь 35». A minus sign in front of a Russian noun is not
## something a player can interpret.
func _test_polarity_readings_name_the_pole() -> void:
	var state := _state()
	state.set_polarity("physical_specialization", -35)
	state.set_polarity("execution_style", 40)
	var axes: Array = _built(state).get("polarities", [])
	var readings: Dictionary = {}
	for raw_axis: Variant in axes:
		var axis: Dictionary = raw_axis
		readings[String(axis["id"])] = String(axis["reading"])
	_require(
		String(readings.get("physical_specialization", "")) == "Мощь 35",
		"left pole reads as «%s»" % String(readings.get("physical_specialization", ""))
	)
	_require(
		String(readings.get("execution_style", "")) == "Контроль 40",
		"right pole reads as «%s»" % String(readings.get("execution_style", ""))
	)
	_require(
		String(readings.get("influence_style", "")) == "Равноправный торг",
		"the centre reads as «%s» instead of a state of its own"
			% String(readings.get("influence_style", ""))
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
