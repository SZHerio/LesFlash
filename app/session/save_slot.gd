class_name SaveSlot
extends RefCounted

const RunSaveScript := preload("res://game/run/run_save.gd")


static func has_candidates(path: String = RunSave.DEFAULT_SAVE_PATH) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return (
		FileAccess.file_exists(absolute)
		or FileAccess.file_exists(absolute + ".tmp")
		or FileAccess.file_exists(absolute + ".bak")
	)
