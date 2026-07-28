extends SceneTree

## A card whose options can all be closed at once must offer a way out.
##
## The shelter list is exactly that case: before 18:00 every place is shut by
## its time window, and the screen used to show a list of things the player
## could not do with no control to leave. Only the Android Back button escaped
## it, which is nothing at all on a desktop build.

const ChoiceScene := preload("res://ui/screens/choice/choice_screen.tscn")
const UiModels := preload("res://app/ui_model_factory.gd")

const LOCKED_SHELTERS := [
	{
		"id": "station_hall",
		"title": "Зал ожидания",
		"description": "Теплее улицы, если получится объяснить, почему вы ждёте поезд.",
		"quality": 2,
		"risk": 2,
		"locked": true,
		"reasons": [{"message": "Ночлег можно выбрать с 18:00 до 08:00"}],
	},
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_shelters_offer_an_exit()
	_check_exit_reaches_its_handler()
	_check_a_decision_keeps_no_exit()
	if _failures.is_empty():
		print("CHOICE EXIT TEST PASSED: запертый список выпускает игрока")
		quit(0)
		return
	print("CHOICE EXIT TEST FAILED: %d" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _check_shelters_offer_an_exit() -> void:
	var model := UiModels.shelters(LOCKED_SHELTERS)
	var available := 0
	for raw_option: Variant in Array(model.get("options", [])):
		if raw_option is Dictionary and bool(raw_option.get("enabled", false)):
			available += 1
	_expect(available == 0, "фикстура должна оставить все варианты закрытыми")
	_expect(
		not String(model.get("leave_text", "")).is_empty(),
		"список ночлегов не предлагает выхода, хотя все варианты закрыты"
	)
	var screen := _mount(model)
	_expect(screen.has_exit(), "экран не показал кнопку выхода")
	_unmount(screen)


func _check_exit_reaches_its_handler() -> void:
	var screen := _mount(UiModels.shelters(LOCKED_SHELTERS))
	var left := [false]
	screen.leave_requested.connect(func() -> void: left[0] = true)
	(screen.get_node("%LeaveButton") as Button).pressed.emit()
	_expect(bool(left[0]), "нажатие выхода не дошло до обработчика")
	_unmount(screen)


## An event always keeps one available answer, so leaving one is not the same as
## leaving a list of shut doors and must stay impossible.
func _check_a_decision_keeps_no_exit() -> void:
	var screen := _mount(UiModels.event({
		"title": "Решение",
		"body": "Что делать",
		"choices": [{"id": "go", "label": "Действовать"}],
	}))
	_expect(not screen.has_exit(), "событие не должно предлагать выход мимо решения")
	_unmount(screen)


func _mount(model: Dictionary) -> ChoiceScreen:
	var screen := ChoiceScene.instantiate() as ChoiceScreen
	root.add_child(screen)
	screen.present(model)
	return screen


func _unmount(screen: ChoiceScreen) -> void:
	root.remove_child(screen)
	screen.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
