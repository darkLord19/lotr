extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")

var ws: Node
var inv: Inventory
var factions: Factions
var trade: Trading


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	inv = Inventory.new("player", ws)
	factions = Factions.new(ws)
	trade = Trading.new(inv, factions, ws)
	ws.transfer_item("cider_jug", "", "innkeeper", 5)


func test_prices_derive_from_item_value() -> void:
	var buy: int = trade.buy_price("cider_jug", "bree")
	assert_gte(buy, ItemDB.value_of("cider_jug"))
	assert_lte(trade.sell_price("cider_jug", "bree"), buy, "merchant never pays more than it asks")
	assert_eq(trade.buy_price("crickhollow_key", "bree"), 0, "keys are not trade goods")


func test_reputation_moves_prices_within_bounds() -> void:
	var neutral: int = trade.buy_price("elven_bread", "bree")
	factions.change_reputation("bree", 100)
	assert_lt(trade.buy_price("elven_bread", "bree"), neutral)
	factions.change_reputation("bree", -200)
	assert_gt(trade.buy_price("elven_bread", "bree"), neutral)
	assert_lte(trade.price_multiplier("bree"), Tuning.num("trade.price_multiplier_max"))


func test_buy_moves_goods_and_money() -> void:
	inv.add_money(20)
	var price: int = trade.buy_price("cider_jug", "bree")
	var r: Dictionary = trade.buy("innkeeper", "cider_jug", 2, "bree")
	assert_true(r["ok"])
	assert_eq(r["total"], price * 2)
	assert_eq(inv.count("cider_jug"), 2)
	assert_eq(ws.item_count("innkeeper", "cider_jug"), 3)
	assert_eq(inv.money(), 20 - price * 2)


func test_buy_failures_change_nothing() -> void:
	assert_eq(trade.buy("innkeeper", "cider_jug", 1, "bree")["reason"], "not_enough_money")
	inv.add_money(1000)
	assert_eq(trade.buy("innkeeper", "cider_jug", 9, "bree")["reason"], "out_of_stock")
	assert_eq(trade.buy("innkeeper", "crickhollow_key", 1, "bree")["reason"], "not_for_sale")
	assert_eq(inv.count("cider_jug"), 0)
	assert_eq(inv.money(), 1000)


func test_sell_pays_pennies() -> void:
	inv.add("apple", 4)
	var r: Dictionary = trade.sell("innkeeper", "apple", 3, "bree")
	assert_true(r["ok"])
	assert_eq(inv.count("apple"), 1)
	assert_eq(inv.money(), r["total"])
	assert_eq(ws.item_count("innkeeper", "apple"), 3)
	assert_eq(trade.sell("innkeeper", "apple", 2, "bree")["reason"], "not_carrying")
	assert_eq(trade.sell("innkeeper", "crickhollow_key", 1, "bree")["reason"], "not_wanted")
