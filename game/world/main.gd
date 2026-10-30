class_name Main
extends Node
## Game flow root: main menu -> character creation -> game (and back). It owns the screens and the
## "session" (world scene plus the simulation services that need nodes), and is the only place that
## knows how a load from the menu differs from a load in-game. Systems it creates register
## themselves with SaveSystem, so nothing here reaches into their state.

enum Screen { NONE, MENU, CREATION, GAME }

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/main_menu.tscn")
const CREATION_SCENE: PackedScene = preload("res://ui/char_creation/char_creation.tscn")
const MENU_PAUSE_REASON: StringName = &"main_menu"

## Overridable so tests (and headless runs without terrain data) can skip the 3D world.
var world_scene_path: String = "res://world/world_root.tscn"
var screen: Screen = Screen.NONE
var menu: MainMenu
var pause_menu: PauseMenu
var session: Node

var _screen_node: Node
var _sim: OffscreenSim
var _weather: WeatherDayNight


func _ready() -> void:
	show_main_menu()


func _exit_tree() -> void:
	# Leave the global clock usable if the flow root is torn down (tests, scene changes).
	_drop_session()
	WorldClock.resume(MENU_PAUSE_REASON)


# --- screens ------------------------------------------------------------------

func show_main_menu() -> void:
	_drop_session()
	_clear_screen()
	SaveSystem.autosave_enabled = false
	# The clock must not run while there is no game; the menu stacks its own reason.
	if MENU_PAUSE_REASON not in WorldClock.pause_reasons():
		WorldClock.pause(MENU_PAUSE_REASON)
	menu = MAIN_MENU_SCENE.instantiate()
	menu.new_game_requested.connect(show_char_creation)
	menu.continue_requested.connect(load_and_start)
	menu.load_requested.connect(load_and_start)
	menu.quit_requested.connect(quit_game)
	_set_screen(menu, Screen.MENU)


func show_char_creation() -> void:
	_clear_screen()
	var creation: CharCreation = CREATION_SCENE.instantiate()
	creation.game_started.connect(_on_new_game_started)
	_set_screen(creation, Screen.CREATION)


## Loads a slot from the menu and starts playing it. Returns the load error.
func load_and_start(slot: String) -> Error:
	var err: Error = SaveSystem.load_slot(slot)
	if err != OK:
		push_warning("Main: could not load '%s' (%s)" % [slot, error_string(err)])
		return err
	_start_game()
	return OK


## Load while a game is running: the session's participants are registered, so they restore
## themselves directly.
func load_in_game(slot: String) -> Error:
	var err: Error = SaveSystem.load_slot(slot)
	if err == OK:
		Settings.sync_from_clock()
		pause_menu.close()
	return err


func quit_game() -> void:
	get_tree().quit()


func _on_new_game_started(_result: Dictionary) -> void:
	# NewGame has already reset state/timeline/clock; extras from an earlier load must not leak in.
	SaveSystem.clear_pending_extras()
	_start_game()


func _unhandled_input(event: InputEvent) -> void:
	# Esc in character creation goes back; in the game the pause menu owns it.
	if screen == Screen.CREATION and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		show_main_menu()


# --- session --------------------------------------------------------------------

func _start_game() -> void:
	_clear_screen()
	_build_session()
	Settings.sync_from_clock()
	SaveSystem.autosave_enabled = true
	WorldClock.resume(MENU_PAUSE_REASON)
	pause_menu = PauseMenu.new()
	pause_menu.load_requested.connect(load_in_game)
	pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)
	pause_menu.quit_requested.connect(quit_game)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.name = "MenuLayer"
	layer.add_child(pause_menu)
	session.add_child(layer)
	screen = Screen.GAME


func _on_quit_to_menu() -> void:
	pause_menu.close()
	show_main_menu()


# Order matters: services are added after they are bound, because their _ready registers them
# with SaveSystem and a load from the menu hands them their saved state at that moment.
func _build_session() -> void:
	session = Node.new()
	session.name = "Session"
	add_child(session)
	if ResourceLoader.exists(world_scene_path):
		var world: Node = (load(world_scene_path) as PackedScene).instantiate()
		session.add_child(world)
		_weather = WeatherDayNight.new()
		# Take over the world's own sun and sky rather than creating a second set.
		if "sun" in world:
			_weather.sun = world.get("sun")
		if "world_environment" in world:
			_weather.world_environment = world.get("world_environment")
		session.add_child(_weather)
	var graph := RoadGraph.new()
	graph.load_region()
	_sim = OffscreenSim.new()
	_sim.bind(WorldClock, WorldState, Timeline, graph)
	_sim.load_tracks()
	session.add_child(_sim)
	var rumours := RumourNetwork.new()
	rumours.graph = graph
	session.add_child(rumours)


func _drop_session() -> void:
	if session != null:
		# Out of the tree now (so services stop ticking and unregister from SaveSystem), freed
		# later: this can be called from a button that lives inside the session.
		remove_child(session)
		session.queue_free()
		session = null
		_sim = null
		_weather = null
		pause_menu = null
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _set_screen(node: Node, which: Screen) -> void:
	_screen_node = node
	add_child(node)
	screen = which


func _clear_screen() -> void:
	if _screen_node != null:
		_screen_node.queue_free()
		_screen_node = null
	menu = null
