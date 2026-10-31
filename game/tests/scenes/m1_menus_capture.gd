extends Control
## Capture scene for tools/capture.sh: shows one menu screen. Pick with --stage=main|settings|pause|load
## after the `--` separator. `pause` and `load` sit over a backdrop (add --world for the 3D world).
## Example: tools/capture.sh res://tests/scenes/m1_menus_capture.tscn out.png --stage=settings --after=1

const WORLD_SCENE: String = "res://world/world_root.tscn"
const SAMPLE_SLOTS: Array[String] = ["slot_1", "slot_3"]


func _ready() -> void:
	var stage: String = "main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr("--stage=".length())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	match stage:
		"main":
			_sample_saves()
			add_child((load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate())
		"settings":
			MenuKit.backdrop(self, MenuKit.BG_COLOR)
			add_child(SettingsMenu.new())
		"load":
			_world()
			_sample_saves()
			add_child(SlotPicker.new(SlotPicker.Mode.LOAD))
		_:
			_world()
			var pm := PauseMenu.new()
			add_child(pm)
			pm.open()


func _world() -> void:
	# The 3D world is very slow under software rendering, so it is opt-in (--world).
	if not OS.get_cmdline_user_args().has("--world") or not ResourceLoader.exists(WORLD_SCENE):
		MenuKit.backdrop(self, MenuKit.BG_COLOR)
		return
	var holder := SubViewportContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.stretch = true
	var vp := SubViewport.new()
	vp.add_child((load(WORLD_SCENE) as PackedScene).instantiate())
	holder.add_child(vp)
	add_child(holder)


# Real files in a throwaway folder, so the lists show believable slots.
func _sample_saves() -> void:
	SaveSystem.save_dir = "user://capture_saves"
	WorldState.reset()
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", "bagshot_row", "", {"name": "Tolman"})
	for i in SAMPLE_SLOTS.size():
		WorldClock.now = GameDate.parse("3018-09-22T08:00") + i * 1440 * 3
		SaveSystem.save(SAMPLE_SLOTS[i])
	SaveSystem.autosave()
