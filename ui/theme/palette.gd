class_name M3Palette
extends RefCounted

const INK := Color("#0b1211")
const TEXT := Color("#f4efe4")
const MUTED := Color("#b8c1bc")
const FAINT := Color("#7f8d87")
const PANEL := Color("#14201ddd")
const PANEL_SOLID := Color("#17231fff")
const PANEL_LIGHT := Color("#21312cf2")
const BORDER := Color("#71807999")
const GREEN := Color("#7ca18a")
const GREEN_BRIGHT := Color("#9bc5a7")
const RUST := Color("#c1744f")
const GOLD := Color("#dfb86c")
const DANGER := Color("#cf716b")
const BLUE := Color("#72a6b0")
const VIOLET := Color("#9c8fbd")


static func status_accent(status_id: StringName) -> Color:
	match status_id:
		&"health":
			return Color("#d76f68")
		&"hunger":
			return Color("#d6a85c")
		&"energy":
			return Color("#7eaa8a")
		&"tension":
			return Color("#9d8fc0")
		&"morale":
			return Color("#72a8b1")
		_:
			return GREEN
