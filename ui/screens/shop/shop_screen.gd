class_name ShopScreen
extends Control

signal back_requested
signal purchase_requested(
	store_id: String,
	offer_id: String,
	quantity: int,
	target_container_id: String,
	expected_revision: int
)
signal sale_requested(
	store_id: String,
	stack_id: String,
	quantity: int,
	expected_revision: int
)

const OfferRowScene := preload("res://ui/components/shop_offer_row.tscn")
const Palette := preload("res://ui/theme/palette.gd")

@onready var _back: Button = %BackButton
@onready var _title: Label = %TitleLabel
@onready var _money: MoneyAmount = %WalletMoney
@onready var _state_icon: SemanticIcon = %StateIcon
@onready var _state_title: Label = %StateTitle
@onready var _availability: Label = %AvailabilityLabel
@onready var _offer_list: VBoxContainer = %OfferList
@onready var _closed_state: MarginContainer = %ClosedState
@onready var _empty_state: MarginContainer = %EmptyState
@onready var _empty_icon: SemanticIcon = %EmptyIcon
@onready var _closed_icon: SemanticIcon = %ClosedIcon

var _model: Dictionary = {}
var _store_id := ""
var _target_container_id := "pockets"
var _revision := 0
var _reduced_motion := false


func _ready() -> void:
	_back.pressed.connect(func() -> void: back_requested.emit())
	_empty_icon.present(&"meta_item", 32, Palette.MUTED)
	_closed_icon.present(&"utility_locked", 32, Palette.MUTED)
	_apply_current_model()


func apply_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_node_ready():
		_apply_current_model()


func present(model: Dictionary) -> void:
	apply_model(model)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	for child in _offer_list.get_children():
		if child is ShopOfferRow:
			(child as ShopOfferRow).set_reduced_motion(enabled)


func _apply_current_model() -> void:
	_store_id = String(_model.get("store_id", _model.get("id", "")))
	_target_container_id = String(_model.get("target_container_id", "pockets"))
	_revision = int(_model.get("revision", 0))
	_reduced_motion = bool(_model.get("reduced_motion", false))
	_title.text = String(_model.get("title", "Торговая точка")).strip_edges()
	if _title.text.is_empty():
		_title.text = "Торговая точка"
	_money.present({"amount": int(_model.get("money", 0))})
	var open := bool(_model.get("open", false))
	var availability: Dictionary = Dictionary(_model.get("availability", {}))
	var reason := String(availability.get("reason", ""))
	if reason.strip_edges().is_empty():
		reason = "Открыто" if open else "Сейчас закрыто"
	_state_icon.present(&"action_trade" if open else &"utility_locked", 32, Palette.GOLD if open else Palette.MUTED)
	_state_title.text = "МОЖНО КУПИТЬ" if open else "ТОРГОВАЯ ТОЧКА ЗАКРЫТА"
	_availability.text = reason
	var rows := Array(_model.get("offers", [])).duplicate(true)
	# What the shop sells and what it buys are the same counter, so the sale
	# rows follow the shelf instead of hiding behind another screen.
	for raw_sale: Variant in Array(_model.get("sell_offers", [])):
		if raw_sale is Dictionary:
			var sale: Dictionary = Dictionary(raw_sale).duplicate(true)
			sale["mode"] = "sell"
			rows.append(sale)
	_rebuild_offers(rows, open, int(_model.get("money", 0)))


func _rebuild_offers(offers: Array, open: bool, wallet: int) -> void:
	for child in _offer_list.get_children():
		_offer_list.remove_child(child)
		child.queue_free()
	if open:
		for raw_offer in offers:
			if not raw_offer is Dictionary:
				continue
			var row := OfferRowScene.instantiate() as ShopOfferRow
			if row == null:
				continue
			_offer_list.add_child(row)
			row.set_reduced_motion(_reduced_motion)
			row.present(raw_offer, true, wallet)
			if String(Dictionary(raw_offer).get("mode", "buy")) == "sell":
				row.purchase_requested.connect(_on_sale)
			else:
				row.purchase_requested.connect(_on_purchase)
	_closed_state.visible = not open
	_empty_state.visible = open and _offer_list.get_child_count() == 0
	_offer_list.visible = open and _offer_list.get_child_count() > 0


func _on_purchase(offer_id: String, quantity: int) -> void:
	if _store_id.is_empty() or offer_id.is_empty():
		return
	purchase_requested.emit(
		_store_id,
		offer_id,
		quantity,
		_target_container_id,
		_revision
	)


func _on_sale(stack_id: String, quantity: int) -> void:
	if _store_id.is_empty() or stack_id.is_empty():
		return
	sale_requested.emit(_store_id, stack_id, quantity, _revision)
