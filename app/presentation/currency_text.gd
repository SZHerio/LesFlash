class_name CurrencyText
extends RefCounted

## Russian presentation helpers for the fictional arden. Domain state stores an
## integer amount; screens decide between the authored mark and these fallbacks.

const CODE := &"ARD"
const FALLBACK := "ард."


static func compact(amount: int) -> String:
	return "%d %s" % [amount, FALLBACK]


static func signed_compact(amount: int) -> String:
	return "%s%d %s" % ["+" if amount > 0 else "", amount, FALLBACK]


static func full(amount: int) -> String:
	return "%d %s" % [amount, _noun(amount)]


static func _noun(amount: int) -> String:
	var absolute := absi(amount)
	var last_two := absolute % 100
	if last_two >= 11 and last_two <= 14:
		return "арденов"
	match absolute % 10:
		1:
			return "арден"
		2, 3, 4:
			return "ардена"
		_:
			return "арденов"
