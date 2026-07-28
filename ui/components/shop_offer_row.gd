class_name ShopOfferRow
extends PanelContainer

signal purchase_requested(offer_id: String, quantity: int)

const Motion := preload("res://ui/theme/motion.gd")
const Palette := preload("res://ui/theme/palette.gd")

@onready var _item_icon: SemanticIcon = %ItemIcon
@onready var _title: Label = %TitleLabel
@onready var _stock: Label = %StockLabel
@onready var _condition: Label = %ConditionLabel
@onready var _quality: Label = %QualityLabel
@onready var _unit_price: MoneyAmount = %UnitPrice
@onready var _total_price: MoneyAmount = %TotalPrice
@onready var _decrease: Button = %DecreaseButton
@onready var _increase: Button = %IncreaseButton
@onready var _quantity_value: Label = %QuantityValue
@onready var _buy: Button = %BuyButton
@onready var _reason: Label = %ReasonLabel

var _model: Dictionary = {}
var _quantity := 1
var _available := 0
var _unit_price_value := 0
var _wallet := 0
var _mode := "buy"
var _store_open := false
var _reduced_motion := false
var _reveal_tween: Tween


func _ready() -> void:
	_decrease.pressed.connect(func() -> void: _change_quantity(-1))
	_increase.pressed.connect(func() -> void: _change_quantity(1))
	_buy.pressed.connect(_request_purchase)
	_apply_model()


func present(model: Dictionary, store_open: bool, wallet: int) -> void:
	_model = model.duplicate(true)
	_store_open = store_open
	_wallet = maxi(wallet, 0)
	_quantity = 1
	if is_node_ready():
		_apply_model()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		Motion.stop(_reveal_tween)
		modulate = Color.WHITE


func offer_id() -> String:
	return String(_model.get("offer_id", _model.get("stack_id", "")))


func mode() -> String:
	return _mode


func selected_quantity() -> int:
	return _quantity


func _apply_model() -> void:
	_mode = "sell" if String(_model.get("mode", "buy")) == "sell" else "buy"
	_available = maxi(int(_model.get("quantity", 0)), 0)
	_unit_price_value = maxi(int(_model.get("unit_price", _model.get("unit_payout", 0))), 0)
	_quantity = clampi(_quantity, 1, maxi(_available, 1))
	_item_icon.present(StringName(_model.get("icon_id", &"meta_item")), 32, Palette.GOLD)
	_title.text = String(_model.get("title", "Товар")).strip_edges()
	if _title.text.is_empty():
		_title.text = "Товар"
	_stock.text = "%d %s" % [_available, _stock_word(_available)]
	_condition.text = _metric_text("Состояние", _model.get("condition", 0))
	_quality.text = _metric_text("Качество", _model.get("quality", 0))
	_unit_price.present({"amount": _unit_price_value})
	_refresh_controls()
	modulate = Color(1, 1, 1, 0)
	_reveal_tween = Motion.play(_reveal_tween, self, [{
		"target": self,
		"property": "modulate",
		"to": Color.WHITE,
		"duration": Motion.REVEAL,
	}], _reduced_motion)


func _change_quantity(delta: int) -> void:
	_quantity = clampi(_quantity + delta, 1, maxi(_available, 1))
	_refresh_controls()


func _refresh_controls() -> void:
	var total := _unit_price_value * _quantity
	_quantity_value.text = "%d из %d" % [_quantity, _available]
	_total_price.present({"amount": total})
	_decrease.disabled = _quantity <= 1 or _available <= 0 or not _store_open
	_increase.disabled = _quantity >= _available or _available <= 0 or not _store_open
	var selling := _mode == "sell"
	var reason := ""
	if not _store_open:
		reason = "Торговая точка сейчас закрыта"
	elif _available <= 0:
		reason = "Товар закончился" if not selling else "У вас этого больше нет"
	elif not selling and total > _wallet:
		reason = "Не хватает %d %s" % [total - _wallet, _arden_word(total - _wallet)]
	_buy.disabled = not reason.is_empty()
	_buy.text = "Продать" if selling else "Купить"
	_reason.text = reason
	_reason.visible = not reason.is_empty()
	_buy.accessibility_name = (
		"%s %s, %d штука, %d %s" % [
			"Продать" if selling else "Купить",
			_title.text,
			_quantity,
			total,
			_arden_word(total),
		]
	)


func _request_purchase() -> void:
	if _buy.disabled or offer_id().is_empty():
		return
	purchase_requested.emit(offer_id(), _quantity)


static func _metric_text(prefix: String, value: Variant) -> String:
	if value is int or value is float:
		return "%s: %d%%" % [prefix, clampi(int(value), 0, 100)]
	var text := String(value).strip_edges()
	return "%s: %s" % [prefix, text if not text.is_empty() else "неизвестно"]


static func _stock_word(value: int) -> String:
	var last_two := value % 100
	if last_two >= 11 and last_two <= 14:
		return "штук"
	match value % 10:
		1:
			return "штука"
		2, 3, 4:
			return "штуки"
		_:
			return "штук"


static func _arden_word(value: int) -> String:
	var last_two := value % 100
	if last_two >= 11 and last_two <= 14:
		return "арденов"
	match value % 10:
		1:
			return "арден"
		2, 3, 4:
			return "ардена"
		_:
			return "арденов"
