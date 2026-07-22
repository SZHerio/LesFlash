class_name UiErrorLocalizer
extends RefCounted

const MESSAGES := {
	"save_not_found": "Сохранение не найдено.",
	"no_valid_save": "Сохранение повреждено, восстановить его не удалось.",
	"invalid_json": "Файл сохранения повреждён.",
	"empty_save": "Файл сохранения пуст.",
	"invalid_envelope": "Структура сохранения повреждена.",
	"invalid_schema_version": "Версия сохранения указана неверно.",
	"unsupported_schema_version": "Сохранение создано несовместимой версией игры.",
	"session_migration_failed": "Старое сохранение не удалось безопасно обновить.",
	"run_state_migration_failed": "Состояние персонажа в сохранении повреждено.",
	"session_deserialization_failed": "Игровую сессию не удалось восстановить.",
	"loaded_session_validation_failed": "Сохранение содержит противоречивые данные.",
	"pending_temporary_recovery": "Найдено незавершённое сохранение. Сначала восстановите попытку.",
	"temporary_recovery_failed": "Незавершённое сохранение не удалось восстановить.",
	"backup_recovery_failed": "Резервную копию не удалось восстановить.",
	"directory_creation_failed": "Не удалось подготовить папку сохранений.",
	"temporary_open_failed": "Не удалось создать временный файл сохранения.",
	"temporary_write_failed": "Не удалось записать сохранение.",
	"temporary_validation_failed": "Записанное сохранение не прошло проверку.",
	"save_install_failed": "Не удалось заменить предыдущее сохранение.",
	"installed_save_invalid": "Новое сохранение не прошло проверку после записи.",
	"save_open_failed": "Не удалось прочитать файл сохранения.",
	"session_validation_failed": "Текущее состояние игры нельзя безопасно сохранить.",
	"serialization_validation_failed": "Сохранение не прошло внутреннюю проверку.",
	"preferences_load_failed": "Настройки интерфейса не удалось прочитать.",
	"preferences_save_failed": "Настройки интерфейса не удалось сохранить.",
	"save_in_progress": "Сохранение уже выполняется.",
}


static func message(result: Dictionary) -> String:
	var code := String(result.get("code", ""))
	var technical_message := String(result.get("error", ""))
	if not technical_message.is_empty():
		push_warning("UI operation failed [%s]: %s" % [code, technical_message])
	if MESSAGES.has(code):
		return String(MESSAGES[code])
	if _contains_cyrillic(technical_message):
		return technical_message
	return "Не удалось выполнить операцию. Попробуйте ещё раз."


static func _contains_cyrillic(value: String) -> bool:
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if codepoint >= 0x0400 and codepoint <= 0x052F:
			return true
	return false
