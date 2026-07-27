extends SceneTree


class CommandSpy extends SessionCommandRunner:
	var busy := false

	func in_flight() -> bool:
		return busy


class InventorySpy extends InventoryFlowCoordinator:
	var modal := false
	var consume_back := false
	var back_calls := 0

	func has_modal() -> bool:
		return modal

	func handle_back() -> bool:
		back_calls += 1
		return consume_back


class SearchSpy extends SearchFlowCoordinator:
	var consume_back := false
	var back_calls := 0

	func handle_back() -> bool:
		back_calls += 1
		return consume_back


var _calls: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var commands := CommandSpy.new()
	var inventory := InventorySpy.new()
	var search := SearchSpy.new()
	var flow := ShellNavigationFlowCoordinator.new()
	var shell := AppShell.new()
	flow.configure(
		shell,
		commands,
		inventory,
		search,
		{
			"close": _mark.bind("close"),
			"main_menu": _mark.bind("main_menu"),
			"return_settings": _mark.bind("return_settings"),
			"leave_session": _mark.bind("leave_session"),
			"location": _mark.bind("location"),
			"map": _mark.bind("map"),
			"hero": _mark.bind("hero"),
			"inventory": _mark.bind("inventory"),
		}
	)

	flow.navigate("map", "location")
	flow.navigate("hero", "location")
	flow.navigate("items", "location")
	flow.navigate("place", "map")
	if not _expect_calls({"map": 1, "hero": 1, "inventory": 1, "location": 1}):
		return

	commands.busy = true
	flow.navigate("map", "location")
	flow.handle_back("npc")
	commands.busy = false
	if not _expect_calls({"map": 1, "location": 1}):
		return

	inventory.modal = true
	flow.navigate("map", "inventory")
	inventory.modal = false
	flow.navigate("map", "inventory")
	if not _expect_calls({"map": 2}):
		return

	flow.navigate("hero", "search")
	if not _expect_calls({"hero": 1}):
		return

	inventory.consume_back = true
	flow.handle_back("inventory")
	if inventory.back_calls != 1 or not _expect_calls({"location": 1}):
		return
	inventory.consume_back = false
	flow.handle_back("inventory")
	if inventory.back_calls != 2 or not _expect_calls({"location": 2}):
		return

	search.consume_back = true
	flow.handle_back("search")
	if search.back_calls != 1 or not _expect_calls({"location": 2}):
		return
	search.consume_back = false
	flow.handle_back("search")
	if search.back_calls != 2 or not _expect_calls({"location": 3}):
		return

	for route: String in ["map", "hero", "npc", "shop", "shelter", "job_result"]:
		flow.handle_back(route)
	if not _expect_calls({"location": 9}):
		return

	flow.handle_back("settings")
	flow.handle_back("location")
	flow.handle_back("summary")
	flow.handle_back("menu")
	flow.handle_back("creation")
	if not _expect_calls({
		"return_settings": 1,
		"leave_session": 2,
		"close": 1,
		"main_menu": 1,
	}):
		return

	shell.free()
	print("SHELL NAVIGATION FLOW TEST: PASS")
	quit(0)


func _mark(key: String) -> void:
	_calls[key] = int(_calls.get(key, 0)) + 1


func _expect_calls(expected: Dictionary) -> bool:
	for key: Variant in expected:
		var actual := int(_calls.get(key, 0))
		if actual != int(expected[key]):
			_fail("hook '%s' called %d times, expected %d" % [key, actual, expected[key]])
			return false
	return true


func _fail(message: String) -> void:
	push_error("SHELL NAVIGATION FLOW TEST: %s" % message)
	quit(1)
