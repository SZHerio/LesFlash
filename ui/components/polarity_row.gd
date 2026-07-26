class_name PolarityRow
extends VBoxContainer

## One axis of the hero's style: what the axis is about, where he stands on it
## right now, and how far that is from the middle.

@onready var _title: Label = %Title
@onready var _reading: Label = %Reading
@onready var _track: PolarityTrack = %Track


func reading_width() -> float:
	return _reading.get_minimum_size().x


## All rows share one reading column so that every track is the same width and
## the centre ticks form a straight line. Ragged centres would make a lean look
## like an artefact of the longest label.
func set_reading_width(width: float) -> void:
	_reading.custom_minimum_size.x = width


func present(model: Dictionary) -> void:
	_title.text = String(model.get("title", ""))
	_reading.text = String(model.get("reading", ""))
	var formed := bool(model.get("formed", true))
	_reading.modulate = Color.WHITE if formed else Color(1.0, 1.0, 1.0, 0.55)
	_track.present(int(model.get("value", 0)), formed)
