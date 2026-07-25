extends SceneTree

## Enforces the closed UI scales declared in ui/theme/tokens.gd.
##
## Without this check the eleven radii, ten type sizes and fifteen paddings that
## were just removed would quietly return: every one of them entered the project
## as a reasonable local choice.

const Tokens := preload("res://ui/theme/tokens.gd")

const ROOTS := ["res://ui", "res://app"]
## The legacy M2 screen still carries hand-picked values. It is deleted at M3F
## rather than migrated, so it is excluded instead of silently failing.
const LEGACY := ["res://ui/main.gd", "res://ui/main.tscn"]
const SCANNED_SUFFIXES := [".tres", ".tscn", ".gd"]

var _failures: Array[String] = []
var _scanned := 0


func _init() -> void:
	var files := _collect()
	if files.size() < 20:
		_failures.append("scan found only %d files; the walk is broken" % files.size())
	for path: String in files:
		_check(path)
	if _failures.is_empty():
		print("UI SCALE CONFORMANCE PASSED: %d файлов в шкалах" % _scanned)
		quit(0)
		return
	print("UI SCALE CONFORMANCE FAILED: %d нарушений" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1)


func _collect() -> Array[String]:
	var result: Array[String] = []
	for root: String in ROOTS:
		_walk(root, result)
	result.sort()
	return result


func _walk(directory: String, result: Array[String]) -> void:
	var handle := DirAccess.open(directory)
	if handle == null:
		return
	handle.list_dir_begin()
	var entry := handle.get_next()
	while not entry.is_empty():
		var path := "%s/%s" % [directory, entry]
		if handle.current_is_dir():
			if not entry.begins_with("."):
				_walk(path, result)
		elif path not in LEGACY:
			for suffix: String in SCANNED_SUFFIXES:
				if entry.ends_with(suffix):
					result.append(path)
					break
		entry = handle.get_next()
	handle.list_dir_end()


func _check(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("%s: не читается" % path)
		return
	var text := file.get_as_text()
	_scanned += 1
	_scan(path, text, "corner_radius_[a-z_]+ = ([0-9]+)", func(value: int) -> bool:
		return value == Tokens.RADIUS
	, "радиус вне шкалы")
	_scan(path, text, "font_size[a-z/_]* = ([0-9]+)", func(value: int) -> bool:
		return Tokens.is_type_size(value)
	, "кегль вне шкалы")
	_scan(path, text, "content_margin_[a-z]+ = ([0-9]+)", func(value: int) -> bool:
		return value == 0 or Tokens.is_spacing(value)
	, "внутренний отступ вне шкалы")
	_scan(path, text, "[hv]?_?separation = ([0-9]+)", func(value: int) -> bool:
		return value == 0 or Tokens.is_spacing(value)
	, "промежуток вне шкалы")
	_scan(path, text, "shadow_size = ([0-9]+)", func(_value: int) -> bool:
		return false
	, "тень: высота задаётся светлотой поверхности и рамкой")


func _scan(
	path: String,
	text: String,
	pattern: String,
	allowed: Callable,
	message: String
) -> void:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		_failures.append("%s: некорректный шаблон %s" % [path, pattern])
		return
	var seen: Dictionary = {}
	for found: RegExMatch in regex.search_all(text):
		var value := int(found.get_string(1))
		if bool(allowed.call(value)) or seen.has(value):
			continue
		seen[value] = true
		_failures.append("%s: %s — %d" % [path.trim_prefix("res://"), message, value])
