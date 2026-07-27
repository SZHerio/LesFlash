class_name CommerceCandidateAccess
extends RefCounted

## Duck-typed boundary for future RunState/WorldState candidates.
## Commerce prepares clones; an owning session decides whether to commit both.


static func clone_candidate(source: Variant, role: String) -> Dictionary:
	if source is Dictionary:
		return {"ok": true, "candidate": Dictionary(source).duplicate(true)}
	if not source is Object or not is_instance_valid(source):
		return _failure("invalid_%s" % role, "%s must be a live object or dictionary" % role)
	if not source.has_method("clone"):
		return _failure("missing_clone", "%s must expose clone()" % role)
	var candidate: Variant = source.call("clone")
	if candidate == null:
		return _failure("clone_failed", "%s.clone() returned null" % role)
	var validation := validate_candidate(candidate, role)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "candidate": candidate}


static func validate_candidate(candidate: Variant, role: String) -> Dictionary:
	if candidate is Dictionary:
		return {"ok": true}
	if not candidate is Object or not is_instance_valid(candidate):
		return _failure("invalid_%s" % role, "%s candidate is invalid" % role)
	if not candidate.has_method("validate"):
		return {"ok": true}
	var result: Variant = candidate.call("validate")
	if not result is Dictionary or not bool(result.get("ok", false)):
		return _failure("invalid_%s" % role, "%s candidate failed validation" % role, {
			"validation": result,
		})
	return {"ok": true}


static func inventory(run_state: Variant) -> Dictionary:
	var value: Variant = _read(run_state, "inventory")
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func set_inventory(run_state: Variant, value: Dictionary) -> bool:
	return _write(run_state, "inventory", value.duplicate(true))


static func money(run_state: Variant) -> Variant:
	var value: Variant = _read(run_state, "money")
	return value if typeof(value) == TYPE_INT else null


static func change_money(run_state: Variant, delta: int) -> bool:
	if run_state is Object and run_state.has_method("change_money"):
		return bool(run_state.call("change_money", delta))
	var current: Variant = money(run_state)
	if current == null:
		return false
	if delta > 0 and int(current) > 1_000_000_000_000 - delta:
		return false
	if int(current) + delta < 0:
		return false
	return _write(run_state, "money", int(current) + delta)


static func strength(run_state: Variant) -> int:
	if run_state is Object and run_state.has_method("get_characteristic"):
		return int(run_state.call("get_characteristic", "strength"))
	var values: Variant = _read(run_state, "characteristics")
	return int(Dictionary(values).get("strength", 5)) if values is Dictionary else 5


static func stock_snapshot(world_state: Variant, store_id: String) -> Dictionary:
	if world_state is Object and world_state.has_method("get_stock_snapshot"):
		var direct: Variant = world_state.call("get_stock_snapshot", store_id)
		return Dictionary(direct).duplicate(true) if direct is Dictionary else {}
	var snapshots: Variant = _read(world_state, "stock_snapshots")
	if snapshots is Dictionary and snapshots.has(store_id) and snapshots[store_id] is Dictionary:
		return Dictionary(snapshots[store_id]).duplicate(true)
	return {}


static func set_stock_snapshot(world_state: Variant, store_id: String, snapshot: Dictionary) -> bool:
	if world_state is Object and world_state.has_method("set_stock_snapshot"):
		var result: Variant = world_state.call("set_stock_snapshot", store_id, snapshot.duplicate(true))
		if result is Dictionary:
			return bool(result.get("ok", false))
		return true if result == null else bool(result)
	var snapshots: Variant = _read(world_state, "stock_snapshots")
	if not snapshots is Dictionary:
		return false
	var candidate: Dictionary = Dictionary(snapshots).duplicate(true)
	candidate[store_id] = snapshot.duplicate(true)
	return _write(world_state, "stock_snapshots", candidate)


static func _read(value: Variant, property_name: String) -> Variant:
	if value is Dictionary:
		return value.get(property_name, null)
	if value is Object and _has_property(value, property_name):
		return value.get(property_name)
	return null


static func _write(value: Variant, property_name: String, property_value: Variant) -> bool:
	if value is Dictionary:
		value[property_name] = property_value
		return true
	if value is Object and _has_property(value, property_name):
		value.set(property_name, property_value)
		return true
	return false


static func _has_property(value: Object, property_name: String) -> bool:
	for raw_property: Variant in value.get_property_list():
		if raw_property is Dictionary and String(raw_property.get("name", "")) == property_name:
			return true
	return false


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	result.merge(details, true)
	return result
