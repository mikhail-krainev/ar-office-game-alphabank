class_name BlackjackTable
extends Control
## The 21 cloth: the dealer (solo game) or colleagues (multiplayer) on top, the player's hand below.
## New cards fly in from the shoe and turn over; at the end the dealer's hole card turns over and
## the result banner appears only after the last card has landed.

signal card_dealt
signal result_shown(outcome: String)

const TABLE_HEIGHT: float = 248.0
const CARD: Vector2 = Vector2(38, 54)
const SEAT_CARD: Vector2 = Vector2(18, 26)
const SHOE: Vector2 = Vector2(24, 32)
const FLY_TIME: float = 0.34
const DEAL_GAP: float = 0.17
const BANNER_POP: float = 0.25
const DECISION_SECONDS: float = 60.0
const ALREADY_DEALT: float = -100.0

var room: Dictionary = {}
var round_stake: int = 0

var _clock: float = 0.0
## Hand key ("me", "dealer" or a colleague's id) -> start time of each card's flight.
var _starts: Dictionary = {}
var _next_deal: float = 0.0
var _sounds: Array[float] = []
var _hole_flip_at: float = INF
var _banner_at: float = INF
var _banner_sent: bool = false
var _round: int = -1
var _phase: String = ""
var _left: float = 0.0
var _avatars: Dictionary = {}
var _seat_key: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(0, TABLE_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_avatars()


func update_room(data: Dictionary) -> void:
	var fresh: bool = room.is_empty()
	var phase: String = str(data.get("phase", ""))
	var round_number: int = int(data.get("round", 0))
	var new_deal: bool = phase == "playing" and (round_number != _round or _phase != "playing")
	room = data
	_left = float(data.get("left", 0))
	if new_deal or fresh:
		_starts.clear()
		_sounds.clear()
		_next_deal = _clock + 0.1
		_hole_flip_at = INF
		_banner_at = INF
		_banner_sent = false
		round_stake = int(data.get("stake", 0))
	var instant: bool = fresh and phase != "playing"
	var finishing: bool = phase == "finished" and _phase != "finished"
	if finishing:
		# The hole card turns over first, then the dealer draws the rest.
		_hole_flip_at = ALREADY_DEALT if instant else maxf(_next_deal, _clock)
		if not instant:
			_next_deal = _hole_flip_at + DEAL_GAP * 2.0
	_sync_hands(instant)
	if finishing:
		_banner_at = _clock if instant else maxf(_next_deal, _clock) + FLY_TIME
	_round = round_number
	_phase = phase
	_rebuild_avatars()
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_left = maxf(0.0, _left - delta)
	while not _sounds.is_empty() and _sounds[0] <= _clock:
		_sounds.pop_front()
		card_dealt.emit()
	if not _banner_sent and _clock >= _banner_at:
		_banner_sent = true
		result_shown.emit(_outcome())
	queue_redraw()


func _is_solo() -> bool:
	return (room.get("players", []) as Array).size() == 1


func _me() -> Dictionary:
	for p: Dictionary in room.get("players", []):
		if p.get("id", "") == Backend.get_user_id():
			return p
	return {}


func _others() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p: Dictionary in room.get("players", []):
		if p.get("id", "") != Backend.get_user_id():
			result.append(p)
	return result


static func _card_count(player: Dictionary) -> int:
	var cards: Array = player.get("cards", [])
	return cards.size() if not cards.is_empty() else int(player.get("card_count", 0))


## Dealer slots include the face-down hole card while the hand is played.
func _dealer_count() -> int:
	var dealer: Array = room.get("dealer", [])
	if dealer.is_empty():
		return 0
	return maxi(dealer.size(), 2)


## Deals the first two cards around the table in turn, then any further cards in order.
func _sync_hands(instant: bool) -> void:
	var keys: Array[String] = ["me"]
	var counts: Dictionary = {"me": _card_count(_me())}
	for p: Dictionary in _others():
		keys.append(str(p.get("id", "")))
		counts[keys[-1]] = _card_count(p)
	if _is_solo():
		keys.append("dealer")
		counts["dealer"] = _dealer_count()
	for limit: int in [1, 2, 99]:
		for key: String in keys:
			_extend(key, mini(int(counts[key]), limit), instant)


func _extend(key: String, count: int, instant: bool) -> void:
	var starts: Array = _starts.get(key, [])
	while starts.size() < count:
		if instant:
			starts.append(ALREADY_DEALT)
		else:
			var at: float = maxf(_next_deal, _clock)
			_next_deal = at + DEAL_GAP
			starts.append(at)
			_sounds.append(at)
	_starts[key] = starts


func _rebuild_avatars() -> void:
	var others: Array[Dictionary] = _others()
	var ids: PackedStringArray = PackedStringArray()
	for p: Dictionary in others:
		ids.append(str(p.get("id", "")))
	var key: String = ",".join(ids)
	if key == _seat_key:
		return
	_seat_key = key
	for view: Node in _avatars.values():
		view.queue_free()
	_avatars.clear()
	for p: Dictionary in others:
		var view: AvatarView = AvatarView.new(20)
		add_child(view)
		if p.get("character_avatar", false):
			view.show_outfit(p.get("outfit", {}), str(p.get("id", "")))
		else:
			view.show_avatar(str(p.get("avatar", "me")), str(p.get("id", "")))
		_avatars[str(p.get("id", ""))] = view
	_place_avatars()


func _place_avatars() -> void:
	var others: Array[Dictionary] = _others()
	for i: int in others.size():
		var view: AvatarView = _avatars.get(str(others[i].get("id", "")))
		if view != null:
			view.position = Vector2(roundf(_seat_x(i, others.size()) - 10), 12)


func _seat_x(index: int, count: int) -> float:
	var usable: float = size.x - 56.0
	return 14.0 + usable * (index + 0.5) / count


func _shoe_rect() -> Rect2:
	return Rect2(Vector2(size.x - SHOE.x - 12, roundf(size.y * 0.42)), SHOE)


func _draw() -> void:
	CasinoArt.draw_felt(self, Rect2(Vector2.ZERO, size))
	var center_y: float = roundf(size.y * 0.47)
	CasinoArt.draw_text_centered(self, Vector2(size.x / 2.0, center_y - 6), "АЛЬФА · 21", 14, CasinoArt.FELT_LINE.lightened(0.15))
	CasinoArt.draw_text_centered(self, Vector2(size.x / 2.0, center_y + 10), "блэкджек 3:2 · дилер берёт до 17" if _is_solo() else "ближе всех к 21 забирает фонд", 7, CasinoArt.FELT_TEXT)
	_draw_shoe()
	if _is_solo():
		_draw_dealer()
	else:
		_draw_seats()
	_draw_my_hand()
	_draw_timer()
	_draw_banner(center_y + 2)


func _draw_shoe() -> void:
	var shoe: Rect2 = _shoe_rect()
	draw_style_box(CasinoArt.box(CasinoArt.WOOD_DARK, CasinoArt.WOOD, 1, 3), shoe.grow(3))
	for i: int in 3:
		CasinoArt.draw_card(self, Rect2(shoe.position - Vector2(i, i), shoe.size), 0, false)


## Where card `index` of a hand of `count` cards lies, centred on `center_x`.
static func _card_rect(index: int, count: int, center_x: float, top: float, card: Vector2, max_width: float) -> Rect2:
	var step: float = card.x + 4.0
	if count > 1:
		step = minf(step, (max_width - card.x) / (count - 1))
	var width: float = card.x + step * (count - 1)
	return Rect2(Vector2(roundf(center_x - width / 2.0 + step * index), top), card)


## Draws a hand with its flights; `values` empty means face-down cards.
func _draw_hand(key: String, values: Array, count: int, center_x: float, top: float, card: Vector2, max_width: float, hole: int = -1) -> void:
	var starts: Array = _starts.get(key, [])
	var shoe: Vector2 = _shoe_rect().position
	for i: int in mini(count, starts.size()):
		var start: float = float(starts[i])
		if _clock < start:
			continue
		var target: Rect2 = _card_rect(i, count, center_x, top, card, max_width)
		var p: float = clampf((_clock - start) / FLY_TIME, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - p, 3.0)
		var rect: Rect2 = Rect2(shoe.lerp(target.position, eased), card)
		var has_face: bool = i < values.size()
		var turn: float = clampf((p - 0.45) / 0.55, 0.0, 1.0)
		if i == hole:
			turn = clampf((_clock - _hole_flip_at) / 0.3, 0.0, 1.0) if has_face else 0.0
		if not has_face:
			CasinoArt.draw_card(self, rect, 0, false)
			continue
		CasinoArt.draw_card(self, rect, int(values[i]), turn >= 0.5, absf(cos(turn * PI)))


func _hand_landed(key: String) -> bool:
	var starts: Array = _starts.get(key, [])
	return starts.is_empty() or _clock >= float(starts[-1]) + FLY_TIME


func _draw_slots(center_x: float, top: float) -> void:
	for i: int in 2:
		var rect: Rect2 = _card_rect(i, 2, center_x, top, CARD, 200)
		draw_style_box(CasinoArt.box(Color.TRANSPARENT, CasinoArt.FELT_LINE, 1, 3), rect)


func _draw_dealer() -> void:
	var dealer: Array = room.get("dealer", [])
	var top: float = 30.0
	CasinoArt.draw_text_centered(self, Vector2(size.x / 2.0, 17), "ДИЛЕР", 8, CasinoArt.FELT_TEXT)
	if dealer.is_empty():
		_draw_slots(size.x / 2.0, top)
		return
	var count: int = _dealer_count()
	_draw_hand("dealer", dealer, count, size.x / 2.0, top, CARD, size.x - 120, 1)
	if not _hand_landed("dealer"):
		return
	var shown: Array = dealer if _clock >= _hole_flip_at + 0.3 else dealer.slice(0, 1)
	var value: Dictionary = CasinoArt.hand_value(shown)
	var right: float = _card_rect(count - 1, count, size.x / 2.0, top, CARD, size.x - 120).end.x
	CasinoArt.draw_badge(self, Vector2(right + 18, top + CARD.y / 2.0), str(value["total"]), 10, CasinoArt.LOSE if int(value["total"]) > 21 else CasinoArt.WOOD_DARK)


func _draw_seats() -> void:
	var others: Array[Dictionary] = _others()
	var finished: bool = room.get("phase", "") == "finished"
	for i: int in others.size():
		var p: Dictionary = others[i]
		var x: float = _seat_x(i, others.size())
		var width: float = (size.x - 56.0) / others.size() - 4.0
		var seat_name: String = str(p.get("name", ""))
		while seat_name.length() > 3 and CasinoArt.text_width(seat_name, 7) > width:
			seat_name = seat_name.left(seat_name.length() - 2) + "…"
		CasinoArt.draw_text_centered(self, Vector2(x, 41), seat_name, 7, Color.WHITE)
		var count: int = _card_count(p)
		_draw_hand(str(p.get("id", "")), p.get("cards", []), count, x, 49, SEAT_CARD, width)
		var tag: Array = _seat_tag(p, finished)
		if not str(tag[0]).is_empty():
			CasinoArt.draw_badge(self, Vector2(x, 88), str(tag[0]), 7, tag[1])


static func _seat_tag(p: Dictionary, finished: bool) -> Array:
	if p.get("departed", false):
		return ["ВЫШЕЛ", CasinoArt.WOOD_DARK]
	if p.get("eliminated", false):
		return ["ВЫБЫЛ", CasinoArt.WOOD_DARK]
	if p.get("passed", false):
		return ["ПАС", CasinoArt.WOOD_DARK]
	var cards: Array = p.get("cards", [])
	if finished and not cards.is_empty():
		var total: int = int(CasinoArt.hand_value(cards)["total"])
		return ["ПЕРЕБОР" if total > 21 else str(total), CasinoArt.LOSE if total > 21 else CasinoArt.WOOD_DARK]
	if _card_count(p) == 0:
		return ["ГОТОВ", CasinoArt.WIN] if p.get("ready", false) else ["ЖДЁМ", CasinoArt.WOOD_DARK]
	return ["ХВАТИТ", CasinoArt.WOOD_DARK] if p.get("done", false) else ["ДУМАЕТ", CasinoArt.BRASS_DARK]


func _draw_my_hand() -> void:
	var me: Dictionary = _me()
	var top: float = size.y - CARD.y - 20.0
	var cards: Array = me.get("cards", [])
	if cards.is_empty():
		_draw_slots(size.x / 2.0, top)
		return
	var max_width: float = size.x - 120.0
	_draw_hand("me", cards, cards.size(), size.x / 2.0, top, CARD, max_width)
	var first: Rect2 = _card_rect(0, cards.size(), size.x / 2.0, top, CARD, max_width)
	if round_stake > 0:
		CasinoArt.draw_chip(self, Vector2(first.position.x - 22, top + CARD.y / 2.0), 13, round_stake)
	if not _hand_landed("me"):
		return
	var value: Dictionary = CasinoArt.hand_value(cards)
	var total: int = int(value["total"])
	var text: String = str(total)
	var color: Color = CasinoArt.WOOD_DARK
	if total > 21:
		text = "ПЕРЕБОР %d" % total
		color = CasinoArt.LOSE
	elif total == 21 and cards.size() == 2:
		text = "БЛЭКДЖЕК"
		color = CasinoArt.BRASS_DARK
	elif bool(value["soft"]) and total < 21 and not me.get("done", false):
		text = "%d / %d" % [total - 10, total]
	CasinoArt.draw_badge(self, Vector2(size.x / 2.0, top - 10), text, 10, color)


func _draw_timer() -> void:
	var me: Dictionary = _me()
	if room.get("phase", "") != "playing" or me.get("done", false) or me.get("eliminated", false):
		return
	var share: float = clampf(_left / DECISION_SECONDS, 0.0, 1.0)
	var bar: Rect2 = Rect2(Vector2(16, size.y - 11), Vector2(size.x - 32, 3))
	draw_rect(bar, CasinoArt.FELT_DARK)
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * share), bar.size.y)), CasinoArt.LOSE if _left < 10.0 else CasinoArt.BRASS)


## Display-only reading of the finished hand, the server has already paid it out.
func _outcome() -> String:
	var me: Dictionary = _me()
	var stake: int = round_stake
	var award: int = int((room.get("awards", {}) as Dictionary).get(str(me.get("id", "")), 0))
	if not _is_solo():
		if (room.get("winners", []) as Array).has(me.get("id", "")):
			return "win"
		return "push" if stake > 0 and award == stake else "lose"
	if stake > 0:
		return "win" if award > stake else ("push" if award == stake else "lose")
	var mine: Dictionary = CasinoArt.hand_value(me.get("cards", []))
	var dealer: Dictionary = CasinoArt.hand_value(room.get("dealer", []))
	var my_total: int = int(mine["total"])
	var dealer_total: int = int(dealer["total"])
	if me.get("passed", false) or my_total > 21:
		return "lose"
	if my_total == dealer_total:
		return "push"
	return "win" if dealer_total > 21 or my_total > dealer_total else "lose"


func _draw_banner(center_y: float) -> void:
	if _clock < _banner_at:
		return
	var outcome: String = _outcome()
	var award: int = int((room.get("awards", {}) as Dictionary).get(str(_me().get("id", "")), 0))
	var gain: int = award - round_stake
	var title: String = {"win": "ПОБЕДА", "push": "НИЧЬЯ", "lose": "ПРОИГРЫШ"}[outcome]
	if round_stake > 0 and gain != 0:
		title += "  %s%d" % ["+" if gain > 0 else "−", absi(gain)]
	var color: Color = {"win": CasinoArt.WIN, "push": CasinoArt.BRASS_DARK, "lose": CasinoArt.LOSE}[outcome]
	var message: String = str(room.get("message", ""))
	var pop: float = clampf((_clock - _banner_at) / BANNER_POP, 0.0, 1.0)
	var scale_value: float = 0.7 + 0.3 * (1.0 - pow(1.0 - pop, 3.0))
	var rect: Rect2 = Rect2(Vector2(-size.x / 2.0 + 18, -21), Vector2(size.x - 36, 42))
	draw_set_transform(Vector2(size.x / 2.0, center_y), 0.0, Vector2(scale_value, scale_value))
	draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), Color(0, 0, 0, 0.35))
	draw_style_box(CasinoArt.box(color, Color.WHITE, 2, 6), rect)
	CasinoArt.draw_text_centered(self, Vector2(0, -6 if not message.is_empty() else 0), title, 15, Color.WHITE)
	if not message.is_empty():
		CasinoArt.draw_text_centered(self, Vector2(0, 11), message, 8, Color(1, 1, 1, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
