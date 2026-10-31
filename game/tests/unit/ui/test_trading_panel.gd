extends GutTest

var panel: TradingPanel
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	for r in WorldClock.pause_reasons():
		WorldClock.resume(r)
	WorldState.reset()
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", Vector3.ZERO, "eriador_west")
	WorldState.spawn_entity("merchant_bob", "npc", Vector3.ZERO, "eriador_west")
	WorldState.transfer_item("apple", "", "merchant_bob", 5)
	WorldState.transfer_item("pipe_weed", "", WorldState.PLAYER_ID, 2)
	var inv := Inventory.new(WorldState.PLAYER_ID)
	inv.add_money(50)
	panel = TradingPanel.new()
	add_child_autofree(panel)


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now
	for r in WorldClock.pause_reasons():
		WorldClock.resume(r)


func test_initial_state_hidden() -> void:
	assert_false(panel.visible)
	assert_false(panel.is_open())
	assert_false(WorldClock.is_paused())


func test_open_populates_stock_and_pauses() -> void:
	panel.open("merchant_bob", "Bob the Merchant", "shire")
	assert_true(panel.visible)
	assert_true(panel.is_open())
	assert_true(WorldClock.is_paused())
	assert_has(WorldClock.pause_reasons(), TradingPanel.PAUSE_REASON)
	assert_string_contains(panel._title.text, "Bob the Merchant")

	# Stock listed
	assert_gt(panel._buy_box.get_child_count(), 0)
	assert_gt(panel._sell_box.get_child_count(), 0)

	panel.close()
	assert_false(panel.visible)
	assert_false(WorldClock.is_paused())


func test_buy_and_sell_buttons_trade_items() -> void:
	panel.open("merchant_bob", "Bob the Merchant", "shire")
	var initial_money: int = panel.inventory.money()
	var initial_apples: int = WorldState.item_count(WorldState.PLAYER_ID, "apple")

	# Find Buy button for apple
	var buy_row: HBoxContainer = panel._buy_box.get_child(0) as HBoxContainer
	assert_not_null(buy_row)
	var buy_btn: Button = buy_row.get_child(1) as Button
	assert_not_null(buy_btn)
	assert_false(buy_btn.disabled)

	buy_btn.pressed.emit()
	assert_eq(WorldState.item_count(WorldState.PLAYER_ID, "apple"), initial_apples + 1)
	assert_lt(panel.inventory.money(), initial_money)
