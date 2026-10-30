class_name Interaction
extends Node
## Finds the nearest Interactable within reach of the player, shows a prompt and applies the
## built-in effect when E is pressed. Needs only a body to measure from; everything else is optional
## so tests can drive it without UI.

signal prompt_changed(text: String)
signal interacted(item: Interactable)
signal message(text: String)

var body: Node3D
var dialogue_panel: DialoguePanel
var survival: Survival
var inventory: Inventory
var camera_rig: CameraRig

var _current: Interactable
var _prompt: Label


func _ready() -> void:
	if inventory == null:
		inventory = Inventory.new(WorldState.PLAYER_ID)


func current() -> Interactable:
	return _current


func prompt_text() -> String:
	return _current.prompt_text() if _current != null else ""


## The label node is owned by the HUD layer the session builds.
func set_prompt_label(label: Label) -> void:
	_prompt = label
	_refresh_label()


func range_m() -> float:
	return float(Config.get_value("player.interaction.range_m", 2.5))


func find_nearest() -> Interactable:
	if body == null or not is_inside_tree():
		return null
	var items: Array[Interactable] = []
	var positions: Array[Vector3] = []
	var flags: Array[bool] = []
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := node as Interactable
		if it == null or not it.is_inside_tree():
			continue
		items.append(it)
		positions.append(it.global_position)
		flags.append(it.enabled)
	var idx: int = Interactable.pick_nearest(body.global_position, positions, flags, range_m())
	return items[idx] if idx >= 0 else null


func _process(_delta: float) -> void:
	var busy: bool = dialogue_panel != null and dialogue_panel.is_open()
	var nearest: Interactable = null if busy else find_nearest()
	if nearest != _current:
		_current = nearest
		_refresh_label()
		prompt_changed.emit(prompt_text())
	if camera_rig != null:
		var npc_near: bool = _current != null and _current.kind == Interactable.KIND_NPC
		camera_rig.set_shoulder_target(_current if npc_near else null)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		if try_interact():
			get_viewport().set_input_as_handled()


## Uses the current interactable. Returns whether something was used.
func try_interact() -> bool:
	if dialogue_panel != null and dialogue_panel.is_open():
		return false
	var target: Interactable = _current if _current != null else find_nearest()
	if target == null:
		return false
	apply(target)
	return true


func apply(item: Interactable) -> void:
	match item.kind:
		Interactable.KIND_NPC:
			_talk(item)
		Interactable.KIND_BED:
			_sleep(item)
		Interactable.KIND_FOOD:
			_take_food(item)
		Interactable.KIND_WELL:
			message.emit(str(Config.get_value("player.interaction.well_message", "")))
		Interactable.KIND_DOOR:
			item.is_open = not item.is_open
	item.activated.emit(body)
	interacted.emit(item)
	_refresh_label()


func _talk(item: Interactable) -> void:
	if dialogue_panel == null or item.target_id.is_empty():
		return
	if camera_rig != null:
		camera_rig.frame_conversation(item.global_position)
		if not dialogue_panel.closed.is_connected(_on_dialogue_closed):
			dialogue_panel.closed.connect(_on_dialogue_closed)
	dialogue_panel.open(item.target_id)


func _on_dialogue_closed(_npc: String) -> void:
	if camera_rig != null:
		camera_rig.end_conversation()


func _sleep(item: Interactable) -> void:
	if survival == null:
		return
	var hours: float = float(item.payload.get("hours", Config.get_value("player.interaction.sleep_hours", 8.0)))
	survival.sleep(hours, str(item.payload.get("place", "bed")))


func _take_food(item: Interactable) -> void:
	var item_id: String = str(item.payload.get("item", ""))
	var count: int = int(item.payload.get("count", 1))
	if item_id.is_empty() or count <= 0:
		return
	if inventory.add(item_id, count):
		item.enabled = false if bool(item.payload.get("single_use", false)) else item.enabled
		message.emit("Took %d x %s." % [count, str(ItemDB.get_item(item_id).get("name", item_id))])
	else:
		message.emit("You can't carry any more.")


func _refresh_label() -> void:
	if _prompt == null:
		return
	var text: String = prompt_text()
	_prompt.visible = not text.is_empty()
	if not text.is_empty():
		var keys: Array[InputEvent] = InputMap.action_get_events(&"interact") if InputMap.has_action(&"interact") else []
		var key_name: String = keys[0].as_text().get_slice(" (", 0) if not keys.is_empty() else "E"
		_prompt.text = "[%s] %s" % [key_name, text]
