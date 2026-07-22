class_name SaveSlot
extends RefCounted

const FirstDaySaveScript := preload("res://game/first_day/first_day_save.gd")


static func has_candidates(path: String = FirstDaySave.DEFAULT_SAVE_PATH) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return (
		FileAccess.file_exists(absolute)
		or FileAccess.file_exists(absolute + ".tmp")
		or FileAccess.file_exists(absolute + ".bak")
	)
