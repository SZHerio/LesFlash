extends SceneTree

const IconRegistryScript := preload("res://ui/icons/icon_registry.gd")
const SemanticIconScene := preload("res://ui/components/semantic_icon.tscn")
const SemanticIconButtonScene := preload("res://ui/components/semantic_icon_button.tscn")
const NavTabButtonScene := preload("res://ui/components/nav_tab_button.tscn")
const MetaTokenScene := preload("res://ui/components/meta_token.tscn")
const MoneyAmountScene := preload("res://ui/components/money_amount.tscn")

const EXPECTED_IDS: Array[StringName] = [
	&"action_food", &"action_observe", &"action_rest", &"action_search",
	&"action_shelter", &"action_study", &"action_talk", &"action_trade",
	&"action_work", &"currency_arden_compact", &"currency_arden_full",
	&"meta_energy", &"meta_item", &"meta_knowledge", &"meta_relationship",
	&"meta_risk", &"meta_time", &"nav_hero", &"nav_items", &"nav_map",
	&"nav_place", &"nav_tasks", &"place_clinic", &"place_embankment",
	&"place_market", &"place_recycling", &"place_station", &"place_underpass",
	&"transport_bus", &"transport_tram", &"transport_walk",
	&"utility_chevron_right", &"utility_info", &"utility_locked",
	&"utility_settings",
]
const LIVE_TEXT_ROOTS := ["res://app", "res://game", "res://ui/components", "res://ui/screens"]
const LIVE_TEXT_EXTENSIONS := ["gd", "tscn", "json"]
const FORBIDDEN_GLYPHS := ["₽", "⚙", "🗺", "👤", "📦", "💰", "🔒"]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_registry()
	_check_renderer_contract()
	_check_accessibility_contract()
	for root_path: String in LIVE_TEXT_ROOTS:
		_scan_live_text(root_path)
	if _failures.is_empty():
		print("ICONOGRAPHY CONFORMANCE PASSED: 35 authored SVG IDs and clean live UI")
		quit(0)
		return
	for failure: String in _failures:
		push_error("ICONOGRAPHY: %s" % failure)
	quit(1)


func _check_registry() -> void:
	var actual := IconRegistryScript.all_ids()
	_require(actual == EXPECTED_IDS, "registry IDs differ from the authored package")
	for icon_id: StringName in EXPECTED_IDS:
		var path := IconRegistryScript.path_for(icon_id)
		_require(not path.is_empty(), "%s has no asset path" % icon_id)
		_require(FileAccess.file_exists(path), "%s asset is missing" % icon_id)
		_require(IconRegistryScript.texture(icon_id) != null, "%s does not load as Texture2D" % icon_id)
		var source := FileAccess.get_file_as_string(path)
		_require('viewBox="0 0 24 24"' in source, "%s has a wrong SVG viewBox" % icon_id)
		_require('stroke-width="1.75"' in source, "%s left the shared stroke system" % icon_id)
	_require(not IconRegistryScript.has(&"currency_rouble"), "real-world currency ID leaked into registry")
	_require(IconRegistryScript.texture(&"unknown_icon") == null, "unknown ID must fail safely")


func _check_renderer_contract() -> void:
	var icon := SemanticIconScene.instantiate() as SemanticIcon
	root.add_child(icon)
	for size_dp: int in [16, 20, 24, 32]:
		_require(icon.present(&"nav_map", size_dp), "renderer rejected %d dp" % size_dp)
		_require(int(icon.custom_minimum_size.x) == size_dp, "renderer did not apply %d dp" % size_dp)
	icon.present(&"nav_map", 18)
	_require(int(icon.custom_minimum_size.x) == 24, "unsupported size did not normalise to 24 dp")
	_require(not icon.present(&"unknown_icon", 24), "missing icon must be hidden")
	_require(not icon.visible, "missing icon remained visible")
	icon.queue_free()


func _check_accessibility_contract() -> void:
	var settings := SemanticIconButtonScene.instantiate() as SemanticIconButton
	root.add_child(settings)
	settings.present(&"utility_settings", "Настройки", 24)
	_require(settings.accessibility_name == "Настройки", "icon button has no native accessible name")
	settings.queue_free()

	var nav := NavTabButtonScene.instantiate() as NavTabButton
	root.add_child(nav)
	nav.present(&"nav_map", "Карта")
	_require(nav.accessibility_name == "Карта", "navigation tab has no native accessible name")
	nav.queue_free()

	var token := MetaTokenScene.instantiate() as MetaToken
	root.add_child(token)
	token.present({"icon_id": &"meta_time", "text": "5 мин", "accessible_text": "Пять минут"})
	_require(token.accessibility_name == "Пять минут", "metadata token is not exposed as one phrase")
	token.queue_free()

	var money := MoneyAmountScene.instantiate() as MoneyAmount
	root.add_child(money)
	money.present({"amount": 5})
	_require(money.accessibility_name == "5 арденов", "money amount is not exposed as one phrase")
	money.queue_free()


func _scan_live_text(root_path: String) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		_require(false, "cannot scan %s" % root_path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			_scan_live_text(path)
		elif LIVE_TEXT_EXTENSIONS.has(entry.get_extension().to_lower()):
			if path == "res://ui/main.tscn":
				entry = directory.get_next()
				continue
			var source := FileAccess.get_file_as_string(path)
			for glyph: String in FORBIDDEN_GLYPHS:
				_require(glyph not in source, "%s contains forbidden UI glyph %s" % [path, glyph])
		entry = directory.get_next()
	directory.list_dir_end()


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
