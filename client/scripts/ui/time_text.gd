class_name TimeText
extends RefCounted
## Durations in words and clock-style countdowns for the play-time and task-limit messages.


## 60 -> "1 час", 90 -> "1 ч 30 мин", 5 -> "5 минут". `genitive` is for "более 1 часа".
static func minutes(total: int, genitive: bool = false) -> String:
	var hours: int = total / 60
	var rest: int = total % 60
	var suffix: String = "_GEN" if genitive else ""
	if hours == 0:
		return "%d %s" % [rest, plural(rest, "TIME_MINUTES" + suffix)]
	if rest == 0:
		return "%d %s" % [hours, plural(hours, "TIME_HOURS" + suffix)]
	return TranslationServer.translate("TIME_HOURS_MINUTES") % [hours, rest]


## Seconds left as whole minutes, rounded up: 61 -> "2 мин".
static func short_minutes(seconds: int) -> String:
	return TranslationServer.translate("TIME_MINUTES_SHORT") % ceili(maxi(seconds, 0) / 60.0)


## 299 -> "04:59", 3725 -> "1:02:05".
static func countdown(seconds: int) -> String:
	var left: int = maxi(seconds, 0)
	if left >= 3600:
		return "%d:%02d:%02d" % [left / 3600, left / 60 % 60, left % 60]
	return "%02d:%02d" % [left / 60, left % 60]


## Picks the form of a "one|few|many" translation for `count`.
static func plural(count: int, key: String) -> String:
	var forms: PackedStringArray = String(TranslationServer.translate(key)).split("|")
	if forms.size() < 3:
		return forms[0]
	if not TranslationServer.get_locale().begins_with("ru"):
		return forms[0] if count == 1 else forms[1]
	var mod10: int = count % 10
	var mod100: int = count % 100
	if mod10 == 1 and mod100 != 11:
		return forms[0]
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
		return forms[1]
	return forms[2]
