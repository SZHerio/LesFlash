extends SceneTree

## Проход по балансу для внешнего вида, отдельным заходом.
##
## Три вопроса записаны до того, как это было построено. Заметит ли игрок
## разницу без подсказки; нельзя ли выглядеть прилично бесплатно; и не заперто
## ли за плохим видом то, у чего нет другого пути.

const Appearance = preload("res://game/appearance/appearance_rules.gd")
const RunStateScript = preload("res://core/state/run_state.gd")
const ItemCatalog = preload("res://core/inventory/item_catalog.gd")
const ActionCatalog = preload("res://game/sandbox/sandbox_action_catalog.gd")
const SandboxAdapter = preload("res://app/session/sandbox_session_adapter.gd")

const BUILD := {"strength": 7, "charisma": 4, "intelligence": 4, "luck": 3}
const CLOTHES := ["warm_jacket", "sturdy_boots", "work_gloves"]


func _init() -> void:
	print("APPEARANCE BALANCE PROBE")
	print("  чистый, по числу надетых вещей:")
	for worn: int in range(0, CLOTHES.size() + 1):
		var state := _state(worn, 0)
		print("    %d вещей: %2d — %s" % [
			worn, Appearance.score_of(state), Appearance.title_of(Appearance.band_of(state)),
		])

	print("  --")
	print("  одетый в три вещи, по дням без мытья:")
	for days: int in [0, Appearance.NOTICEABLE_DAYS, Appearance.UNMISTAKABLE_DAYS]:
		var state := _state(CLOTHES.size(), days)
		print("    %2d дней: %2d — %s" % [
			days, Appearance.score_of(state), Appearance.title_of(Appearance.band_of(state)),
		])

	print("  --")
	var cost := 0
	for item_id: String in CLOTHES:
		var definition: Variant = ItemCatalog.definition(item_id)
		if definition != null:
			cost += int(definition.call("base_value"))
	print("  одеться целиком стоит %d ард; мытьё — только времени" % cost)

	var gated := 0
	var loaded := ActionCatalog.load_default()
	if bool(loaded.get("ok", false)):
		for raw_action: Variant in Array(Dictionary(loaded["catalog"]).get("actions", [])):
			for raw_requirement: Variant in Array(Dictionary(raw_action).get("requirements", [])):
				if String(Dictionary(raw_requirement).get("type", "")) == "appearance_min":
					gated += 1
	print("  за видом заперто действий: %d" % gated)
	print("APPEARANCE BALANCE PROBE WRITTEN")
	quit(0)


## Одевает героя тем же путём, каким это делает игрок. Первая версия замера
## переставляла предмету поле контейнера напрямую, ничего этим не добивалась и
## сообщала, что одежда не читается вовсе.
func _state(worn: int, days_unwashed: int) -> RunState:
	var adapter = SandboxAdapter.create(BUILD, 91_301)
	if adapter == null:
		return null
	var session = adapter.get("_session")
	session.location = "underpass"
	session.phase = "map"
	for index: int in worn:
		var item_id := String(CLOTHES[index])
		session.run_state.add_item(item_id, 1, "hands")
		var stack_id := _stack_of(adapter, item_id)
		if stack_id != "":
			adapter.perform_inventory_action(stack_id, "equip")
	if days_unwashed > 0:
		session.run_state.calendar.advance_minutes(days_unwashed * 1440)
	return session.run_state


func _stack_of(adapter: Object, item_id: String) -> String:
	var inventory: Dictionary = Dictionary(adapter.get_inventory_model()).get("inventory", {})
	for key: Variant in Dictionary(inventory.get("containers", {})):
		var container: Dictionary = Dictionary(inventory["containers"])[key]
		for raw_stack: Variant in Array(container.get("stacks", [])):
			if String(Dictionary(raw_stack).get("item_id", "")) == item_id:
				return String(Dictionary(raw_stack).get("stack_id", ""))
	return ""
