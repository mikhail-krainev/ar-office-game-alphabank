class_name ClickerNumbers
extends RefCounted
## Huge clicker numbers in Russian: "12,3 млн", "4,56 квинвигинтлн", up to 10^303. Beyond the
## names the number is shown as "1,2e306".

const SHORT: Array[String] = ["", "тыс.", "млн", "млрд", "трлн", "квадрлн", "квинтлн", "секстлн", "септлн", "октлн", "нонлн"]
const FULL: Array[String] = ["", "тысяча", "миллион", "миллиард", "триллион", "квадриллион", "квинтиллион", "секстиллион", "септиллион", "октиллион", "нониллион"]
## Latin prefixes of the n-illions from 10 (decillion, 10^33) to 99 (10^300).
const UNITS: Array[String] = ["", "ун", "дуо", "тре", "кваттуор", "квин", "секс", "септен", "окто", "новем"]
const TENS: Array[String] = ["", "дец", "вигинт", "тригинт", "квадрагинт", "квинквагинт", "сексагинт", "септуагинт", "октогинт", "нонагинт"]


## Name of 10^(3·group): group 1 is a thousand, group 2 a million and so on.
static func group_name(group: int, full: bool = false) -> String:
	if group < SHORT.size():
		return FULL[group] if full else SHORT[group]
	var n: int = group - 1
	if n >= 100:
		return ""
	var stem: String = UNITS[n % 10] + TENS[int(n / 10.0)]
	return stem + ("иллион" if full else "лн")


static func format(value: float, full: bool = false) -> String:
	if is_nan(value) or value < 0.0:
		return "0"
	if value < 1.0:
		return _decimal(value, 2)
	if value < 1000.0:
		return _decimal(value, 1 if value < 10.0 else 0)
	var group: int = int(floor(log(value) / log(1000.0) + 1e-9))
	var name: String = group_name(group, full)
	var mantissa: float = value / pow(1000.0, group)
	if mantissa >= 999.95:
		group += 1
		name = group_name(group, full)
		mantissa /= 1000.0
	if name.is_empty():
		var exponent: int = int(floor(log(value) / log(10.0)))
		return "%se%d" % [_decimal(value / pow(10.0, exponent), 2), exponent]
	var digits: int = 2 if mantissa < 10.0 else (1 if mantissa < 100.0 else 0)
	return "%s %s" % [_decimal(mantissa, digits), name]


## A number with a decimal comma and no trailing zeros.
static func _decimal(value: float, digits: int) -> String:
	var factor: float = pow(10.0, digits)
	var text: String = String.num(floorf(value * factor + 1e-6) / factor, digits)
	if text.contains("."):
		text = text.rstrip("0").trim_suffix(".")
	return text.replace(".", ",")
