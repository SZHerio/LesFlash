class_name GameHeader
extends PanelContainer

signal settings_requested

@onready var _district_label: Label = %DistrictLabel
@onready var _location_label: Label = %LocationLabel
@onready var _date_label: Label = %DateLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	_settings_button.pressed.connect(func() -> void: settings_requested.emit())


func present(model: Dictionary) -> void:
	_district_label.text = String(model.get("district_title", "НЕИЗВЕСТНЫЙ РАЙОН")).to_upper()
	_location_label.text = String(model.get("location_title", "Неизвестное место"))

	var date_text := String(model.get("date_text", ""))
	var time_text := String(model.get("time_text", ""))
	var date_parts: Array[String] = []
	if not date_text.is_empty():
		date_parts.append(date_text)
	if not time_text.is_empty():
		date_parts.append(time_text)
	_date_label.text = " · ".join(PackedStringArray(date_parts))
	_date_label.visible = not _date_label.text.is_empty()

	if model.has("money_text"):
		_money_label.text = String(model.get("money_text", ""))
	else:
		_money_label.text = "%d ₽" % int(model.get("money", 0))
	_settings_button.visible = bool(model.get("show_settings", true))
