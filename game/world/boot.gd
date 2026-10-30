extends Node
## Prints BOOT_OK (verify.sh greps for it), then hands over to the game flow. Headless runs and
## tool runs (--scene/--capture, which drive their own scene) stay on this scene.

const MAIN_SCENE: String = "res://world/main.tscn"
const TOOL_ARG_PREFIXES: Array[String] = ["--scene=", "--capture=", "--preset=", "--no-menu"]


func _ready() -> void:
	print("BOOT_OK")
	if _should_open_menu():
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


static func _should_open_menu() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for arg in OS.get_cmdline_user_args():
		for prefix in TOOL_ARG_PREFIXES:
			if arg.begins_with(prefix):
				return false
	return true
