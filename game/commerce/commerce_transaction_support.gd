class_name CommerceTransactionSupport
extends RefCounted

const Access := preload("res://game/commerce/commerce_candidate_access.gd")
const PriceResolverScript := preload("res://game/commerce/price_resolver.gd")
const StockSnapshotScript := preload("res://game/commerce/stock_snapshot.gd")


static func guard_snapshot(
	snapshot: Dictionary,
	command_id: String,
	expected_revision: int,
	expected_store_id: String = ""
) -> Dictionary:
	var validation := StockSnapshotScript.validate(snapshot)
	if not bool(validation.get("ok", false)):
		return failure("invalid_stock", "stock snapshot is invalid", validation)
	if command_id.strip_edges().is_empty() or command_id.length() > 160:
		return failure("invalid_command_id", "command_id must be non-empty and bounded")
	if not expected_store_id.is_empty() and String(snapshot["store_id"]) != expected_store_id:
		return failure("store_mismatch", "stock snapshot belongs to another store")
	if StockSnapshotScript.has_command(snapshot, command_id):
		return {"ok": true, "already_applied": true}
	if expected_revision != int(snapshot["revision"]):
		return failure("revision_conflict", "stock changed since it was displayed")
	return {"ok": true, "already_applied": false}


static func idempotent_candidate(run_state: Variant, snapshot: Dictionary) -> Dictionary:
	var clone_result := Access.clone_candidate(run_state, "run_state")
	if not bool(clone_result.get("ok", false)):
		return clone_result
	return {
		"ok": true,
		"code": "already_applied",
		"already_applied": true,
		"run_state_candidate": clone_result["candidate"],
		"stock_snapshot_candidate": snapshot.duplicate(true),
		"receipt": {},
	}


static func finish_snapshot_candidate(
	run_candidate: Variant,
	source_snapshot: Dictionary,
	offers: Array,
	command_id: String,
	receipt: Dictionary
) -> Dictionary:
	var next_snapshot := StockSnapshotScript.with_committed_command(source_snapshot, command_id, offers)
	var snapshot_validation := StockSnapshotScript.validate(next_snapshot)
	if not bool(snapshot_validation.get("ok", false)):
		return failure("invalid_stock_candidate", "stock candidate failed validation", snapshot_validation)
	var run_validation := Access.validate_candidate(run_candidate, "run_state")
	if not bool(run_validation.get("ok", false)):
		return run_validation
	return {
		"ok": true,
		"code": "ok",
		"already_applied": false,
		"run_state_candidate": run_candidate,
		"stock_snapshot_candidate": next_snapshot,
		"receipt": receipt.duplicate(true),
	}


static func attach_world_candidate(prepared: Dictionary, world_state: Variant, store_id: String) -> Dictionary:
	if not bool(prepared.get("ok", false)):
		return prepared
	var clone_result := Access.clone_candidate(world_state, "world_state")
	if not bool(clone_result.get("ok", false)):
		return clone_result
	var world_candidate: Variant = clone_result["candidate"]
	if not Access.set_stock_snapshot(world_candidate, store_id, prepared["stock_snapshot_candidate"]):
		return failure("stock_write_failed", "world candidate rejected the stock snapshot")
	var validation := Access.validate_candidate(world_candidate, "world_state")
	if not bool(validation.get("ok", false)):
		return validation
	var result := prepared.duplicate()
	result["world_state_candidate"] = world_candidate
	return result


static func checked_total(unit_price: int, quantity: int) -> Dictionary:
	if unit_price < 0 or quantity <= 0:
		return failure("invalid_total", "unit price and quantity are invalid")
	if unit_price > 0 and quantity > PriceResolverScript.MAX_PRICE / unit_price:
		return failure("price_overflow", "transaction total exceeds the money domain")
	return {"ok": true, "total": unit_price * quantity}


static func stable_token(value_text: String) -> String:
	var value := 91_919
	for byte: int in value_text.to_utf8_buffer():
		value = (value * 131 + byte) % 2_147_483_647
	return str(value if value > 0 else 1)


static func failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error": message}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
