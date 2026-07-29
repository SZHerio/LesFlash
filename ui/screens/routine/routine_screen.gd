class_name RoutineScreen
extends Control

## The week, written down.
##
## Seven days, four stretches each, and one activity in a stretch or nothing.
## The screen presents a model and emits intents; it reads no state of its own
## and decides nothing about whether a plan is any good.
##
## The stretch the hero is living right now is marked, because a plan is only
## useful if you can see where in it you are.

signal settings_requested
## day_of_week, block_id — the player wants to fill or clear this stretch.
signal block_selected(day_of_week: int, block_id: String)
signal following_toggled(following: bool)
signal clear_requested
## The player picked what fills the stretch. An empty id clears it.
signal activity_chosen(day_of_week: int, block_id: String, activity_id: String)

@onready var _header: GameHeader = %GameHeader
@onready var _summary: Label = %Summary
@onready var _days: VBoxContainer = %Days
@onready var _follow_button: Button = %FollowButton
@onready var _clear_button: Button = %ClearButton

var _reduced_motion := false
var _following := false


func _ready() -> void:
	_header.settings_requested.connect(func() -> void: settings_requested.emit())
	_follow_button.pressed.connect(func() -> void: following_toggled.emit(not _following))
	_clear_button.pressed.connect(func() -> void: clear_requested.emit())


func present(model: Dictionary, reduced_motion: bool = false) -> void:
	_reduced_motion = reduced_motion
	if model.has("shell"):
		_header.present(Dictionary(model["shell"]))
	_following = bool(model.get("following", false))
	_summary.text = String(model.get("summary", ""))
	_follow_button.text = "Перестать следовать" if _following else "Следовать распорядку"
	# Nothing to abandon and nothing to erase: both buttons go rather than sit
	# greyed out with an explanation, which rule 3.4 forbids.
	var planned := int(model.get("planned_count", 0)) > 0
	_follow_button.visible = planned
	_clear_button.visible = planned
	_rebuild(Array(model.get("days", [])))


## Swaps the week for the list of what could fill one stretch of it. Choosing —
## or going back — returns the week. There is no separate screen because picking
## an activity is one step, and a step is not a place.
func present_options(day_of_week: int, block_id: String, block_title: String, options: Array) -> void:
	_summary.text = "%s, %s" % [WeekSchedule.day_title(day_of_week), block_title]
	_follow_button.visible = false
	_clear_button.visible = false
	for child: Node in _days.get_children():
		child.queue_free()

	var free_row := Button.new()
	free_row.theme_type_variation = &"ListRow"
	free_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	free_row.text = "оставить свободным"
	free_row.pressed.connect(func() -> void: activity_chosen.emit(day_of_week, block_id, ""))
	_days.add_child(free_row)

	for raw_option: Variant in options:
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var row := Button.new()
		row.theme_type_variation = &"ListRow"
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var label := String(option.get("title", ""))
		if bool(option.get("unattended", false)):
			label = "%s (само собой)" % label
		row.text = label
		row.tooltip_text = String(option.get("description", ""))
		var activity_id := String(option.get("id", ""))
		row.pressed.connect(func() -> void: activity_chosen.emit(day_of_week, block_id, activity_id))
		_days.add_child(row)

	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(func() -> void: block_selected.emit(0, ""))
	_days.add_child(back)


func _rebuild(days: Array) -> void:
	for child: Node in _days.get_children():
		child.queue_free()
	for raw_day: Variant in days:
		if not raw_day is Dictionary:
			continue
		_days.add_child(_day_section(Dictionary(raw_day)))


func _day_section(day: Dictionary) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = String(day.get("title", ""))
	title.theme_type_variation = &"HeadingSmall"
	if bool(day.get("today", false)):
		title.text = "%s — сегодня" % String(day.get("title", ""))
	section.add_child(title)

	for raw_block: Variant in Array(day.get("blocks", [])):
		if not raw_block is Dictionary:
			continue
		section.add_child(_block_row(int(day.get("day_of_week", 1)), Dictionary(raw_block)))
	return section


func _block_row(day_of_week: int, block: Dictionary) -> Control:
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_ALL
	var block_id := String(block.get("block_id", ""))
	var label := "%s — %s" % [String(block.get("title", "")), String(block.get("activity_title", ""))]
	# An activity the catalog has since dropped would otherwise show as a blank
	# row the player cannot explain.
	if bool(block.get("missing", false)):
		label = "%s — занятия больше нет" % String(block.get("title", ""))
	elif bool(block.get("occupied", false)):
		# Held by something that started earlier. Tapping it would only be refused.
		row.disabled = true
	elif bool(block.get("unattended", false)):
		label = "%s (само собой)" % label
	if bool(block.get("now", false)):
		label = "▸ %s" % label
	row.text = label
	row.pressed.connect(func() -> void: block_selected.emit(day_of_week, block_id))
	return row
