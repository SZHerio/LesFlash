class_name EncounterViewModel
extends RefCounted

## Choice-screen model for a contextual encounter.
##
## The encounter reuses the ordinary choice screen over the current environment:
## it interrupts what the player was doing, it does not become a separate place.

const UiModels := preload("res://app/ui_model_factory.gd")


## Closed answers stay hidden unless the player asked to see them, matching how
## every other card in the game treats blocked options.
static func build(
	preview: Dictionary,
	context_title: String,
	show_locked_options: bool = false
) -> Dictionary:
	var options: Array = []
	var available_options: Array = []
	for raw_option: Variant in Array(preview.get("options", [])):
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var available := bool(option.get("available", false))
		var model := {
			"id": String(option.get("id", "")),
			"title": String(option.get("label", "Ответить")),
			"meta": _price(option.get("effects", [])),
			"enabled": available,
			"locked_reason": UiModels.reason_text(option.get("blocked_reasons", [])),
			"variant": "accent" if available else "normal",
		}
		options.append(model)
		if available:
			available_options.append(model)
	if not show_locked_options and not available_options.is_empty():
		options = available_options
	return {
		"eyebrow": "ВСТРЕЧА",
		"title": String(preview.get("title", "Вас заметили")),
		"context": context_title,
		"body": String(preview.get("body", "")),
		"section_title": "Ваш ответ",
		"options": options,
	}


## Shows what an answer costs before it is chosen: time, money and effort.
## Outcome text and mood changes stay hidden so the decision keeps its weight.
static func _price(raw_effects: Variant) -> Array:
	var parts: Array = []
	if not raw_effects is Array:
		return parts
	for raw_effect: Variant in raw_effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		match String(effect.get("type", "")):
			"advance_time":
				var minutes := int(effect.get("minutes", 0))
				if minutes > 0:
					parts.append("%d мин" % minutes)
			"change_money":
				var delta := int(effect.get("delta", 0))
				if delta != 0:
					parts.append("%+d ₽" % delta)
			"change_state":
				if String(effect.get("id", "")) == "energy":
					var energy := int(effect.get("delta", 0))
					if energy != 0:
						parts.append("Энергия %+d" % energy)
	return parts
