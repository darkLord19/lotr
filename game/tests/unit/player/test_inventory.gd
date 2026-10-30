extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")

var ws: Node
var inv: Inventory


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	inv = Inventory.new("player", ws)


func test_add_uses_world_state_as_truth() -> void:
	assert_true(inv.add("apple", 3))
	assert_eq(ws.item_count("player", "apple"), 3)
	ws.transfer_item("apple", "player", "", 1)
	assert_eq(inv.count("apple"), 2)


func test_weight_limit_is_all_or_nothing() -> void:
	var item_weight: float = ItemDB.weight_of("potatoes")
	var fits: int = int(inv.capacity() / item_weight)
	assert_true(inv.add("potatoes", fits))
	assert_false(inv.add("potatoes", 1), "over the limit")
	assert_eq(inv.count("potatoes"), fits)
	assert_false(inv.can_add("not_an_item", 1))
	assert_almost_eq(inv.total_weight(), fits * item_weight, 0.001)
	assert_true(inv.remove("potatoes", 1))
	assert_true(inv.add("potatoes", 1))


func test_money_counts_toward_weight_and_spends() -> void:
	assert_true(inv.add_money(50))
	assert_eq(inv.money(), 50)
	assert_true(inv.spend(20))
	assert_eq(inv.money(), 30)
	assert_false(inv.spend(31))
	assert_eq(inv.money(), 30)
	assert_gt(inv.total_weight(), 0.0)


func test_give_to_other_owner() -> void:
	inv.add("apple", 2)
	assert_true(inv.give_to("gaffer", "apple", 1))
	assert_eq(ws.item_count("gaffer", "apple"), 1)
	assert_false(inv.give_to("gaffer", "apple", 5))
