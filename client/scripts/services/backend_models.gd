class_name BackendModels
extends RefCounted
## Data returned by the Backend service, parsed from the server's RPC answers by BackendParser.


class Profile:
	extends RefCounted

	## Server account id; shown to colleagues as a profile QR code.
	var user_id: String = ""
	var display_name: String = ""
	var department: String = ""
	## Short text under the avatar, like a status in a messenger.
	var status: String = ""
	## Template id from AvatarCatalog, or AvatarCatalog.CUSTOM for an uploaded picture.
	var avatar: String = ""
	var balance: int = 0
	## Office workdays in a row. Today counts once the player has checked in.
	var streak_days: int = 0
	var present_today: bool = false
	## Scanned the entry code and not the exit code yet: tasks and room codes count only now.
	var in_office: bool = false
	## Reward multiplier for the current streak, e.g. 1.5.
	var multiplier: float = 1.0
	var welcome_bonus: int = 0
	## Absence fines taken since the previous login, and the streak that was lost, for the morning card.
	var fined_coins: int = 0
	var lost_streak: int = 0
	var car_id: String = "vaz2104"
	var car_name: String = ""
	var car_speed_kmh: int = 110
	var outfit: Dictionary = {}


class TaskInfo:
	extends RefCounted

	var id: String
	var title: String
	var description: String
	var room: StringName
	## Office map cell where the player stands to start the task.
	var spot: Vector2i
	var minigame: String
	## Screen-only minigame used when the device lacks the sensors `minigame` needs; empty = none.
	var fallback_minigame: String = ""
	## Minigame settings from the admin panel, e.g. {"steps": 120}.
	var params: Dictionary = {}
	var base_reward: int
	## Final reward: base reward x difficulty multiplier x streak multiplier.
	var reward: int
	## normal | hard | very_hard
	var difficulty: String = "normal"
	var difficulty_multiplier: float = 1.0
	var skippable: bool = false
	var completed: bool
	var skipped: bool
	## Office floor of the task (OfficeFloors id).
	var floor_id: StringName = &"hq"
	## "" | "present_colleague" | "other_department": the server picks a colleague for the task.
	var assignment: String = ""
	## Done by the player, waiting for the colleague to confirm (joint photo).
	var pending: bool = false

	## Completed, skipped or waiting for a colleague: nothing left to do today.
	func is_closed() -> bool:
		return completed or skipped or pending

	## The daily check-in at the reception: always on the list, free of the task limits.
	func is_check_in() -> bool:
		return minigame == "presence_qr"


class TaskResult:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var reward: int = 0
	var balance: int = 0
	## The reward waits for a colleague's confirmation; `partner_name` is who has to confirm.
	var pending: bool = false
	var partner_name: String = ""


class ShopOffer:
	extends RefCounted

	var offer_id: String
	var item_id: String
	var name: String
	var description: String
	var rarity: String
	var icon: int
	var base_price: int
	var price: int
	var discount_percent: int
	var purchased: bool


class ShopState:
	extends RefCounted

	var offers: Array[ShopOffer] = []
	## Unix time (seconds) when the assortment rotates.
	var refresh_at: int = 0


class PurchaseResult:
	extends RefCounted

	enum Status { GRANTED, PENDING_APPROVAL, FAILED }

	var status: Status = Status.FAILED
	var error: String = ""
	var balance: int = 0
	## Promo code or voucher text for instantly granted rewards.
	var voucher: String = ""


class ActionResult:
	extends RefCounted

	var ok: bool = false
	var error: String = ""


class WardrobeItem:
	extends RefCounted

	var slot: String
	var id: String
	var name: String
	var unlocked: bool
	## free | shop | streak
	var unlock_type: String = "free"
	## Shop item id for "shop", number of days for "streak".
	var unlock_value: String = ""


class WardrobeState:
	extends RefCounted

	var items: Array[WardrobeItem] = []
	var outfit: Dictionary = {}
	var streak_days: int = 1


class CarInfo:
	extends RefCounted

	var id: String
	var name: String
	var description: String
	var price: int
	var speed_kmh: int
	var owned: bool
	var selected: bool


class GarageState:
	extends RefCounted

	var cars: Array[CarInfo] = []


class Colleague:
	extends RefCounted

	var user_id: String = ""
	var name: String = ""
	var department: String = ""
	## Avatar template id or AvatarCatalog.CUSTOM.
	var avatar: String = ""
	var status: String = ""
	## Room where the colleague scanned a door code last today; empty when unknown.
	var floor_id: StringName = &"hq"
	var room: StringName = &""
	## In the office now (entered and not left).
	var present: bool = false


class ColleagueResult:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var colleague: Colleague


## One day of the attendance calendar.
class DayRecord:
	extends RefCounted

	var day: int
	var present: bool = false
	## Task titles completed that day with their rewards: [{"title", "reward"}].
	var tasks: Array[Dictionary] = []
	var earned: int = 0


class ProfilePage:
	extends RefCounted

	var profile: Profile
	var best_streak: int = 0
	var office_days_total: int = 0
	var tasks_total: int = 0
	var coins_earned_total: int = 0
	## Oldest first, up to today; covers the calendar range.
	var days: Array[DayRecord] = []
	var today: int = 0
	var has_custom_avatar: bool = false


class InboxItem:
	extends RefCounted

	## penalty | streak_reset | photo_request | photo_confirmed | photo_declined | raffle_win | raffle_lost
	var id: int = 0
	var kind: String = ""
	var created_at: int = 0
	var params: Dictionary = {}
	var read: bool = false
	## For photo_request: pending | confirmed | declined | expired.
	var state: String = ""

	func needs_answer() -> bool:
		return kind == "photo_request" and state == "pending"


class RaffleEntrant:
	extends RefCounted

	var user_id: String = ""
	var name: String = ""
	var avatar: String = ""


class RaffleState:
	extends RefCounted

	enum Phase { OPEN, DRAWN }

	var draw_id: String = ""
	var prize_name: String = ""
	var prize_description: String = ""
	var ticket_price: int = 0
	## Unix time of the draw; the result is shown on that day.
	var draw_at: int = 0
	## Countdown at the moment of the request, so the phone clock does not matter.
	var seconds_to_draw: int = 0
	var phase: Phase = Phase.OPEN
	var entrants: Array[RaffleEntrant] = []
	var has_ticket: bool = false
	## Why the player cannot buy a ticket now; "" when they can.
	var buy_error: String = ""
	var office_days: int = 0
	var min_office_days: int = 0
	var window_days: int = 0
	## SHA-256 of the secret seed, published before the draw; the seed is revealed after it.
	var commitment: String = ""
	var revealed_seed: String = ""
	var winner_id: String = ""
	var winner_name: String = ""
	var is_winner: bool = false


## A notification the client schedules with the OS.
class PlannedNotification:
	extends RefCounted

	var id: int = 0
	## Server time of delivery, and the same as a delay from now (the phone clock may differ).
	var at: int = 0
	var delay_seconds: int = 0
	var kind: String = ""
	var params: Dictionary = {}


## When tasks count today (server/modules/limits.go), for locking them before the player starts.
class TaskSchedule:
	extends RefCounted

	var cooldown_minutes: int = 0
	## Seconds until the next task counts, at the moment of the request; 0 = now.
	var next_task_in: int = 0
	## Office time, "HH:MM".
	var window_start: String = ""
	var window_end: String = ""
	var in_window: bool = true
	## Ticks (ms) when the schedule was received, so the countdown runs on.
	var received_at_ms: int = 0

	func cooldown_left() -> int:
		return maxi(0, next_task_in - (Time.get_ticks_msec() - received_at_ms) / 1000)

	## "" when tasks count now, otherwise the error key that explains why not.
	func lock_reason() -> String:
		if not in_window:
			return "outside_task_window"
		if cooldown_left() > 0:
			return "task_cooldown"
		return ""


## Continuous-play limit (server/modules/play.go).
class PlayStatus:
	extends RefCounted

	## DEFERRED: the limit came during a minigame; the rest starts when it ends.
	enum State { OK, WARNING, DEFERRED, RESTING, BLOCKED }

	var ok: bool = false
	var error: String = ""
	var state: State = State.OK
	var played_seconds: int = 0
	var limit_minutes: int = 0
	var grace_minutes: int = 0
	var rest_minutes: int = 0
	## Seconds left of the grace (WARNING) or of the rest (RESTING), at the moment of the request.
	var seconds_left: int = 0
	var beat_seconds: int = 30
