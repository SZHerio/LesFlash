class_name HeroScreen
extends Control

## Everything the run knows about this person, in one place.
##
## The screen presents a model and emits intents; it reads no state of its own.
## Sections the hero has not filled yet are absent rather than shown empty — an
## unlearned skill list would announce that skills exist and how many there are.

signal settings_requested

const PolarityRowScene := preload("res://ui/components/polarity_row.tscn")

@onready var _header: GameHeader = %GameHeader
@onready var _age_value: Label = %AgeValue
@onready var _psyche_step: Label = %PsycheStep
@onready var _characteristics: HBoxContainer = %Characteristics
@onready var _polarities: VBoxContainer = %Polarities
@onready var _skills_title: Label = %SkillsTitle
@onready var _skills: VBoxContainer = %Skills
@onready var _knowledge_title: Label = %KnowledgeTitle
@onready var _knowledge: Label = %Knowledge

var _reduced_motion := false


func _ready() -> void:
	_header.settings_requested.connect(func() -> void: settings_requested.emit())


func present(model: Dictionary) -> void:
	set_reduced_motion(bool(model.get("reduced_motion", false)))
	_header.present(Dictionary(model.get("header", {})))
	_age_value.text = String(model.get("age_text", ""))
	_psyche_step.text = String(Dictionary(model.get("psyche", {})).get("step", ""))
	_present_characteristics(Array(model.get("characteristics", [])))
	_present_polarities(
		Array(model.get("polarities", [])) + Array(model.get("profiles", []))
	)
	_present_skills(Array(model.get("skills", [])))
	_present_knowledge(Array(model.get("knowledge", [])))


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func _present_characteristics(entries: Array) -> void:
	for child in _characteristics.get_children():
		child.queue_free()
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override(&"separation", 4)
		var value := Label.new()
		value.text = str(int(entry.get("value", 0)))
		value.theme_type_variation = &"ScreenTitle"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var title := Label.new()
		title.text = String(entry.get("title", ""))
		title.theme_type_variation = &"ActionMetaLabel"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		column.add_child(title)
		_characteristics.add_child(column)


func _present_polarities(entries: Array) -> void:
	for child in _polarities.get_children():
		child.queue_free()
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var row := PolarityRowScene.instantiate() as PolarityRow
		_polarities.add_child(row)
		row.present(Dictionary(raw_entry))
	var reading_column := 0.0
	for child in _polarities.get_children():
		reading_column = maxf(reading_column, (child as PolarityRow).reading_width())
	for child in _polarities.get_children():
		(child as PolarityRow).set_reading_width(reading_column)


## Nothing learned yet means no section at all, not an empty one.
func _present_skills(entries: Array) -> void:
	for child in _skills.get_children():
		child.queue_free()
	var has_any := not entries.is_empty()
	_skills_title.visible = has_any
	_skills.visible = has_any
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var title := Label.new()
		title.text = String(entry.get("title", ""))
		title.theme_type_variation = &"BodyLabel"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rank := Label.new()
		rank.text = String(entry.get("rank_title", ""))
		rank.theme_type_variation = &"ActionMetaLabel"
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(title)
		row.add_child(rank)
		_skills.add_child(row)


func _present_knowledge(tags: Array) -> void:
	var has_any := not tags.is_empty()
	_knowledge_title.visible = has_any
	_knowledge.visible = has_any
	if has_any:
		_knowledge.text = ", ".join(PackedStringArray(tags))
