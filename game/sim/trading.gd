class_name Trading
extends RefCounted
## Buy/sell rules at inns and farms. Prices derive from item `value` in content/items; the
## player's reputation with the merchant's faction nudges them. Merchant stock is a real
## WorldState inventory (finite), but merchants have unlimited pennies: tracking every
## innkeeper's purse would add bookkeeping the game never surfaces.

var _state: Node
var _player: Inventory
var _factions: Factions


func _init(player_inventory: Inventory, factions: Factions = null, state: Node = null) -> void:
	_state = state if state != null else WorldState
	_player = player_inventory
	_factions = factions if factions != null else Factions.new(_state)


func is_tradeable(item_id: String) -> bool:
	if not ItemDB.has_item(item_id) or ItemDB.value_of(item_id) <= 0:
		return false
	return not Tuning.list("trade.unsellable_kinds").has(ItemDB.kind_of(item_id))


## Good standing makes prices lower, bad standing higher, within configured bounds.
func price_multiplier(faction: String) -> float:
	var m: float = 1.0 - _factions.reputation(faction) * Tuning.num("trade.reputation_price_per_point")
	return clampf(m, Tuning.num("trade.price_multiplier_min"), Tuning.num("trade.price_multiplier_max"))


## Per-unit price to buy; at least 1 penny so nothing is free.
func buy_price(item_id: String, faction: String) -> int:
	if not is_tradeable(item_id):
		return 0
	var raw: float = ItemDB.value_of(item_id) * Tuning.num("trade.base_markup") * price_multiplier(faction)
	return maxi(1, ceili(raw))


## Per-unit price when selling to a merchant; the merchant never pays more than it would ask.
func sell_price(item_id: String, faction: String) -> int:
	if not is_tradeable(item_id):
		return 0
	var raw: float = ItemDB.value_of(item_id) * Tuning.num("trade.sell_ratio") / price_multiplier(faction)
	return clampi(maxi(1, floori(raw)), 1, buy_price(item_id, faction))


## Returns {ok, reason, total}.
func buy(merchant_id: String, item_id: String, n: int, faction: String) -> Dictionary:
	var fail: Dictionary = {"ok": false, "reason": "", "total": 0}
	if n <= 0 or not is_tradeable(item_id):
		fail["reason"] = "not_for_sale"
		return fail
	if _state.item_count(merchant_id, item_id) < n:
		fail["reason"] = "out_of_stock"
		return fail
	var total: int = buy_price(item_id, faction) * n
	if _player.money() < total:
		fail["reason"] = "not_enough_money"
		return fail
	if not _player.can_add(item_id, n):
		fail["reason"] = "too_heavy"
		return fail
	_player.spend(total)
	_state.transfer_item(item_id, merchant_id, _player.owner, n)
	return {"ok": true, "reason": "", "total": total}


func sell(merchant_id: String, item_id: String, n: int, faction: String) -> Dictionary:
	var fail: Dictionary = {"ok": false, "reason": "", "total": 0}
	if n <= 0 or not is_tradeable(item_id):
		fail["reason"] = "not_wanted"
		return fail
	if not _player.has(item_id, n):
		fail["reason"] = "not_carrying"
		return fail
	var total: int = sell_price(item_id, faction) * n
	_player.give_to(merchant_id, item_id, n)
	# Coins weigh something; undo the hand-over rather than leave a sale half done.
	if not _player.add_money(total):
		_state.transfer_item(item_id, merchant_id, _player.owner, n)
		fail["reason"] = "too_heavy"
		return fail
	return {"ok": true, "reason": "", "total": total}
