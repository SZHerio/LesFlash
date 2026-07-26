class_name UiColourSpace
extends RefCounted

## Conversion between sRGB and OKLCH.
##
## HSV is the wrong tool for tinting surfaces: it is not perceptually uniform,
## so the same saturation and value give a clean night blue on one hue and mud
## on another. Measured across the first seasonal palette, chroma ranged from
## 0.006 to 0.034 — nearly six times — which is why some months looked coloured
## and others looked dirty.
##
## In OKLCH lightness and chroma mean the same thing at every hue, so a palette
## can hold both steady and move only the hue.


static func to_oklch(colour: Color) -> Vector3:
	var r := _to_linear(colour.r)
	var g := _to_linear(colour.g)
	var b := _to_linear(colour.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	var lightness := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var a_axis := 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	var b_axis := 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return Vector3(
		lightness,
		sqrt(a_axis * a_axis + b_axis * b_axis),
		rad_to_deg(atan2(b_axis, a_axis))
	)


static func from_oklch(lightness: float, chroma: float, hue_degrees: float, alpha: float = 1.0) -> Color:
	var hue := deg_to_rad(hue_degrees)
	var a_axis := chroma * cos(hue)
	var b_axis := chroma * sin(hue)
	var l := lightness + 0.3963377774 * a_axis + 0.2158037573 * b_axis
	var m := lightness - 0.1055613458 * a_axis - 0.0638541728 * b_axis
	var s := lightness - 0.0894841775 * a_axis - 1.2914855480 * b_axis
	l = l * l * l
	m = m * m * m
	s = s * s * s
	return Color(
		_to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		_to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		_to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
		alpha
	)


## Keeps a colour's own lightness and gives it the palette's hue and chroma, so
## a surface stays exactly as deep as it was and only changes its cast.
static func recast(colour: Color, chroma: float, hue_degrees: float) -> Color:
	return from_oklch(to_oklch(colour).x, chroma, hue_degrees, colour.a)


static func _to_linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


static func _to_srgb(channel: float) -> float:
	var value := (
		channel * 12.92
		if channel <= 0.0031308
		else 1.055 * pow(maxf(channel, 0.0), 1.0 / 2.4) - 0.055
	)
	return clampf(value, 0.0, 1.0)
