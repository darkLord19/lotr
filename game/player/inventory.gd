class_name Inventory
extends RefCounted
## A weight-limited view over WorldState.inventories. It stores nothing itself, so the save file
## and every other system see the same counts.

# Float sums of item weights drift; without a tolerance a full pack could refuse an exact fit.
const EPSILON: float = 0.0001

var owner: String
var _state: Node


func _init(owner_id: String = "", state: Node = null) -> void:
	owner = owner_id if owner_id != "" else WorldState.PLAYER_ID
	_state = state if state != null else WorldState


func count(item_id: String) -> int:
	return _state.item_count(owner, item_id)


func has(item_id: String, n: int = 1) -> bool:
	return count(item_id) >= n


func capacity() -> float:
	return Tuning.num("inventory.carry_limit")


func total_weight() -> float:
	var total: float = 0.0
	for item_id: String in _state.inventories.get(owner, {}):
		total += ItemDB.weight_of(item_id) * count(item_id)
	return total


func can_add(item_id: String, n: int = 1) -> bool:
	if n <= 0 or not ItemDB.has_item(item_id):
		return false
	return total_weight() + ItemDB.weight_of(item_id) * n <= capacity() + EPSILON


## All-or-nothing: a partial stack would make "you picked up 2 of 3" states the UI must explain.
func add(item_id: String, n: int = 1) -> bool:
	if not can_add(item_id, n):
		return false
	return _state.transfer_item(item_id, "", owner, n)


## Consumes the items (they leave the world).
func remove(item_id: String, n: int = 1) -> bool:
	return _state.transfer_item(item_id, owner, "", n)


func give_to(other_owner: String, item_id: String, n: int = 1) -> bool:
	if other_owner == "":
		return false
	return _state.transfer_item(item_id, owner, other_owner, n)


func money() -> int:
	return count(Tuning.text("inventory.money_item"))


## Coins weigh something, so a purse can be refused just like any other loot.
func add_money(pennies: int) -> bool:
	return add(Tuning.text("inventory.money_item"), pennies)


func spend(pennies: int) -> bool:
	return remove(Tuning.text("inventory.money_item"), pennies)


## Item ids with counts, for the future UI.
func contents() -> Dictionary:
	return (_state.inventories.get(owner, {}) as Dictionary).duplicate()

