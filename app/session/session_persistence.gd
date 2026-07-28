class_name SessionPersistence
extends RefCounted

const DefaultAdapter := preload("res://app/session/sandbox_session_adapter.gd")
const DefaultSaveSlot := preload("res://app/session/save_slot.gd")

var _create_session: Callable
var _load_session: Callable
var _has_candidates: Callable
var _save_in_progress := false


func _init(dependencies: Dictionary = {}) -> void:
	_create_session = dependencies.get("create_session", Callable(DefaultAdapter, "create"))
	_load_session = dependencies.get("load_session", Callable(DefaultAdapter, "load_session"))
	_has_candidates = dependencies.get("has_candidates", Callable(DefaultSaveSlot, "has_candidates"))


func has_candidates() -> bool:
	return bool(_has_candidates.call())


func create_session(characteristics: Dictionary, seed: int) -> RunSessionAdapter:
	return _create_session.call(characteristics, seed) as RunSessionAdapter


func load_session() -> Dictionary:
	var result: Variant = _load_session.call()
	return result if result is Dictionary else {
		"ok": false,
		"code": "invalid_load_result",
		"error": "Хранилище вернуло неверный результат загрузки.",
	}


func save_session(session: RunSessionAdapter) -> Dictionary:
	if session == null:
		return {"ok": true}
	if _save_in_progress:
		return {"ok": false, "code": "save_in_progress", "error": "Сохранение уже выполняется"}
	_save_in_progress = true
	var result: Dictionary = session.save()
	_save_in_progress = false
	return result
