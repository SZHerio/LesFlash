class_name ResultScreen
extends Control

signal confirmed

@onready var _eyebrow_label: Label = %EyebrowLabel
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: Label = %BodyLabel
@onready var _facts_label: Label = %FactsLabel
@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	_confirm_button.pressed.connect(func() -> void: confirmed.emit())


func present(model: Dictionary) -> void:
	_eyebrow_label.text = String(model.get("eyebrow", "ИТОГ"))
	_title_label.text = String(model.get("title", "Готово"))
	_body_label.text = String(model.get("body", ""))
	var facts := PackedStringArray()
	for fact in Array(model.get("facts", [])):
		facts.append(String(fact))
	_facts_label.text = "\n".join(facts)
	_facts_label.visible = not facts.is_empty()
	_confirm_button.text = String(model.get("confirm_text", "Продолжить"))


func set_reduced_motion(_enabled: bool) -> void:
	pass
