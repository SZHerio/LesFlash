class_name WorldProcessDefinitionValidator
extends RefCounted

## Validates authored time advancement and observable stage projections.
## Structural graph validation remains in WorldDefinitionCatalog.

const Rules := preload("res://game/content/catalogs/catalog_rules.gd")
const MAX_ELAPSED_MINUTES := 9_007_199_254_740_991
const MAX_BASIS_POINTS := 20_000
const ADVANCE_MODE := "confirmed_time"


static func validate(
	process: Dictionary,
	stages: Dictionary,
	transitions: Dictionary,
	facts: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	if String(process.get("advance_mode", "")) != ADVANCE_MODE:
		errors.append("%s.advance_mode должен быть %s" % [path, ADVANCE_MODE])
	_validate_stage_projections(stages, path, errors)
	_validate_transition_policies(transitions, facts, path, errors)


static func _validate_stage_projections(
	stages: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	for stage_id: String in stages:
		var stage: Dictionary = stages[stage_id]
		var stage_path := "%s.stages.%s" % [path, stage_id]
		var raw_projection: Variant = stage.get("projection", null)
		if not raw_projection is Dictionary:
			errors.append("%s.projection должен быть объектом" % stage_path)
			continue
		var projection: Dictionary = raw_projection
		_validate_job_projection(projection.get("job", null), stage_path, errors)
		_validate_recycling_projection(
			projection.get("recycling", null), stage_path, errors
		)
		_validate_location_projection(
			projection.get("location", null), stage_path, errors
		)
		Rules.validate_id_array(
			projection.get("event_tags", null),
			"%s.projection.event_tags" % stage_path,
			errors,
			true
		)


static func _validate_job_projection(
	raw_value: Variant,
	stage_path: String,
	errors: Array[String]
) -> void:
	var path := "%s.projection.job" % stage_path
	if not raw_value is Dictionary:
		errors.append("%s должен быть объектом" % path)
		return
	var value: Dictionary = raw_value
	var job_id := String(value.get("job_id", ""))
	if not Rules.valid_id(job_id) or not job_id.begins_with("job_"):
		errors.append("%s.job_id должен быть стабильным job_ ID" % path)
	if typeof(value.get("available", null)) != TYPE_BOOL:
		errors.append("%s.available должен быть булевым" % path)
	Rules.validate_int_range(
		value.get("pay_basis_points", null),
		0,
		MAX_BASIS_POINTS,
		"%s.pay_basis_points" % path,
		errors
	)
	if (
		typeof(value.get("available", null)) == TYPE_BOOL
		and not bool(value["available"])
		and int(value.get("pay_basis_points", -1)) != 0
	):
		errors.append("%s недоступная работа должна иметь нулевую оплату" % path)


static func _validate_recycling_projection(
	raw_value: Variant,
	stage_path: String,
	errors: Array[String]
) -> void:
	var path := "%s.projection.recycling" % stage_path
	if not raw_value is Dictionary:
		errors.append("%s должен быть объектом" % path)
		return
	var value: Dictionary = raw_value
	var organization_id := String(value.get("organization_id", ""))
	if not Rules.valid_id(organization_id) or not organization_id.begins_with("org_"):
		errors.append("%s.organization_id должен быть стабильным org_ ID" % path)
	if typeof(value.get("accepting_materials", null)) != TYPE_BOOL:
		errors.append("%s.accepting_materials должен быть булевым" % path)
	Rules.validate_int_range(
		value.get("price_basis_points", null),
		0,
		MAX_BASIS_POINTS,
		"%s.price_basis_points" % path,
		errors
	)
	if (
		typeof(value.get("accepting_materials", null)) == TYPE_BOOL
		and not bool(value["accepting_materials"])
		and int(value.get("price_basis_points", -1)) != 0
	):
		errors.append("%s закрытый приём должен иметь нулевую цену" % path)


static func _validate_location_projection(
	raw_value: Variant,
	stage_path: String,
	errors: Array[String]
) -> void:
	var path := "%s.projection.location" % stage_path
	if not raw_value is Dictionary:
		errors.append("%s должен быть объектом" % path)
		return
	var value: Dictionary = raw_value
	for field: String in ["location_id", "status_id"]:
		if not Rules.valid_id(value.get(field, null)):
			errors.append("%s.%s должен быть стабильным ID" % [path, field])


static func _validate_transition_policies(
	transitions: Dictionary,
	facts: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var outgoing: Dictionary = {}
	var exclusive_groups: Dictionary = {}
	for transition_id: String in transitions:
		var transition: Dictionary = transitions[transition_id]
		var transition_path := "%s.transitions.%s" % [path, transition_id]
		Rules.validate_int_range(
			transition.get("priority", null),
			1,
			10_000,
			"%s.priority" % transition_path,
			errors
		)
		Rules.validate_int_range(
			transition.get("eligible_after_elapsed_minutes", null),
			0,
			MAX_ELAPSED_MINUTES,
			"%s.eligible_after_elapsed_minutes" % transition_path,
			errors
		)
		_validate_fact_sets(transition, facts, transition_path, errors)
		var from_id := String(transition.get("from_stage_id", ""))
		var siblings: Array = outgoing.get(from_id, [])
		siblings.append(transition)
		outgoing[from_id] = siblings
		var group_id := String(transition.get("mutual_exclusion_group_id", ""))
		if group_id.is_empty():
			continue
		if not Rules.valid_id(group_id):
			errors.append("%s.mutual_exclusion_group_id некорректен" % transition_path)
			continue
		var group_key := "%s:%s" % [from_id, group_id]
		var members: Array = exclusive_groups.get(group_key, [])
		members.append(transition)
		exclusive_groups[group_key] = members
	for from_id: String in outgoing:
		_validate_sibling_priority_and_time(
			from_id, Array(outgoing[from_id]), path, errors
		)
	for group_key: String in exclusive_groups:
		_validate_exclusive_group(
			group_key, Array(exclusive_groups[group_key]), path, errors
		)


static func _validate_fact_sets(
	transition: Dictionary,
	facts: Dictionary,
	path: String,
	errors: Array[String]
) -> void:
	var required := _id_set(Array(transition.get("required_fact_ids", [])))
	var excluded := _id_set(Array(transition.get("excluded_fact_ids", [])))
	for fact_id: String in required:
		if excluded.has(fact_id):
			errors.append("%s одновременно требует и исключает %s" % [path, fact_id])
		if not facts.has(fact_id):
			errors.append("%s ссылается на неизвестный факт %s" % [path, fact_id])
	for fact_id: String in excluded:
		if not facts.has(fact_id):
			errors.append("%s ссылается на неизвестный факт %s" % [path, fact_id])


static func _validate_sibling_priority_and_time(
	from_id: String,
	siblings: Array,
	path: String,
	errors: Array[String]
) -> void:
	var priorities: Dictionary = {}
	var threshold: Variant = null
	for raw_transition: Variant in siblings:
		var transition: Dictionary = raw_transition
		var priority := int(transition.get("priority", -1))
		if priorities.has(priority):
			errors.append(
				"%s: переходы из %s должны иметь разные priority" % [path, from_id]
			)
		priorities[priority] = true
		var current_threshold: Variant = transition.get(
			"eligible_after_elapsed_minutes", null
		)
		if threshold == null:
			threshold = current_threshold
		elif current_threshold != threshold:
			errors.append(
				"%s: переходы из %s должны иметь общий временной порог" % [
					path, from_id,
				]
			)


static func _validate_exclusive_group(
	group_key: String,
	members: Array,
	path: String,
	errors: Array[String]
) -> void:
	if members.size() < 2:
		errors.append("%s: группа %s должна содержать минимум два перехода" % [path, group_key])
		return
	for left_index: int in members.size():
		for right_index: int in range(left_index + 1, members.size()):
			var left: Dictionary = members[left_index]
			var right: Dictionary = members[right_index]
			if not _fact_conditions_are_exclusive(left, right):
				errors.append(
					"%s: группа %s не гарантирует взаимоисключение %s и %s" % [
						path,
						group_key,
						String(left.get("id", "")),
						String(right.get("id", "")),
					]
				)


static func _fact_conditions_are_exclusive(left: Dictionary, right: Dictionary) -> bool:
	var left_required := _id_set(Array(left.get("required_fact_ids", [])))
	var left_excluded := _id_set(Array(left.get("excluded_fact_ids", [])))
	var right_required := _id_set(Array(right.get("required_fact_ids", [])))
	var right_excluded := _id_set(Array(right.get("excluded_fact_ids", [])))
	for fact_id: String in left_required:
		if right_excluded.has(fact_id):
			return true
	for fact_id: String in right_required:
		if left_excluded.has(fact_id):
			return true
	return false


static func _id_set(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_id: Variant in ids:
		result[String(raw_id)] = true
	return result
