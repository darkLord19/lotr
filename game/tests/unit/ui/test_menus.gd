extends GutTest
## Menu screens and the Main game flow, driven through their public API (no real input).

const DIR: String = "user://test_saves_menus"
const SETTINGS_PATH: String = "user://test_settings_menus.json"

var saved_dir: String
var saved_autosave: bool
var saved_settings_path: String
var saved_settings: Dictionary
var saved_now: int
var saved_mode: StringName
var saved_scale: float


func before_each() -> void:
	saved_dir = SaveSystem.save_dir
	saved_autosave = SaveSystem.autosave_enabled
	saved_settings_path = Settings.path
	saved_settings = Settings.values.duplicate()
	saved_now = WorldClock.now
	saved_mode = WorldClock.mode
	saved_scale = WorldClock.time_scale
	SaveSystem.save_dir = DIR
	Settings.path = SETTINGS_PATH
	_wipe()
	SaveSystem.clear_pending_extras()


func after_each() -> void:
	_wipe()
	DirAccess.remove_absolute(SETTINGS_PATH)
	SaveSystem.save_dir = saved_dir
	SaveSystem.autosave_enabled = saved_autosave
	Settings.path = saved_settings_path
	Settings.values = saved_settings
	WorldClock.now = saved_now
	WorldClock.set_mode(saved_mode)
	WorldClock.time_scale = saved_scale
	WorldState.reset()
	WorldState.poi_info = {}
	Timeline.deserialise({})
	get_tree().paused = false


func _wipe() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


func _button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n
	return null


func _start_main() -> Main:
	var m := Main.new()
	m.world_scene_path = ""  # no 3D world in unit tests
	add_child_autofree(m)
	return m


func _start_new_game(m: Main) -> void:
	m.show_char_creation()
	var creation: CharCreation = m._screen_node
	creation.choose_race("hobbit")
	creation.confirm()


func test_boot_shows_main_menu_with_clock_held() -> void:
	var m: Main = _start_main()
	assert_eq(m.screen, Main.Screen.MENU)
	assert_true(WorldClock.is_paused(), "no game running, no time passing")
	assert_true(_button(m.menu, "Continue").disabled, "nothing to continue yet")
	assert_true(_button(m.menu, "Load Game").disabled)
	assert_false(_button(m.menu, "New Game").disabled)


func test_continue_enabled_once_a_save_exists() -> void:
	var m: Main = _start_main()
	SaveSystem.save("slot_1")
	m.menu.refresh()
	assert_false(_button(m.menu, "Continue").disabled)
	assert_false(_button(m.menu, "Load Game").disabled)


func test_new_game_flow_builds_session_and_pause_menu() -> void:
	var m: Main = _start_main()
	_start_new_game(m)
	assert_eq(m.screen, Main.Screen.GAME)
	assert_true(WorldState.has_entity(WorldState.PLAYER_ID))
	assert_true(SaveSystem.autosave_enabled)
	assert_false(WorldClock.is_paused(), "the world runs once the game starts")
	assert_true("rumour_network" in SaveSystem.participant_keys())
	assert_true("offscreen_sim" in SaveSystem.participant_keys())
	# Esc menu holds the clock and releases it.
	m.pause_menu.open()
	assert_true(WorldClock.is_paused())
	m.pause_menu.close()
	assert_false(WorldClock.is_paused())
	m.show_main_menu()
	assert_eq(m.screen, Main.Screen.MENU)
	assert_false(SaveSystem.autosave_enabled)
	assert_true(WorldClock.is_paused())
	await get_tree().process_frame
	assert_false("rumour_network" in SaveSystem.participant_keys(), "session services unregistered")


func test_pause_menu_save_then_main_menu_continue_restores() -> void:
	var m: Main = _start_main()
	_start_new_game(m)
	WorldClock.advance(300)
	WorldState.set_flag("menu_test_marker", 7)
	var picker := SlotPicker.new(SlotPicker.Mode.SAVE)
	add_child_autofree(picker)
	assert_eq(picker.slots().size(), SaveSystem.manual_slots().size(), "save mode lists manual slots only")
	(picker.find_child("slot_2", true, false) as Button).pressed.emit()
	assert_true(FileAccess.file_exists(SaveSystem.slot_path("slot_2")))
	var saved_clock: int = WorldClock.now

	m.show_main_menu()
	WorldState.reset()
	WorldClock.now = 0
	assert_false(_button(m.menu, "Continue").disabled)
	assert_eq(m.load_and_start("slot_2"), OK)
	assert_eq(m.screen, Main.Screen.GAME)
	assert_eq(WorldClock.now, saved_clock)
	assert_eq(WorldState.get_flag("menu_test_marker"), 7)
	assert_false(WorldClock.is_paused())


func test_load_picker_lists_autosaves_and_disables_empty_slots() -> void:
	SaveSystem.save("slot_1")
	SaveSystem.autosave()
	var picker := SlotPicker.new(SlotPicker.Mode.LOAD)
	add_child_autofree(picker)
	var chosen: Array[String] = []
	picker.slot_chosen.connect(func(s: String) -> void: chosen.append(s))
	assert_eq(picker.slots().size(), SaveSystem.manual_slots().size() + SaveSystem.autosave_slots().size())
	assert_false((picker.find_child("slot_1", true, false) as Button).disabled)
	assert_true((picker.find_child("slot_2", true, false) as Button).disabled)
	assert_false((picker.find_child("autosave_1", true, false) as Button).disabled)
	(picker.find_child("autosave_1", true, false) as Button).pressed.emit()
	assert_eq(chosen, ["autosave_1"])


func test_settings_menu_controls_drive_settings() -> void:
	var menu := SettingsMenu.new()
	add_child_autofree(menu)
	var checks: Array = menu.find_children("*", "CheckBox", true, false)
	for c: CheckBox in checks:
		if c.text == "Mode B":
			c.button_pressed = true
	assert_eq(Settings.get_value("time_mode"), "B")
	assert_eq(WorldClock.mode, &"B", "applies live")
	var sliders: Array = menu.find_children("*", "HSlider", true, false)
	assert_eq(sliders.size(), 3)
	(sliders[0] as HSlider).value = 2.0  # clock speed
	assert_almost_eq(WorldClock.time_scale, 2.0, 0.001)
	var quality: OptionButton = menu.find_children("*", "OptionButton", true, false)[0]
	quality.select(0)
	quality.item_selected.emit(0)
	assert_eq(Settings.get_value("quality"), "low")
	var done: Array[bool] = []
	menu.closed.connect(func() -> void: done.append(true))
	_button(menu, "Back").pressed.emit()
	assert_eq(done.size(), 1)
	assert_true(FileAccess.file_exists(SETTINGS_PATH), "closing persists")


func test_pause_menu_load_request_is_forwarded() -> void:
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	var asked: Array[String] = []
	pm.load_requested.connect(func(s: String) -> void: asked.append(s))
	SaveSystem.save("slot_3")
	pm.open()
	_button(pm, "Load Game").pressed.emit()
	var picker: SlotPicker = pm.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is SlotPicker)[0]
	(picker.find_child("slot_3", true, false) as Button).pressed.emit()
	assert_eq(asked, ["slot_3"])
	pm.close()
	assert_false(WorldClock.is_paused())


func test_pause_menu_frees_the_cursor_when_it_opens() -> void:
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pm.open()
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "PlayerSession does not run while paused, so the menu must release the mouse itself")
	pm.close()
