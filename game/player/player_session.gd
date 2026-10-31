class_name PlayerSession
extends Node
## Builds everything the player needs inside a world: the body, camera rig, interaction, survival
## rules and the HUD layer (prompt, inventory, journal, dialogue panel, dev console). Main adds one
## of these after the world; it needs only the world's `terrain` and sets `focus_node` so terrain
## streams around the player.

const JOURNAL_SCENE: PackedScene = preload("res://ui/journal/journal.tscn")
const DIALOGUE_SCENE: PackedScene = preload("res://ui/dialogue/dialogue_panel.tscn")
const HUD_LAYER: int = 5
const MESSAGE_SECONDS: float = 3.0

var world: Node3D
var controller: PlayerController
var rig: CameraRig
var interaction: Interaction
var survival: Survival
var soft_failure: SoftFailure
var inventory_panel: InventoryPanel
var journal: Journal
var dialogue: DialoguePanel
var map_screen: MapScreen
var trading_panel: TradingPanel
var console: DebugConsole
var hud: HUD
var layer: CanvasLayer

var _message: Label
var _message_left: float = 0.0


func _ready() -> void:
	InputSetup.apply()
	survival = Survival.new()
	soft_failure = SoftFailure.new()
	_build_body()
	_build_hud()
	_build_interaction()
	if "focus_node" in world:
		world.set("focus_node", controller)
	# Registered last so the body's first state read sees the final entity (new game or load).
	controller.read_state()


func _exit_tree() -> void:
	if survival != null:
		survival.detach()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_body() -> void:
	var data: Dictionary = WorldState.get_entity(WorldState.PLAYER_ID).get("data", {})
	var look: Dictionary = data.get("appearance", {})
	controller = PlayerController.new()
	controller.name = "Player"
	controller.survival = survival
	controller.soft_failure = soft_failure
	if world != null and "terrain" in world:
		controller.terrain = world.get("terrain")
	controller.configure(str(data.get("race", PlayerController.cfg("default_race", "man"))), str(look.get("palette", "")))
	rig = CameraRig.new()
	rig.name = "CameraRig"
	controller.camera_rig = rig
	add_child(controller)
	controller.add_child(rig)
	rig.follow(controller, controller.body_height())


func _build_hud() -> void:
	layer = CanvasLayer.new()
	layer.layer = HUD_LAYER
	layer.name = "PlayerHud"
	add_child(layer)
	_message = Label.new()
	_message.add_theme_font_size_override("font_size", int(PlayerController.cfg("interaction.prompt_font_size", 28)))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y = 80.0
	_message.hide()
	layer.add_child(_message)
	hud = HUD.new()
	hud.survival = survival
	layer.add_child(hud)
	inventory_panel = InventoryPanel.new()
	layer.add_child(inventory_panel)
	journal = JOURNAL_SCENE.instantiate()
	layer.add_child(journal)
	dialogue = DIALOGUE_SCENE.instantiate()
	layer.add_child(dialogue)
	map_screen = MapScreen.new()
	layer.add_child(map_screen)
	trading_panel = TradingPanel.new()
	layer.add_child(trading_panel)
	if DebugConsole.available():
		console = DebugConsole.new()
		console.player = controller
		layer.add_child(console)


func _build_interaction() -> void:
	var prompt := Label.new()
	prompt.add_theme_font_size_override("font_size", int(PlayerController.cfg("interaction.prompt_font_size", 28)))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y = -float(PlayerController.cfg("interaction.prompt_bottom_margin_px", 120))
	prompt.hide()
	layer.add_child(prompt)
	interaction = Interaction.new()
	interaction.body = controller
	interaction.dialogue_panel = dialogue
	interaction.survival = survival
	interaction.camera_rig = rig
	interaction.message.connect(show_message)
	add_child(interaction)
	interaction.set_prompt_label(prompt)


func show_message(text: String) -> void:
	_message.text = text
	_message.show()
	_message_left = MESSAGE_SECONDS


## True while a menu, panel or dialogue owns the mouse and keyboard.
func ui_blocking() -> bool:
	return dialogue.is_open() or journal.visible or inventory_panel.visible \
			or (map_screen != null and map_screen.visible) \
			or (trading_panel != null and trading_panel.visible) \
			or (console != null and console.visible) or get_tree().paused


func _process(delta: float) -> void:
	var blocked: bool = ui_blocking()
	controller.input_enabled = not blocked
	rig.input_enabled = not blocked
	var want: Input.MouseMode = Input.MOUSE_MODE_VISIBLE if blocked else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.hide()
