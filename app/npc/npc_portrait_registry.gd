class_name NpcPortraitRegistry
extends RefCounted

## Stable presentation mapping for recurring characters. Domain catalogs keep
## gameplay references; replacing or versioning art never changes NPC rules.

const PORTRAITS := {
	"npc_viktor_koren": {
		"portrait_key": "npc_viktor_koren_neutral_v1",
		"portrait_path": "res://assets/portraits/npc_viktor_koren.png",
		"portrait_crop_mode": "focus_cover",
		"portrait_focus": {"x": 0.50, "y": 0.31},
	},
	"npc_lidia_maren": {
		"portrait_key": "npc_lidia_maren_neutral_v1",
		"portrait_path": "res://assets/portraits/npc_lidia_maren.png",
		"portrait_crop_mode": "focus_cover",
		"portrait_focus": {"x": 0.50, "y": 0.34},
	},
	"npc_tamara_roven": {
		"portrait_key": "npc_tamara_roven_neutral_v1",
		"portrait_path": "res://assets/portraits/npc_tamara_roven.png",
		"portrait_crop_mode": "focus_cover",
		"portrait_focus": {"x": 0.50, "y": 0.30},
	},
}


static func entry(npc_id: String) -> Dictionary:
	return Dictionary(PORTRAITS.get(npc_id, {})).duplicate(true)


static func portrait_path(npc_id: String) -> String:
	return String(Dictionary(PORTRAITS.get(npc_id, {})).get("portrait_path", ""))
