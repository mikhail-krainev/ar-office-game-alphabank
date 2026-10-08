class_name BackendParser
extends RefCounted
## Turns RPC answers of the server module (server/modules) into BackendModels. Missing fields keep
## the model defaults, so an older server never crashes the client.


static func profile(data: Dictionary) -> BackendModels.Profile:
	var result: BackendModels.Profile = BackendModels.Profile.new()
	result.user_id = str(data.get("user_id", ""))
	result.display_name = str(data.get("display_name", ""))
	result.department = str(data.get("department", ""))
	result.status = str(data.get("status", ""))
	result.avatar = str(data.get("avatar", AvatarCatalog.DEFAULT))
	result.balance = int(data.get("balance", 0))
	result.streak_days = int(data.get("streak_days", 0))
	result.present_today = bool(data.get("present_today", false))
	result.in_office = bool(data.get("in_office", false))
	result.multiplier = float(data.get("multiplier", 1.0))
	result.welcome_bonus = int(data.get("welcome_bonus", 0))
	result.fined_coins = int(data.get("fined_coins", 0))
	result.lost_streak = int(data.get("lost_streak", 0))
	result.car_id = str(data.get("car_id", result.car_id))
	result.car_name = str(data.get("car_name", ""))
	result.car_speed_kmh = int(data.get("car_speed_kmh", result.car_speed_kmh))
	result.outfit = outfit(data.get("outfit", {}))
	return result


## The server keeps only what the player chose; defaults fill the rest.
static func outfit(data: Variant) -> Dictionary:
	var result: Dictionary = Outfit.default_outfit()
	if data is Dictionary:
		result.merge(data as Dictionary, true)
	return result


static func task(data: Dictionary) -> BackendModels.TaskInfo:
	var info: BackendModels.TaskInfo = BackendModels.TaskInfo.new()
	info.id = str(data.get("id", ""))
	info.title = str(data.get("title", ""))
	info.description = str(data.get("description", ""))
	info.room = StringName(str(data.get("room", "")))
	info.floor_id = StringName(str(data.get("floor", OfficeFloors.HQ)))
	var spot: Array = data.get("spot", [0, 0]) if data.get("spot") is Array else [0, 0]
	info.spot = Vector2i(int(spot[0]), int(spot[1])) if spot.size() >= 2 else Vector2i.ZERO
	info.minigame = str(data.get("minigame", ""))
	info.fallback_minigame = str(data.get("fallback", ""))
	info.params = data.get("params", {}) if data.get("params") is Dictionary else {}
	info.assignment = str(data.get("assignment", ""))
	info.base_reward = int(data.get("base_reward", 0))
	info.reward = int(data.get("reward", 0))
	info.difficulty = str(data.get("difficulty", "normal"))
	info.difficulty_multiplier = float(data.get("difficulty_multiplier", 1.0))
	info.skippable = bool(data.get("skippable", false))
	info.completed = bool(data.get("completed", false))
	info.skipped = bool(data.get("skipped", false))
	info.pending = bool(data.get("pending", false))
	info.taken = bool(data.get("taken", false))
	return info


static func task_result(data: Dictionary, error: String) -> BackendModels.TaskResult:
	var result: BackendModels.TaskResult = BackendModels.TaskResult.new()
	result.ok = bool(data.get("ok", false))
	result.error = error if not error.is_empty() else str(data.get("error", ""))
	result.reward = int(data.get("reward", 0))
	result.balance = int(data.get("balance", -1))
	result.pending = bool(data.get("pending", false))
	result.partner_name = str(data.get("partner_name", ""))
	return result


static func action(data: Dictionary, error: String) -> BackendModels.ActionResult:
	var result: BackendModels.ActionResult = BackendModels.ActionResult.new()
	result.ok = error.is_empty() and bool(data.get("ok", false))
	result.error = error if not error.is_empty() else str(data.get("error", ""))
	return result


static func purchase(data: Dictionary, error: String) -> BackendModels.PurchaseResult:
	var result: BackendModels.PurchaseResult = BackendModels.PurchaseResult.new()
	match str(data.get("status", "failed")):
		"granted":
			result.status = BackendModels.PurchaseResult.Status.GRANTED
		"pending_approval":
			result.status = BackendModels.PurchaseResult.Status.PENDING_APPROVAL
	result.error = error if not error.is_empty() else str(data.get("error", ""))
	result.balance = int(data.get("balance", -1))
	result.voucher = str(data.get("voucher", ""))
	return result


static func shop(data: Dictionary) -> BackendModels.ShopState:
	var state: BackendModels.ShopState = BackendModels.ShopState.new()
	state.refresh_at = int(data.get("refresh_at", 0))
	for entry: Dictionary in _dictionaries(data.get("offers")):
		var offer: BackendModels.ShopOffer = BackendModels.ShopOffer.new()
		offer.offer_id = str(entry.get("offer_id", ""))
		offer.item_id = str(entry.get("item_id", ""))
		offer.name = str(entry.get("name", ""))
		offer.description = str(entry.get("description", ""))
		offer.rarity = str(entry.get("rarity", "common"))
		offer.icon = int(entry.get("icon", 0))
		offer.base_price = int(entry.get("base_price", 0))
		offer.price = int(entry.get("price", 0))
		offer.discount_percent = int(entry.get("discount_percent", 0))
		offer.purchased = bool(entry.get("purchased", false))
		state.offers.append(offer)
	return state


static func wardrobe(data: Dictionary) -> BackendModels.WardrobeState:
	var state: BackendModels.WardrobeState = BackendModels.WardrobeState.new()
	state.outfit = outfit(data.get("outfit", {}))
	state.streak_days = int(data.get("streak_days", 0))
	for entry: Dictionary in _dictionaries(data.get("items")):
		var item: BackendModels.WardrobeItem = BackendModels.WardrobeItem.new()
		item.slot = str(entry.get("slot", ""))
		item.id = str(entry.get("id", ""))
		item.name = str(entry.get("name", ""))
		item.unlocked = bool(entry.get("unlocked", false))
		item.unlock_type = str(entry.get("unlock_type", "free"))
		item.unlock_value = str(entry.get("unlock_value", ""))
		state.items.append(item)
	return state


static func garage(data: Dictionary) -> BackendModels.GarageState:
	var state: BackendModels.GarageState = BackendModels.GarageState.new()
	for entry: Dictionary in _dictionaries(data.get("cars")):
		state.cars.append(car(entry))
	return state


static func car(entry: Dictionary) -> BackendModels.CarInfo:
	var info: BackendModels.CarInfo = BackendModels.CarInfo.new()
	info.id = str(entry.get("id", ""))
	info.name = str(entry.get("name", ""))
	info.description = str(entry.get("description", ""))
	info.price = int(entry.get("price", 0))
	info.speed_kmh = int(entry.get("speed_kmh", 110))
	info.owned = bool(entry.get("owned", false))
	info.selected = bool(entry.get("selected", false))
	return info


static func colleague(entry: Dictionary) -> BackendModels.Colleague:
	var info: BackendModels.Colleague = BackendModels.Colleague.new()
	info.user_id = str(entry.get("user_id", ""))
	info.name = str(entry.get("name", ""))
	info.department = str(entry.get("department", ""))
	info.avatar = str(entry.get("avatar", ""))
	info.status = str(entry.get("status", ""))
	info.room = StringName(str(entry.get("room", "")))
	info.floor_id = OfficeFloors.floor_of_room(info.room) if info.room != &"" else OfficeFloors.HQ
	info.present = bool(entry.get("present", false))
	return info


static func colleague_result(data: Dictionary, error: String) -> BackendModels.ColleagueResult:
	var result: BackendModels.ColleagueResult = BackendModels.ColleagueResult.new()
	result.ok = error.is_empty() and bool(data.get("ok", false))
	result.error = error if not error.is_empty() else str(data.get("error", ""))
	if data.get("colleague") is Dictionary:
		result.colleague = colleague(data["colleague"])
	return result


static func profile_page(data: Dictionary) -> BackendModels.ProfilePage:
	var page: BackendModels.ProfilePage = BackendModels.ProfilePage.new()
	page.profile = profile(data.get("profile", {}) if data.get("profile") is Dictionary else {})
	page.best_streak = int(data.get("best_streak", 0))
	page.office_days_total = int(data.get("office_days_total", 0))
	page.tasks_total = int(data.get("tasks_total", 0))
	page.coins_earned_total = int(data.get("coins_earned_total", 0))
	page.today = int(data.get("today", 0))
	page.has_custom_avatar = bool(data.get("has_custom_avatar", false))
	for entry: Dictionary in _dictionaries(data.get("days")):
		var record: BackendModels.DayRecord = BackendModels.DayRecord.new()
		record.day = int(entry.get("day", 0))
		record.present = bool(entry.get("present", false))
		record.earned = int(entry.get("earned", 0))
		for line: Dictionary in _dictionaries(entry.get("tasks")):
			record.tasks.append({"title": str(line.get("title", "")), "reward": int(line.get("reward", 0))})
		page.days.append(record)
	return page


static func inbox(data: Dictionary) -> Array[BackendModels.InboxItem]:
	var result: Array[BackendModels.InboxItem] = []
	for entry: Dictionary in _dictionaries(data.get("items")):
		var item: BackendModels.InboxItem = BackendModels.InboxItem.new()
		item.id = int(entry.get("id", 0))
		item.kind = str(entry.get("kind", ""))
		item.created_at = int(entry.get("created_at", 0))
		item.params = entry.get("params", {}) if entry.get("params") is Dictionary else {}
		item.read = bool(entry.get("read", false))
		item.state = str(entry.get("state", ""))
		result.append(item)
	return result


static func raffle(data: Dictionary) -> BackendModels.RaffleState:
	var state: BackendModels.RaffleState = BackendModels.RaffleState.new()
	state.draw_id = str(data.get("draw_id", ""))
	state.prize_name = str(data.get("prize_name", ""))
	state.prize_description = str(data.get("prize_description", ""))
	state.ticket_price = int(data.get("ticket_price", 0))
	state.draw_at = int(data.get("draw_at", 0))
	state.seconds_to_draw = int(data.get("seconds_to_draw", 0))
	state.phase = BackendModels.RaffleState.Phase.DRAWN if bool(data.get("drawn", false)) else BackendModels.RaffleState.Phase.OPEN
	state.has_ticket = bool(data.get("has_ticket", false))
	state.buy_error = str(data.get("buy_error", ""))
	state.office_days = int(data.get("office_days", 0))
	state.min_office_days = int(data.get("min_office_days", 0))
	state.window_days = int(data.get("window_days", 0))
	state.commitment = str(data.get("commitment", ""))
	state.revealed_seed = str(data.get("revealed_seed", ""))
	state.winner_id = str(data.get("winner_id", ""))
	state.winner_name = str(data.get("winner_name", ""))
	state.is_winner = bool(data.get("is_winner", false))
	for entry: Dictionary in _dictionaries(data.get("entrants")):
		var entrant: BackendModels.RaffleEntrant = BackendModels.RaffleEntrant.new()
		entrant.user_id = str(entry.get("user_id", ""))
		entrant.name = str(entry.get("name", ""))
		entrant.avatar = str(entry.get("avatar", ""))
		state.entrants.append(entrant)
	return state


static func notification_plan(data: Dictionary) -> Array[BackendModels.PlannedNotification]:
	var result: Array[BackendModels.PlannedNotification] = []
	for entry: Dictionary in _dictionaries(data.get("notifications")):
		var item: BackendModels.PlannedNotification = BackendModels.PlannedNotification.new()
		item.id = int(entry.get("id", 0))
		item.at = int(entry.get("at", 0))
		item.delay_seconds = int(entry.get("delay_seconds", 0))
		item.kind = str(entry.get("kind", ""))
		item.params = entry.get("params", {}) if entry.get("params") is Dictionary else {}
		result.append(item)
	return result


static func task_schedule(data: Variant) -> BackendModels.TaskSchedule:
	var schedule: BackendModels.TaskSchedule = BackendModels.TaskSchedule.new()
	var entry: Dictionary = data if data is Dictionary else {}
	schedule.cooldown_minutes = int(entry.get("cooldown_minutes", 0))
	schedule.next_task_in = int(entry.get("next_task_in", 0))
	schedule.window_start = str(entry.get("window_start", ""))
	schedule.window_end = str(entry.get("window_end", ""))
	schedule.in_window = bool(entry.get("in_window", true))
	schedule.received_at_ms = Time.get_ticks_msec()
	return schedule


static func play_status(data: Dictionary, error: String) -> BackendModels.PlayStatus:
	var status: BackendModels.PlayStatus = BackendModels.PlayStatus.new()
	status.ok = error.is_empty()
	status.error = error
	var states: Dictionary[String, BackendModels.PlayStatus.State] = {
		"ok": BackendModels.PlayStatus.State.OK,
		"warning": BackendModels.PlayStatus.State.WARNING,
		"deferred": BackendModels.PlayStatus.State.DEFERRED,
		"resting": BackendModels.PlayStatus.State.RESTING,
		"blocked": BackendModels.PlayStatus.State.BLOCKED,
	}
	status.state = states.get(str(data.get("state", "ok")), BackendModels.PlayStatus.State.OK)
	status.played_seconds = int(data.get("played_seconds", 0))
	status.limit_minutes = int(data.get("limit_minutes", 0))
	status.grace_minutes = int(data.get("grace_minutes", 0))
	status.rest_minutes = int(data.get("rest_minutes", 0))
	status.seconds_left = int(data.get("seconds_left", 0))
	status.beat_seconds = maxi(5, int(data.get("beat_seconds", 30)))
	return status


static func facts_state(data: Dictionary, error: String) -> BackendModels.FactsState:
	var result: BackendModels.FactsState = BackendModels.FactsState.new()
	result.ok = error.is_empty()
	result.error = error
	for entry: Dictionary in _dictionaries(data.get("facts")):
		result.facts.append(BackendModels.Fact.new(str(entry.get("text", "")), bool(entry.get("true", false))))
	result.written_today = bool(data.get("today", false))
	result.needed = bool(data.get("needed", false))
	return result


static func facts_answer(data: Dictionary, error: String) -> BackendModels.FactsAnswer:
	var result: BackendModels.FactsAnswer = BackendModels.FactsAnswer.new()
	result.ok = error.is_empty() and bool(data.get("ok", false))
	result.error = error if not error.is_empty() else str(data.get("error", ""))
	result.correct = int(data.get("correct", 0))
	result.truths = bools(data.get("truths"))
	return result


## Booleans of a JSON array; other values are left out.
static func bools(value: Variant) -> Array[bool]:
	var result: Array[bool] = []
	if value is Array:
		for entry: Variant in value:
			if entry is bool:
				result.append(entry)
	return result


static func _dictionaries(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				result.append(entry)
	return result
