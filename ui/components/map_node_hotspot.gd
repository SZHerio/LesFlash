class_name MapNodeHotspot
extends Button

signal destination_requested(destination_id: String)

var _destination_id := ""


func _ready() -> void:
	pressed.connect(_on_pressed)


func present(destination_id: String, place_title: String) -> void:
	_destination_id = destination_id
	accessibility_name = place_title.strip_edges()
	accessibility_description = "Место на карте. Нажмите, чтобы построить маршрут."
	tooltip_text = ""


func destination_id() -> String:
	return _destination_id


func set_selected(selected: bool) -> void:
	button_pressed = selected
	accessibility_description = (
		"Выбранное место. Нажмите, чтобы обновить маршрут."
		if selected
		else "Место на карте. Нажмите, чтобы построить маршрут."
	)


func _on_pressed() -> void:
	if not disabled and not _destination_id.is_empty():
		destination_requested.emit(_destination_id)
