class_name EventWorkbench
extends RefCounted

## Headless/editor-facing event viewer. A tool can pass any validated
## EventContext and receive the exact pool trace plus option availability.

const Director := preload("res://game/events/event_director.gd")


static func inspect(
	catalog: Dictionary,
	context: Dictionary,
	card_id: String = ""
) -> Dictionary:
	var analysis := Director.analyze(catalog, context)
	if not bool(analysis.get("ok", false)):
		return analysis
	var selected_id := card_id
	if selected_id.is_empty():
		for raw_trace: Variant in Array(analysis.get("cards", [])):
			if raw_trace is Dictionary and bool(raw_trace.get("included", false)):
				selected_id = String(raw_trace.get("card_id", ""))
				break
	var card_trace: Dictionary = {}
	for raw_trace: Variant in Array(analysis.get("cards", [])):
		if raw_trace is Dictionary and String(raw_trace.get("card_id", "")) == selected_id:
			card_trace = Dictionary(raw_trace).duplicate(true)
			break
	return {
		"ok": true,
		"code": "ok",
		"card_id": selected_id,
		"card_trace": card_trace,
		"preview": Director.preview(catalog, selected_id, context),
		"pool_trace": analysis,
	}
