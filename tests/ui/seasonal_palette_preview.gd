extends SceneTree

## Renders the same screen once per month so the seasonal cast can be judged by
## eye. Twelve descriptions of a colour are worth nothing; twelve pictures side
## by side show immediately whether a month reads as a season or as dirt.
##
## Also asserts what the palette promises: every month must hold the same
## perceived depth and the same amount of colour, and text contrast must stay
## far above the readability floor on all of them.

const AppShellScene := preload("res://app/app_shell.tscn")
const LegacySession := preload("res://game/first_day/first_day_session.gd")
const SandboxAdapterScript := preload("res://app/session/sandbox_session_adapter.gd")
const TokensScript := preload("res://ui/theme/tokens.gd")
const ColourSpace := preload("res://ui/theme/colour_space.gd")
const OUTPUT_DIR := "res://docs/qa/palette"
const TEST_SIZE := Vector2i(360, 640)
const MONTH_NAMES := [
	"01_january", "02_february", "03_march", "04_april",
	"05_may", "06_june", "07_july", "08_august",
	"09_september", "10_october", "11_november", "12_december",
]
const TEXT := Color("#f4efe4")

class MemoryPersistence extends SessionPersistence:
	var session: FirstDaySession

	func has_candidates() -> bool:
		return false

	func create_session(characteristics: Dictionary, _seed: int) -> FirstDaySessionAdapter:
		session = LegacySession.create_location_first(characteristics, 74_112)
		return SandboxAdapterScript.new(session)

	func load_session() -> Dictionary:
		return {"ok": false, "code": "save_not_found"}

	func save_session(_session: FirstDaySessionAdapter) -> Dictionary:
		return {"ok": true}


class MemoryPreferences extends UiPreferences:
	func load_from_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true, "created": true}

	func save_to_disk(_path: String = SETTINGS_PATH) -> Dictionary:
		return {"ok": true}


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_palette_is_uniform()
	await _render_every_month()
	if _failures.is_empty():
		print("SEASONAL PALETTE PREVIEW PASSED: 12 месяцев одной глубины")
		quit(0)
		return
	print("SEASONAL PALETTE PREVIEW FAILED: %d" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


## The whole point of moving to OKLCH: lightness and chroma hold still while
## only the hue turns. In the first HSV attempt chroma ranged six-fold between
## months, and that is what made some of them look like mud.
func _check_palette_is_uniform() -> void:
	var lightness: Array[float] = []
	var chroma: Array[float] = []
	for month in range(1, 13):
		var surface := ColourSpace.recast(
			TokensScript.SURFACE_BASE,
			TokensScript.SURFACE_CHROMA,
			TokensScript.month_hue(month)
		)
		var oklch := ColourSpace.to_oklch(surface)
		lightness.append(oklch.x)
		chroma.append(oklch.y)
		var ratio := _contrast(TEXT, surface)
		if ratio < 4.5:
			_failures.append("месяц %d: контраст текста %.2f:1 ниже нормы 4.5:1" % [month, ratio])
	if maxf(lightness.max() - lightness.min(), 0.0) > 0.01:
		_failures.append("светлота гуляет между месяцами: %.3f..%.3f" % [lightness.min(), lightness.max()])
	if maxf(chroma.max() - chroma.min(), 0.0) > 0.002:
		_failures.append("цветность гуляет между месяцами: %.4f..%.4f" % [chroma.min(), chroma.max()])


func _render_every_month() -> void:
	var viewport := SubViewport.new()
	viewport.size = TEST_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell := AppShellScene.instantiate() as AppShell
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(shell.get_node("UiCoordinator") as UiCoordinator).configure(
		MemoryPersistence.new(),
		MemoryPreferences.new()
	)
	viewport.add_child(shell)
	for _frame in range(5):
		await process_frame
	(shell.current_screen() as MainMenuScreen).new_game_requested.emit()
	await process_frame
	(shell.current_screen() as CharacterCreationScreen).character_confirmed.emit({
		"strength": 5, "charisma": 6, "intelligence": 4, "luck": 3
	})
	for _frame in range(6):
		await process_frame
	await create_timer(0.3, true, false, true).timeout

	for month in range(1, 13):
		shell.set_month(month)
		for _frame in range(3):
			await process_frame
		await _capture(viewport, MONTH_NAMES[month - 1])
	root.remove_child(viewport)
	viewport.queue_free()
	await process_frame


func _contrast(a: Color, b: Color) -> float:
	var first := _relative_luminance(a)
	var second := _relative_luminance(b)
	var brighter := maxf(first, second)
	var darker := minf(first, second)
	return (brighter + 0.05) / (darker + 0.05)


func _relative_luminance(colour: Color) -> float:
	var channels := [colour.r, colour.g, colour.b]
	var linear: Array[float] = []
	for channel: float in channels:
		linear.append(
			channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
		)
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


func _capture(viewport: SubViewport, basename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s: пустой рендер" % basename)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if image.save_png("%s/%s.png" % [OUTPUT_DIR, basename]) != OK:
		_failures.append("%s: снимок не сохранён" % basename)
