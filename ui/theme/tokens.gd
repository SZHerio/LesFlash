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

## Seasonal cast, one hue per month of the game year.
##
## The month contributes a hue and nothing else. Lightness stays whatever the
## surface already had, and chroma is a fixed whisper, so every month sits at
## the same depth and carries the same amount of colour. The first attempt
## stored whole colours and worked in HSV: chroma drifted from 0.006 to 0.034
## between months, which is why some read as night and others as mud.
##
## Mood deliberately does not drive this. Mood is unpredictable and changes in
## the middle of a decision, and it already speaks through the environment
## shader. A month is slow, foreseeable and part of the world.
const MONTH_HUES := [
	250.0, # январь — ледяной синий
	285.0, # февраль — сизый, серо-фиолетовый
	200.0, # март — талый холодный
	155.0, # апрель — влажная земля
	135.0, # май — зелень
	120.0, # июнь — густая листва
	100.0, # июль — выгоревшая пыль
	80.0,  # август — тёплая охра
	60.0,  # сентябрь — ржавая листва
	45.0,  # октябрь — опад
	230.0, # ноябрь — мокрый асфальт
	275.0, # декабрь — ранние сумерки
]

## A surface is tinted, not coloured. Above roughly 0.03 the cast stops reading
## as a season and starts competing with the photograph behind it.
const SURFACE_CHROMA := 0.022


## Hue of a calendar month, 1–12. An out-of-range month falls back to a neutral
## cold grey rather than failing: a broken calendar must not repaint the game.
static func month_hue(month: int) -> float:
	if month < 1 or month > MONTH_HUES.size():
		return 230.0
	return MONTH_HUES[month - 1]


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
