class_name MoneyAmount
extends HBoxContainer

## One amount in the fictional currency. The SVG carries the compact mark;
## when it is unavailable, the visible Russian fallback is always "ард.".

const CurrencyTextScript := preload("res://app/presentation/currency_text.gd")
const CURRENCY_ICON := &"currency_arden_compact"
const ICON_SIZE := 16

@onready var _currency_icon: SemanticIcon = %CurrencyIcon
@onready var _amount_label: Label = %AmountLabel

var _model: Dictionary = {}
var _amount_text := "0"


func _ready() -> void:
	_apply_model()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_currency()


func present(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_node_ready():
		_apply_model()


func _apply_model() -> void:
	if _model.is_empty():
		_currency_icon.clear()
		_amount_label.text = ""
		accessibility_name = ""
		set_meta(&"accessible_text", "")
		visible = false
		return
	_amount_text = String(_model.get("amount_text", "")).strip_edges()
	if _amount_text.is_empty():
		_amount_text = str(int(_model.get("amount", 0)))
	var accessible_text := String(_model.get("accessible_text", "")).strip_edges()
	if accessible_text.is_empty():
		accessible_text = CurrencyTextScript.full(int(_model.get("amount", 0)))
	accessibility_name = accessible_text
	set_meta(&"accessible_text", accessible_text)
	visible = true
	_apply_currency()


func _apply_currency() -> void:
	var has_mark := _currency_icon.present(
		CURRENCY_ICON,
		ICON_SIZE,
		_amount_label.get_theme_color(&"font_color")
	)
	_amount_label.text = (
		_amount_text
		if has_mark
		else CurrencyTextScript.compact(int(_model.get("amount", 0)))
	)
