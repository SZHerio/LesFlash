class_name JobShiftCatalog
extends RefCounted

const CatalogIo := preload("res://game/content/catalogs/catalog_io.gd")
const Validator := preload("res://game/jobs/job_shift_catalog_validator.gd")

const SCHEMA_VERSION := 1
const CATALOG_ID := "job_shift_catalog_v1"
const DEFAULT_PATH := "res://game/jobs/data/job_shift_catalog_v1.json"


static func load_default() -> Dictionary:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> Dictionary:
	var parsed := CatalogIo.load_json(path)
	if not bool(parsed.get("ok", false)):
		return parsed
	var validation := Validator.validate(Dictionary(parsed.get("catalog", {})))
	return CatalogIo.validated_result(parsed, validation)


static func validate(catalog: Dictionary) -> Dictionary:
	return Validator.validate(catalog)


static func find_job(catalog: Dictionary, job_id: String) -> Dictionary:
	return _find(Array(catalog.get("jobs", [])), job_id)


static func tasks_for_class(catalog: Dictionary, task_class_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in Array(catalog.get("tasks", [])):
		if raw is Dictionary and String(raw.get("task_class_id", "")) == task_class_id:
			result.append(Dictionary(raw).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return result


static func decisions(catalog: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in Array(catalog.get("decisions", [])):
		if raw is Dictionary:
			result.append(Dictionary(raw).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return result


static func _find(entries: Array, identifier: String) -> Dictionary:
	for raw: Variant in entries:
		if raw is Dictionary and String(raw.get("id", "")) == identifier:
			return Dictionary(raw).duplicate(true)
	return {}
