class_name SearchApproachRow
extends PanelContainer

signal confirmed(approach_id: String)

@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _costs: Label = %Costs
@onready var _blocked: Label = %Blocked
@onready var _confirm: Button = %Confirm

var _approach_id := ""


func _ready() -> void:
	_confirm.pressed.connect(_on_confirmed)


func present(model: Dictionary) -> void:
	_approach_id = String(model.get("id", ""))
	_title.text = String(model.get("title", "Способ действия"))
	var description := String(model.get("description", "")).strip_edges()
	_description.text = description
	_description.visible = not description.is_empty()
	var cost_text := String(model.get("cost_text", "")).strip_edges()
	_costs.text = cost_text if not cost_text.is_empty() else "Без затрат"
	var reasons := _string_array(model.get("blocked_reasons", []))
	_blocked.text = "\n".join(PackedStringArray(reasons))
	_blocked.visible = not reasons.is_empty()
	_confirm.disabled = not bool(model.get("enabled", true)) or _approach_id.is_empty()
	_confirm.text = "Недоступно" if _confirm.disabled else "Выбрать"


func action_button() -> Button:
	return _confirm


func _on_confirmed() -> void:
	if not _confirm.disabled:
		confirmed.emit(_approach_id)


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is String and not String(value).strip_edges().is_empty():
		result.append(String(value))
	elif value is Array:
		for raw_entry: Variant in value:
			var entry := String(raw_entry).strip_edges()
			if not entry.is_empty():
				result.append("• %s" % entry)
	return result
