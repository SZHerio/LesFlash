class_name ActionResult
extends RefCounted

## Structured result returned by ActionTransaction.

var success: bool = false
var code: StringName = &"unknown"
var message: String = ""
var blocked_reasons: Array[Dictionary] = []
var changes: Array[Dictionary] = []
var journal_entry: Dictionary = {}
var failed_effect_index: int = -1


static func succeeded(
		result_changes: Array[Dictionary],
		result_journal_entry: Dictionary
	) -> ActionResult:
	var result := ActionResult.new()
	result.success = true
	result.code = &"ok"
	result.message = "Действие выполнено"
	result.changes = result_changes.duplicate(true)
	result.journal_entry = result_journal_entry.duplicate(true)
	return result


static func blocked(reasons: Array[Dictionary]) -> ActionResult:
	var result := ActionResult.new()
	result.success = false
	result.code = &"blocked"
	result.message = "Условия действия не выполнены"
	result.blocked_reasons = reasons.duplicate(true)
	return result


static func failed(
		error_code: StringName,
		error_message: String,
		effect_index: int = -1,
		partial_changes: Array[Dictionary] = []
	) -> ActionResult:
	var result := ActionResult.new()
	result.success = false
	result.code = error_code
	result.message = error_message
	result.failed_effect_index = effect_index
	# These records describe the discarded clone; the original state is intact.
	result.changes = partial_changes.duplicate(true)
	return result


func to_dict() -> Dictionary:
	return {
		"success": success,
		"code": String(code),
		"message": message,
		"blocked_reasons": blocked_reasons.duplicate(true),
		"changes": changes.duplicate(true),
		"journal_entry": journal_entry.duplicate(true),
		"failed_effect_index": failed_effect_index,
	}
