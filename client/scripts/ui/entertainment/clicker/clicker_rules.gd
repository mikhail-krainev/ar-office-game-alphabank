class_name ClickerRules
extends RefCounted
## The clicker formulas of the server (server/modules/clicker.go), repeated only to animate the
## numbers between replies and to price the buttons. The server's state always wins.

var data: Dictionary = {}


func _init(rules: Dictionary = {}) -> void:
	data = rules


func tiers() -> Array:
	return data.get("tiers", [])


func gold_levels() -> Array:
	return data.get("gold", [])


func achievements() -> Array:
	return data.get("achievements", [])


func growth() -> float:
	return float(data.get("growth", 1.15))


func cost(tier: int) -> float:
	return float(data.get("cost_scale", 1)) * pow(10.0, float(tiers()[tier].get("exp", 0)))


func tap_gain(tier: int) -> float:
	return float(data.get("gain_scale", 1)) * pow(10.0, float(tiers()[tier].get("exp", 0)) * float(data.get("gain_power", 0.6)))


func gain(kind: String, tier: int) -> float:
	return tap_gain(tier) / (float(data.get("idle_divisor", 6)) if kind == "idle" else 1.0)


func level_bonus(level: int) -> float:
	return level * pow(2.0, floorf(float(level) / float(data.get("double_every", 25))))


func price(kind: String, tier: int, level: int, count: int) -> float:
	var base: float = cost(tier) * (float(data.get("idle_cost", 2)) if kind == "idle" else 1.0)
	var g: float = growth()
	return base * pow(g, level) * (pow(g, count) - 1.0) / (g - 1.0)


## How many levels `points` buy, at most `limit`.
func affordable(kind: String, tier: int, level: int, points: float, limit: int) -> int:
	var first: float = price(kind, tier, level, 1)
	if points < first:
		return 0
	var n: int = clampi(int(floor(log(points * (growth() - 1.0) / first + 1.0) / log(growth()))), 1, limit)
	while n > 1 and price(kind, tier, level, n) > points:
		n -= 1
	return n


func unlock_at(kind: String, tier: int) -> float:
	return price(kind, tier, 0, 1) * float(data.get("unlock_share", 0.5))


func combo(rate: float) -> float:
	var from: float = float(data.get("combo_from", 2))
	var to: float = float(data.get("combo_to", 8))
	return 1.0 + (float(data.get("combo_max", 2)) - 1.0) * clampf((rate - from) / (to - from), 0.0, 1.0)


func gold_name(level: int) -> String:
	if level <= 0:
		return "Красный кот удачи"
	return str(gold_levels()[mini(level, gold_levels().size()) - 1].get("name", ""))


func gold_at(level: int) -> float:
	return pow(10.0, float(gold_levels()[level - 1].get("at", 0)))


func gold_mult(level: int) -> float:
	return 1.0 if level <= 0 else pow(10.0, float(gold_levels()[level - 1].get("mult", 0)))
