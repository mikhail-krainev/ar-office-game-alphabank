class_name BackendHome
extends Node
## Server API of the player's home (Backend.home, server/modules/home.go): apartments, palettes and
## interior items with what the player owns, and the look of the current apartment. Prices, copies
## and ownership are decided by the server; the client only checks where an item fits on the map.
## Works outside the office network too.

const KIND_APARTMENT: String = "apartment"
const KIND_PALETTE: String = "palette"
const KIND_ITEM: String = "item"
const ITEM_FURNITURE: String = "furniture"
const ITEM_POSTER: String = "poster"


class Apartment:
	extends RefCounted

	var id: String
	var name: String
	var description: String
	var area: int
	var price: int
	var palette: String
	var owned: bool
	var current: bool


class PaletteInfo:
	extends RefCounted

	var id: String
	var name: String
	var price: int
	var owned: bool


class Item:
	extends RefCounted

	var id: String
	var name: String
	## ITEM_FURNITURE (floor, rugs too) or ITEM_POSTER (wall).
	var kind: String
	var price: int
	var owned: int
	## Copies standing in the other apartments.
	var elsewhere: int


class Placed:
	extends RefCounted

	var item: String
	var cell: Vector2i

	func _init(p_item: String, p_cell: Vector2i) -> void:
		item = p_item
		cell = p_cell


class State:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var apartments: Array[Apartment] = []
	var palettes: Array[PaletteInfo] = []
	var items: Array[Item] = []
	var apartment: String = ""
	var palette: String = ""
	var placed: Array[Placed] = []
	var max_owned: int = 0

	func find_apartment(id: String) -> Apartment:
		for entry: Apartment in apartments:
			if entry.id == id:
				return entry
		return null

	func find_item(id: String) -> Item:
		for entry: Item in items:
			if entry.id == id:
				return entry
		return null

	## Copies of `id` the player can still put into the current apartment.
	func free_copies(id: String) -> int:
		var entry: Item = find_item(id)
		if entry == null:
			return 0
		var here: int = 0
		for placement: Placed in placed:
			if placement.item == id:
				here += 1
		return entry.owned - entry.elsewhere - here


class Purchase:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var balance: int = -1
	var state: State


var _backend: BackendService


func _init(backend: BackendService) -> void:
	name = "Home"
	_backend = backend


## The trip from home: the office part of the game is open, the player is in the office Wi-Fi (the
## server says so). Outside it the call fails with office_network_required, which PlayTime shows
## only over the office scene.
func office_open() -> bool:
	var result: ServerSession.RpcResult = await _backend.call_rpc("office_access")
	return result.ok


func get_home() -> State:
	var response: ServerSession.RpcResult = await _backend.call_rpc("get_home")
	var state: State = parse_state(response.data)
	state.ok = response.ok
	state.error = response.error
	return state


## `kind`: KIND_APARTMENT, KIND_PALETTE or KIND_ITEM.
func buy(kind: String, id: String) -> Purchase:
	var payload: Dictionary = {"kind": kind, "id": id, "operation_key": _backend.operation_key()}
	var response: ServerSession.RpcResult = await _backend.call_rpc("buy_home", payload)
	var result: Purchase = Purchase.new()
	result.ok = response.ok and str(response.data.get("status", "")) == "granted"
	result.error = response.error if not response.error.is_empty() else str(response.data.get("error", ""))
	result.balance = int(response.data.get("balance", -1))
	if response.data.get("home") is Dictionary:
		result.state = parse_state(response.data["home"])
	_backend.apply_balance(result.balance)
	return result


## Moves into `apartment` (owned) and sets its palette and items. Resolves to the new state, or one
## with `ok` false and the server's error.
func save(apartment: String, palette: String, placed: Array[Placed]) -> State:
	var items: Array[Dictionary] = []
	for placement: Placed in placed:
		items.append({"item": placement.item, "x": placement.cell.x, "y": placement.cell.y})
	var payload: Dictionary = {"apartment": apartment, "palette": palette, "placed": items}
	var response: ServerSession.RpcResult = await _backend.call_rpc("save_home", payload)
	var ok: bool = response.ok and bool(response.data.get("ok", false))
	var state: State = parse_state(response.data.get("home", {}) if response.data.get("home") is Dictionary else {})
	state.ok = ok
	state.error = response.error if not response.error.is_empty() else str(response.data.get("error", ""))
	return state


## Moves into the owned `apartment`, which keeps its own look.
func move(apartment: String) -> State:
	var response: ServerSession.RpcResult = await _backend.call_rpc("save_home", {"apartment": apartment})
	var state: State = parse_state(response.data.get("home", {}) if response.data.get("home") is Dictionary else {})
	state.ok = response.ok and bool(response.data.get("ok", false))
	state.error = response.error if not response.error.is_empty() else str(response.data.get("error", ""))
	return state


static func parse_state(data: Dictionary) -> State:
	var state: State = State.new()
	state.ok = true
	for entry: Variant in data.get("apartments", []):
		if entry is Dictionary:
			var apartment: Apartment = Apartment.new()
			apartment.id = str(entry.get("id", ""))
			apartment.name = str(entry.get("name", ""))
			apartment.description = str(entry.get("description", ""))
			apartment.area = int(entry.get("area", 0))
			apartment.price = int(entry.get("price", 0))
			apartment.palette = str(entry.get("palette", ""))
			apartment.owned = bool(entry.get("owned", false))
			apartment.current = bool(entry.get("current", false))
			state.apartments.append(apartment)
	for entry: Variant in data.get("palettes", []):
		if entry is Dictionary:
			var palette: PaletteInfo = PaletteInfo.new()
			palette.id = str(entry.get("id", ""))
			palette.name = str(entry.get("name", ""))
			palette.price = int(entry.get("price", 0))
			palette.owned = bool(entry.get("owned", false))
			state.palettes.append(palette)
	for entry: Variant in data.get("items", []):
		if entry is Dictionary:
			var item: Item = Item.new()
			item.id = str(entry.get("id", ""))
			item.name = str(entry.get("name", ""))
			item.kind = str(entry.get("kind", ITEM_FURNITURE))
			item.price = int(entry.get("price", 0))
			item.owned = int(entry.get("owned", 0))
			item.elsewhere = int(entry.get("elsewhere", 0))
			state.items.append(item)
	state.apartment = str(data.get("apartment", ""))
	state.max_owned = int(data.get("max_owned", 0))
	var decor: Dictionary = data.get("decor", {}) if data.get("decor") is Dictionary else {}
	state.palette = str(decor.get("palette", ""))
	for entry: Variant in decor.get("placed", []):
		if entry is Dictionary:
			state.placed.append(Placed.new(str(entry.get("item", "")), Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))))
	return state
