class_name TradingPanel
extends Control
## Trading UI at inns and farms: buy from merchant stock or sell items from the player's pack.
## Prices derive from ItemDB and the player's reputation with the merchant's faction.

const PAUSE_REASON: StringName = &"trading"
const TEXT_COLOR: Color = Color(0.93, 0.9, 0.8)
const SUBTEXT_COLOR: Color = Color(0.7, 0.72, 0.62)
const WIDTH: float = 780.0

var inventory: Inventory
var factions: Factions
var trading: Trading

var merchant_id: String = ""
var merchant_name: String = ""
var faction: String = ""

var _title: Label
var _status: Label
var _buy_box: VBoxContainer
var _sell_box: VBoxContainer
var _footer: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if inventory == null:
		inventory = Inventory.new(WorldState.PLAYER_ID)
	if factions == null:
		factions = Factions.new(WorldState)
	trading = Trading.new(inventory, factions, WorldState)
	_build()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open(m_id: String, m_name: String, m_faction: String = "") -> void:
	merchant_id = m_id
	merchant_name = m_name if not m_name.is_empty() else NPCContent.prettify(m_id)
	faction = m_faction
	WorldClock.pause(PAUSE_REASON)
	refresh()
	show()


func close() -> void:
	WorldClock.resume(PAUSE_REASON)
	hide()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _title != null:
		_title.text = "Trade with %s" % merchant_name
	if _status != null:
		var mult: float = trading.price_multiplier(faction) if trading != null else 1.0
		_status.text = "Standing with %s: x%.2f price rate" % [faction if not faction.is_empty() else "local folk", mult]

	# Rebuild buy list
	for c in _buy_box.get_children():
		c.queue_free()
	var stock: Dictionary = WorldState.inventories.get(merchant_id, {})
	var buy_items: Array = stock.keys()
	buy_items.sort()
	var has_buy: bool = false
	for it: String in buy_items:
		var count: int = int(stock[it])
		if count <= 0 or not trading.is_tradeable(it):
			continue
		has_buy = true
		_add_buy_row(it, count)
	if not has_buy:
		_buy_box.add_child(_label("Nothing for sale.", SUBTEXT_COLOR))

	# Rebuild sell list
	for c in _sell_box.get_children():
		c.queue_free()
	var pack: Dictionary = inventory.contents()
	var sell_items: Array = pack.keys()
	sell_items.sort()
	var has_sell: bool = false
	for it: String in sell_items:
		var count: int = int(pack[it])
		if count <= 0 or not trading.is_tradeable(it):
			continue
		has_sell = true
		_add_sell_row(it, count)
	if not has_sell:
		_sell_box.add_child(_label("Nothing to sell.", SUBTEXT_COLOR))

	if _footer != null:
		_footer.text = "Pennies: %d   |   Weight: %.1f / %.1f" % [
			inventory.money(), inventory.total_weight(), inventory.capacity()
		]


func _add_buy_row(item_id: String, stock_count: int) -> void:
	var row := HBoxContainer.new()
	var price: int = trading.buy_price(item_id, faction)
	var name: String = str(ItemDB.get_item(item_id).get("name", item_id))
	var desc := _label("%s (x%d) - %d p" % [name, stock_count, price], TEXT_COLOR)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)

	var btn := Button.new()
	btn.text = "Buy"
	btn.disabled = inventory.money() < price or not inventory.can_add(item_id, 1)
	btn.pressed.connect(func() -> void:
		trading.buy(merchant_id, item_id, 1, faction)
		refresh()
	)
	row.add_child(btn)
	_buy_box.add_child(row)


func _add_sell_row(item_id: String, pack_count: int) -> void:
	var row := HBoxContainer.new()
	var price: int = trading.sell_price(item_id, faction)
	var name: String = str(ItemDB.get_item(item_id).get("name", item_id))
	var desc := _label("%s (x%d) - %d p" % [name, pack_count, price], TEXT_COLOR)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)

	var btn := Button.new()
	btn.text = "Sell"
	btn.pressed.connect(func() -> void:
		trading.sell(merchant_id, item_id, 1, faction)
		refresh()
	)
	row.add_child(btn)
	_sell_box.add_child(row)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuKit.backdrop(self, MenuKit.SCRIM_COLOR)
	var box: VBoxContainer = MenuKit.panel(self, WIDTH)

	if ResourceLoader.exists("res://assets/ui/inventory_panel.png"):
		var tex: Texture2D = load("res://assets/ui/inventory_panel.png") as Texture2D
		if tex != null:
			var pc: PanelContainer = box.get_parent() as PanelContainer
			if pc != null:
				var st := StyleBoxTexture.new()
				st.texture = tex
				st.set_content_margin_all(MenuKit.PANEL_MARGIN)
				pc.add_theme_stylebox_override("panel", st)

	_title = MenuKit.heading("Trading")
	box.add_child(_title)

	_status = _label("", SUBTEXT_COLOR)
	box.add_child(_status)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	box.add_child(cols)

	# Left: Buy
	var buy_vbox := VBoxContainer.new()
	buy_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(buy_vbox)
	buy_vbox.add_child(MenuKit.label("Merchant Wares (Buy)", MenuKit.FONT_SIZE, MenuKit.ACCENT_COLOR))
	var buy_scroll := ScrollContainer.new()
	buy_scroll.custom_minimum_size = Vector2(0, 240)
	buy_vbox.add_child(buy_scroll)
	_buy_box = VBoxContainer.new()
	_buy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_scroll.add_child(_buy_box)

	# Right: Sell
	var sell_vbox := VBoxContainer.new()
	sell_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(sell_vbox)
	sell_vbox.add_child(MenuKit.label("Your Pack (Sell)", MenuKit.FONT_SIZE, MenuKit.ACCENT_COLOR))
	var sell_scroll := ScrollContainer.new()
	sell_scroll.custom_minimum_size = Vector2(0, 240)
	sell_vbox.add_child(sell_scroll)
	_sell_box = VBoxContainer.new()
	_sell_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_scroll.add_child(_sell_box)

	_footer = _label("", MenuKit.ACCENT_COLOR)
	box.add_child(_footer)

	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", MenuKit.FONT_SIZE - 4)
	l.add_theme_color_override("font_color", color)
	return l
