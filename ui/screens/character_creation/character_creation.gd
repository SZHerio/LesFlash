class_name CharacterCreationScreen
extends Control

signal back_requested
signal character_confirmed(characteristics: Dictionary)

const CHARACTERISTIC_ORDER := ["strength", "charisma", "intelligence", "luck"]
const CHARACTERISTIC_COPY := {
	"strength": {
		"title": "Сила",
		"description": "Тяжёлая работа, сопротивление усталости и прямые физические действия.",
	},
	"charisma": {
		"title": "Харизма",
		"description": "Доверие, торг, общение и возможность договориться без конфликта.",
	},
	"intelligence": {
		"title": "Интеллект",
		"description": "Обучение, анализ, осторожные решения и понимание сложных правил.",
	},
	"luck": {
		"title": "Удача",
		"description": "Тяжесть стартовой точки и частота неблагоприятных случайностей.",
	},
}

@onready var _points_label: Label = %PointsLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _info_sheet: InfoSheet = %InfoSheet
@onready var _steppers := {
	"strength": %StrengthStepper,
	"charisma": %CharismaStepper,
	"intelligence": %IntelligenceStepper,
	"luck": %LuckStepper,
}

var _values := {"strength": 1, "charisma": 1, "intelligence": 1, "luck": 1}
var _budget := 18
var _minimum := 1
var _maximum := 10
var _reduced_motion := false


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: back_requested.emit())
	_confirm_button.pressed.connect(_confirm)
	for stepper in _steppers.values():
		stepper.delta_requested.connect(_on_delta_requested)
		stepper.description_requested.connect(_show_description)
	_refresh()


## Back closes the explanation first, so reading about a characteristic can
## never drop the player out of character creation.
func handle_back() -> bool:
	if _info_sheet != null and _info_sheet.is_open():
		_info_sheet.close()
		return true
	return false


func has_open_sheet() -> bool:
	return _info_sheet != null and _info_sheet.is_open()


func _show_description(characteristic_id: String) -> void:
	var copy: Dictionary = CHARACTERISTIC_COPY.get(characteristic_id, {})
	if copy.is_empty():
		return
	_info_sheet.present(
		String(copy["title"]),
		String(copy["description"]),
		_reduced_motion
	)


func present(model: Dictionary) -> void:
	_budget = int(model.get("budget", 18))
	_minimum = int(model.get("minimum", 1))
	_maximum = int(model.get("maximum", 10))
	var incoming: Variant = model.get("values", {})
	if incoming is Dictionary:
		for characteristic_id in CHARACTERISTIC_ORDER:
			_values[characteristic_id] = clampi(
				int(incoming.get(characteristic_id, _minimum)),
				_minimum,
				_maximum
			)
	_refresh()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	for stepper in _steppers.values():
		stepper.set_reduced_motion(enabled)
	if _info_sheet != null:
		_info_sheet.set_reduced_motion(enabled)


func _on_delta_requested(characteristic_id: String, delta: int) -> void:
	if not _values.has(characteristic_id):
		return
	var next_value := int(_values[characteristic_id]) + delta
	if next_value < _minimum or next_value > _maximum:
		return
	if delta > 0 and _remaining_points() <= 0:
		return
	_values[characteristic_id] = next_value
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var remaining := _remaining_points()
	_points_label.text = "%d" % remaining
	_points_label.modulate = Color("d8b36a") if remaining == 0 else Color.WHITE
	_confirm_button.disabled = remaining != 0
	# The count is already on screen above; repeating it here says nothing new.
	_confirm_button.text = (
		"Начать жизнь" if remaining == 0 else "Есть свободные очки"
	)
	for characteristic_id in CHARACTERISTIC_ORDER:
		var copy: Dictionary = CHARACTERISTIC_COPY[characteristic_id]
		_steppers[characteristic_id].present({
			"id": characteristic_id,
			"title": copy["title"],
			"value": int(_values[characteristic_id]),
			"can_decrease": int(_values[characteristic_id]) > _minimum,
			"can_increase": int(_values[characteristic_id]) < _maximum and remaining > 0,
		})


func _remaining_points() -> int:
	var spent := 0
	for value in _values.values():
		spent += int(value)
	return maxi(_budget - spent, 0)


func _confirm() -> void:
	if _remaining_points() != 0:
		return
	character_confirmed.emit(_values.duplicate(true))
