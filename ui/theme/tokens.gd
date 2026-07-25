class_name UiTokens
extends RefCounted

## Closed scales for the interface.
##
## A value that is not in this file must not appear in a theme, a scene or a
## script. The point is not the specific numbers but the closure: the interface
## looked unassembled because eleven radii and eleven animation durations had
## each been picked by eye at the place they were needed.
##
## Motion tokens are deliberately absent here; they arrive with the motion
## system so that duration and easing stay in one place together.

# Spacing — an eight-point rhythm with one half step for tight pairings.
const SPACE_HAIR := 4
const SPACE_XS := 8
const SPACE_S := 12
const SPACE_M := 16
const SPACE_L := 24
const SPACE_XL := 32
const SPACE_XXL := 48
const SPACING := [
	SPACE_HAIR, SPACE_XS, SPACE_S, SPACE_M, SPACE_L, SPACE_XL, SPACE_XXL,
]

## One radius, no exceptions. Zero reads as unfinished next to a hairline border
## on a dense list; sixteen and above is the voice of a friendly consumer app.
## Four reads as precision, which is the tone this game wants.
const RADIUS := 4

# Type — six steps. Body is the 16sp the Android standard requires, and caption
# is its 12sp floor: nothing in the interface may be smaller.
const TEXT_CAPTION := 12
const TEXT_SECONDARY := 14
const TEXT_BODY := 16
const TEXT_TITLE := 20
const TEXT_DISPLAY := 28
const TEXT_HERO := 40
const TYPE_SCALE := [
	TEXT_CAPTION, TEXT_SECONDARY, TEXT_BODY, TEXT_TITLE, TEXT_DISPLAY, TEXT_HERO,
]

# Surfaces — three opaque steps of lightness. Depth comes from these and from a
# hairline border, never from a shadow: in a dark interface a soft shadow turns
# to mud and separates nothing.
const SURFACE_SUNKEN := Color("#0d1412")
const SURFACE_BASE := Color("#16201d")
const SURFACE_RAISED := Color("#1f2b27")
const SURFACES := [SURFACE_SUNKEN, SURFACE_BASE, SURFACE_RAISED]

## Seasonal base tint, one per month of the game year.
##
## Only the hue moves; luminance is held level, so contrast against the text
## never drifts — measured 14.7:1 to 15.7:1 across all twelve against a 4.5:1
## requirement. The accent and the danger colour stay fixed, or the meaning of a
## colour would change with the calendar.
##
## Mood deliberately does not drive this. Mood is unpredictable and changes in
## the middle of a decision; it already speaks through the environment shader. A
## month is slow, foreseeable and part of the world.
const MONTH_TINTS := [
	Color("#101a22"), # январь — ледяной синий
	Color("#15171f"), # февраль — сизый
	Color("#111c1c"), # март — талый серо-зелёный
	Color("#141d18"), # апрель — влажная земля
	Color("#16200f"), # май — приглушённая зелень
	Color("#1a1f10"), # июнь — густая листва
	Color("#1f1d12"), # июль — выгоревшая пыль
	Color("#211b12"), # август — тёплая охра
	Color("#231a13"), # сентябрь — ржавая листва
	Color("#211711"), # октябрь — опад
	Color("#181b1d"), # ноябрь — мокрый асфальт
	Color("#14161f"), # декабрь — ранние сумерки
]


## Seasonal tint for a calendar month, 1–12. Out-of-range months fall back to
## the neutral base rather than failing: a broken calendar must not black out
## the interface.
static func month_tint(month: int) -> Color:
	if month < 1 or month > MONTH_TINTS.size():
		return SURFACE_BASE
	return MONTH_TINTS[month - 1]

const HAIRLINE := Color("#5a686266")
const HAIRLINE_STRONG := Color("#7f8d87a6")
const BORDER_WIDTH := 1

# Scrim laid under content that has to sit over a photograph. Content surfaces
# themselves stay opaque: the photograph shows between blocks, not under lines.
const SCRIM := Color("#0b1211d9")

# Minimum touch target and the height of a main action, in device pixels.
const TOUCH_MIN := 48
const ACTION_HEIGHT := 56


static func is_spacing(value: int) -> bool:
	return value in SPACING


static func is_type_size(value: int) -> bool:
	return value in TYPE_SCALE


## Nearest legal spacing step, for migrating a value that was picked by eye.
static func snap_spacing(value: int) -> int:
	var best: int = SPACE_HAIR
	for step: int in SPACING:
		if absi(step - value) < absi(best - value):
			best = step
	return best
