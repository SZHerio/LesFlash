class_name NpcScreen
extends Control

signal interaction_requested(
	npc_id: String,
	interaction_id: String,
	expected_revision: int
)
signal back_requested
## Герой заговорил о чём-то. Отдельный сигнал, потому что это не взаимодействие
## с ревизией и подтверждением, а обычный разговор.
signal topic_requested(npc_id: String, topic_id: String)

const ActionRowScene := preload("res://ui/components/action_row.tscn")
const Motion := preload("res://ui/theme/motion.gd")
const Palette := preload("res://ui/theme/palette.gd")

@onready var _back: Button = %BackButton
@onready var _portrait_frame: PanelContainer = %PortraitFrame
@onready var _portrait: Control = %PortraitTexture
@onready var _portrait_fallback: CenterContainer = %PortraitFallback
@onready var _portrait_icon: SemanticIcon = %PortraitIcon
@onready var _name_label: Label = %NameLabel
@onready var _role_label: Label = %RoleLabel
@onready var _presence_label: Label = %PresenceLabel
@onready var _relationship_label: Label = %RelationshipLabel
@onready var _relationship_value: Label = %RelationshipValue
@onready var _outcome_panel: PanelContainer = %OutcomePanel
@onready var _outcome_label: Label = %OutcomeLabel
@onready var _reaction_label: Label = %ReactionLabel
@onready var _interactions: VBoxContainer = %InteractionList
@onready var _empty_state: MarginContainer = %EmptyState
@onready var _empty_icon: SemanticIcon = %EmptyIcon

var _model: Dictionary = {}
var _npc_id := ""
var _expected_revision := 0
var _awaiting_result := false
var _reduced_motion := false
var _portrait_tween: Tween
var _interaction_rows: Dictionary = {}


func _ready() -> void:
	_back.pressed.connect(_request_back)
	_portrait_icon.present(&"nav_hero", 32, Palette.MUTED)
	_empty_icon.present(&"action_talk", 32, Palette.MUTED)
	_apply_model()


func apply_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_node_ready():
		_apply_model()


func present(model: Dictionary) -> void:
	apply_model(model)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		Motion.stop(_portrait_tween)
		_portrait_frame.modulate = Color.WHITE
	for child in _interactions.get_children():
		if child is ActionRow:
			(child as ActionRow).set_reduced_motion(enabled)


func _apply_model() -> void:
	_awaiting_result = false
	_back.disabled = false
	_npc_id = String(_model.get("npc_id", ""))
	_expected_revision = int(_model.get("expected_revision", _model.get("revision", 0)))
	_reduced_motion = bool(_model.get("reduced_motion", false))
	_name_label.text = _visible_text(_model.get("name", "Неизвестный человек"), "Неизвестный человек")
	_role_label.text = _visible_text(_model.get("role", ""))
	_role_label.visible = not _role_label.text.is_empty()
	_presence_label.text = _visible_text(_model.get("presence_text", "Сейчас здесь"), "Сейчас здесь")
	_relationship_label.text = _visible_text(_model.get("relationship_label", "Отношение"), "Отношение")
	_relationship_value.text = _visible_text(_model.get("relationship_value", "Пока неясно"), "Пока неясно")
	_apply_portrait()
	_apply_outcome()
	_rebuild_interactions(Array(_model.get("interactions", [])))


func _apply_portrait() -> void:
	var portrait_path := String(_model.get("portrait_path", "")).strip_edges()
	var texture: Texture2D = null
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path, "Texture2D"):
		texture = ResourceLoader.load(
			portrait_path,
			"Texture2D",
			ResourceLoader.CACHE_MODE_REUSE
		) as Texture2D
	var focus_source: Dictionary = Dictionary(_model.get("portrait_focus", {}))
	var focus := Vector2(
		float(focus_source.get("x", 0.5)),
		float(focus_source.get("y", 0.35))
	)
	_portrait.call(
		"present",
		texture,
		focus,
		String(_model.get("portrait_crop_mode", "focus_cover"))
	)
	_portrait.visible = texture != null
	_portrait_fallback.visible = texture == null
	_portrait_frame.accessibility_name = "Портрет: %s" % _name_label.text
	_portrait_frame.set_meta(&"portrait_key", String(_model.get("portrait_key", "")))
	_portrait_frame.modulate = Color(1, 1, 1, 0)
	_portrait_tween = Motion.play(_portrait_tween, self, [{
		"target": _portrait_frame,
		"property": "modulate",
		"to": Color.WHITE,
		"duration": Motion.REVEAL,
	}], _reduced_motion)


func _apply_outcome() -> void:
	var outcome := String(_model.get("outcome", "")).strip_edges()
	var reactions := PackedStringArray()
	for raw_reaction: Variant in Array(_model.get("reactions", [])):
		var reaction := String(raw_reaction).strip_edges()
		if not reaction.is_empty():
			reactions.append(reaction)
	_outcome_label.text = outcome
	_outcome_label.visible = not outcome.is_empty()
	_reaction_label.text = "\n".join(reactions)
	_reaction_label.visible = not reactions.is_empty()
	_outcome_panel.visible = _outcome_label.visible or _reaction_label.visible


func _rebuild_interactions(models: Array) -> void:
	_interaction_rows.clear()
	for child in _interactions.get_children():
		_interactions.remove_child(child)
		child.queue_free()
	for raw_model: Variant in models:
		if not raw_model is Dictionary:
			continue
		var row := ActionRowScene.instantiate() as ActionRow
		if row == null:
			continue
		_interactions.add_child(row)
		row.set_reduced_motion(_reduced_motion)
		row.present(raw_model)
		row.action_requested.connect(_request_interaction)
		var interaction_id := String(Dictionary(raw_model).get("id", ""))
		if not interaction_id.is_empty():
			_interaction_rows[interaction_id] = row
	# Темы идут тем же списком, что и всё остальное: заговорить — такое же дело,
	# как отдать вещь или попросить о работе, и отдельного режима у него нет.
	for raw_topic: Variant in Array(_model.get("topics", [])):
		if not raw_topic is Dictionary:
			continue
		var topic: Dictionary = raw_topic
		var topic_row := ActionRowScene.instantiate() as ActionRow
		if topic_row == null:
			continue
		_interactions.add_child(topic_row)
		topic_row.set_reduced_motion(_reduced_motion)
		topic_row.present({
			"id": String(topic.get("id", "")),
			"title": String(topic.get("title", "")),
			"description": String(topic.get("prompt", "")),
			"available": true,
			"minutes": int(topic.get("minutes", 0)),
		})
		var topic_id := String(topic.get("id", ""))
		topic_row.action_requested.connect(
			func(_id: String) -> void: topic_requested.emit(_npc_id, topic_id)
		)
	_empty_state.visible = _interactions.get_child_count() == 0
	_interactions.visible = not _empty_state.visible


func _request_interaction(interaction_id: String) -> void:
	if _awaiting_result or _npc_id.is_empty() or interaction_id.strip_edges().is_empty():
		return
	_awaiting_result = true
	_back.disabled = true
	for child in _interactions.get_children():
		if child is ActionRow:
			var row := child as ActionRow
			row.set_pending_feedback(row == _interaction_rows.get(interaction_id))
			row.disabled = true
	interaction_requested.emit(_npc_id, interaction_id, _expected_revision)


func _request_back() -> void:
	if not _awaiting_result:
		back_requested.emit()


static func _visible_text(value: Variant, fallback: String = "") -> String:
	var text := String(value).strip_edges()
	return fallback if text.is_empty() else text
