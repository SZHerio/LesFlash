extends SceneTree

const UiModels := preload("res://app/ui_model_factory.gd")
const UiErrors := preload("res://app/ui_error_localizer.gd")


func _init() -> void:
	var transaction := {
		"changes": [
			{"effect_type": "change_money", "target_kind": "money", "target_id": "money", "delta": 24},
			{"effect_type": "change_state", "target_kind": "state", "target_id": "energy", "delta": -7},
			{"effect_type": "change_state", "target_kind": "state", "target_id": "energy", "delta": 2},
			{"effect_type": "advance_time", "target_kind": "time", "target_id": "calendar", "delta": 120},
			{"effect_type": "unlock_skill", "target_kind": "skill", "target_id": "first_aid", "delta": 1},
		],
	}
	var facts := UiModels.transaction_facts(transaction)
	var expected := ["Деньги: +24 ард.", "Энергия: -7", "Энергия: +2", "Время: +120 мин", "Первая помощь: +1"]
	if facts != expected:
		push_error("UI MODEL FACTORY FAILED: expected %s, got %s" % [expected, facts])
		quit(1)
		return
	var shell_model := {
		"location": {"title": "Вокзальная площадь", "actions": []},
		"status": {
			"meters": {"health": 70, "hunger": 40, "energy": 55, "tension": 100, "mental_state": 0},
			"calendar": {"year": 1974, "month": 9, "day": 12, "minute_of_day": 500},
		},
	}
	var off_model := UiModels.location(shell_model, false, 1.0, "off", transaction)
	var reduced_model := UiModels.location(shell_model, false, 1.0, "reduced", transaction)
	var replay_model := UiModels.location(shell_model, false, 1.0, "full", transaction, false)
	var statuses: Array = off_model.get("statuses", [])
	var energy_delta := 0
	for status_value in statuses:
		if status_value is Dictionary and String(status_value.get("id", "")) == "energy":
			energy_delta = int(status_value.get("delta", 0))
	if energy_delta != -5:
		push_error("UI MODEL FACTORY FAILED: real status deltas were not aggregated")
		quit(1)
		return
	for status_value in Array(replay_model.get("statuses", [])):
		if status_value is Dictionary and bool(status_value.get("animate_delta", true)):
			push_error("UI MODEL FACTORY FAILED: a consumed status delta would animate again")
			quit(1)
			return
	if not is_zero_approx(float(off_model.get("psyche_intensity", -1.0))):
		push_error("UI MODEL FACTORY FAILED: disabled psyche filter is not zero")
		quit(1)
		return
	if not is_equal_approx(float(reduced_model.get("psyche_intensity", 0.0)), 0.45):
		push_error("UI MODEL FACTORY FAILED: reduced psyche filter is not scaled")
		quit(1)
		return
	if UiErrors.message({"code": "invalid_json", "error": "Invalid JSON."}) != "Файл сохранения повреждён.":
		push_error("UI MODEL FACTORY FAILED: a technical save error reached the Russian UI")
		quit(1)
		return
	print("UI MODEL FACTORY TEST PASSED: changes, status deltas, psyche modes and errors")
	quit(0)
