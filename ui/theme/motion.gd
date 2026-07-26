class_name UiMotion
extends RefCounted

## Named durations, curves and one tween factory for the whole interface.
##
## Before this file 16 scripts created their own tweens with 11 different
## durations, and 21 decided independently what "reduced motion" means. A
## duration written at a call site is a decision nobody can review: 0.17 and
## 0.18 sat next to each other on two sheets that open the same way.
##
## Durations follow the intervals in UI_UX_STANDARD §4 and the test in
## `tests/ui/motion_conformance_test.gd` fails on any token that leaves them,
## and on any numeric duration written into a screen or component.

## Press feedback: 80–120 ms. The only motion a finger sees while still touching
## the glass, so it has to finish before the finger lifts.
const PRESS := 0.10

## Ordinary transition: 180–260 ms. Fading is shorter than moving, so a panel
## reaches full opacity while still travelling and reads as arriving rather than
## materialising.
const FADE := 0.18
const REVEAL := 0.20
const SHEET := 0.24

## Screen change: at most 320 ms. Deliberately longer than an ordinary
## transition — a change of place must not feel like a row expanding.
const SCREEN := 0.28

## Meter change: 240–450 ms "depending on the size of the delta". Taken
## literally, see `meter_duration`.
const METER_MIN := 0.24
const METER_MAX := 0.45

## Not an interface transition and deliberately outside the intervals above:
## this is the trip itself being shown, not a control responding. The ceiling in
## §4 governs how fast the interface answers the player, and here the player is
## watching something happen rather than waiting for a reply.
const JOURNEY := 0.72

## How long a toast stays legible once it has arrived. Dwell, not motion.
const TOAST_DWELL := 3.2
const TOAST_DWELL_ERROR := 4.2

enum Shape {
	ENTER, ## Arriving. Fast first, settles at the end.
	EXIT, ## Leaving. Slow first, accelerates away.
	TRAVEL, ## Continuous movement with a start and a stop of its own.
}


## A meter that moves by one point and a meter that halves should not take the
## same time. `span` is the full range of the meter, so the caller does not have
## to know the token values.
static func meter_duration(delta: float, span: float = 100.0) -> float:
	if span <= 0.0:
		return METER_MIN
	var share := clampf(absf(delta) / span, 0.0, 1.0)
	return lerpf(METER_MIN, METER_MAX, share)


## Animates `steps` on `host`, killing whatever `previous` was still running.
##
## Returns `null` when motion is off or the host is detached — and in that case
## the final values are already applied, so a caller never has to branch on
## reduced motion itself. That branch is the whole reason the policy used to be
## copied into 21 files.
static func play(
	previous: Tween,
	host: Node,
	steps: Array,
	reduced_motion: bool,
	shape: Shape = Shape.ENTER
) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	if steps.is_empty():
		return null
	if reduced_motion or host == null or not host.is_inside_tree():
		for raw_step: Variant in steps:
			_settle(raw_step)
		return null
	var tween := host.create_tween()
	if steps.size() > 1:
		tween.set_parallel(true)
	_shape(tween, shape)
	for raw_step: Variant in steps:
		var step: Dictionary = raw_step
		var target: Object = step["target"]
		if target == null:
			continue
		tween.tween_property(
			target,
			NodePath(String(step["property"])),
			step["to"],
			float(step["duration"])
		)
	return tween


## Press feedback is the one motion reduced mode drops entirely instead of
## settling. Every other animation ends where the element belongs, so applying
## the final value early is the same picture without the movement. This one ends
## where it began — squeeze down, spring back — so settling would snap the
## control to the squeezed size and hold it there. Reduced motion has to mean
## "leave it alone", not "jump to frame one".
static func press(
	previous: Tween,
	host: Node,
	target: Object,
	scale: float,
	reduced_motion: bool
) -> Tween:
	if reduced_motion:
		stop(previous)
		return null
	return play(
		previous,
		host,
		[{"target": target, "property": "scale", "to": Vector2.ONE * scale, "duration": PRESS}],
		false
	)


## The same contract for animations that drive a setter rather than a property —
## a redraw, a shader parameter, a path position.
static func play_method(
	previous: Tween,
	host: Node,
	setter: Callable,
	from: float,
	to: float,
	duration: float,
	reduced_motion: bool,
	shape: Shape = Shape.ENTER
) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	if not setter.is_valid():
		return null
	if reduced_motion or host == null or not host.is_inside_tree():
		setter.call(to)
		return null
	var tween := host.create_tween()
	_shape(tween, shape)
	tween.tween_method(setter, from, to, duration)
	return tween


static func stop(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


static func _settle(raw_step: Variant) -> void:
	var step: Dictionary = raw_step
	var target: Object = step["target"]
	if target != null:
		target.set_indexed(NodePath(String(step["property"])), step["to"])


static func _shape(tween: Tween, shape: Shape) -> void:
	match shape:
		Shape.EXIT:
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		Shape.TRAVEL:
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_:
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
