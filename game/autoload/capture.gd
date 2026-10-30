extends Node

# Agent-facing screenshot tool. Args after `--`: --capture=<abs png> --after=<sec> --scene=<res path>
# --pos=x,y,z --look=yaw,pitch --date=<content date> --hide-ui --preset=<name from config/capture_presets.json>
# Explicit --pos/--look/--date/--scene beat the preset's values.

const EXIT_SCENE_FAILED: int = 2
const PRESETS_PATH: String = "res://config/capture_presets.json"

var _out_path: String = ""
var _after_frames: int = 0
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	if not _args.has("capture"):
		return
	_out_path = String(_args["capture"])
	var fps: int = maxi(Engine.max_fps, 60)
	_after_frames = int(float(_args.get("after", "3")) * fps)
	call_deferred("_start")


func _parse(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in argv:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func _start() -> void:
	if not _apply_preset():
		get_tree().quit(EXIT_SCENE_FAILED)
		return
	_apply_date()
	if _args.has("scene"):
		var packed: Resource = load(String(_args["scene"]))
		if not packed is PackedScene:
			printerr("Capture: cannot load scene %s" % _args["scene"])
			get_tree().quit(EXIT_SCENE_FAILED)
			return
		get_tree().change_scene_to_packed(packed)
		await get_tree().process_frame
		await get_tree().process_frame
	_place_camera()
	# Streaming scenes build everything the new camera position needs before we shoot.
	var root: Node = get_tree().current_scene
	if root != null and root.has_method("capture_prepare"):
		await root.call("capture_prepare")
	if _args.has("hide-ui"):
		for n in get_tree().get_nodes_in_group("ui"):
			if n is CanvasItem:
				(n as CanvasItem).hide()
	for i in _after_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(_out_path)
	print("CAPTURE_SAVED %s %dx%d err=%d" % [_out_path, img.get_width(), img.get_height(), err])
	get_tree().quit(0 if err == OK else 1)


# Fills in scene/pos/look/date from a named preset without overriding explicit arguments.
func _apply_preset() -> bool:
	if not _args.has("preset"):
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
	var presets: Dictionary = (parsed as Dictionary).get("presets", {}) if parsed is Dictionary else {}
	var preset_name: String = String(_args["preset"])
	if not presets.has(preset_name):
		printerr("Capture: unknown preset '%s' (have: %s)" % [preset_name, ", ".join(presets.keys())])
		return false
	var p: Dictionary = presets[preset_name]
	if not _args.has("scene"):
		_args["scene"] = String(p.get("scene", (parsed as Dictionary).get("default_scene", "")))
		if String(_args["scene"]).is_empty():
			_args.erase("scene")
	if not _args.has("pos") and p.has("pos"):
		var v: Array = p["pos"]
		_args["pos"] = "%s,%s,%s" % [v[0], v[1], v[2]]
	if not _args.has("look") and p.has("look"):
		var l: Array = p["look"]
		_args["look"] = "%s,%s" % [l[0], l[1]]
	if not _args.has("date") and p.has("date"):
		_args["date"] = String(p["date"])
	return true


# Set before the scene loads so scenes read the requested time in _ready; the clock is
# frozen so a slow software-rendered capture does not drift off the requested minute.
func _apply_date() -> void:
	if not _args.has("date"):
		return
	var m: int = GameDate.parse(String(_args["date"]))
	if m == GameDate.INVALID:
		printerr("Capture: bad --date %s" % _args["date"])
		return
	WorldClock.now = m
	WorldClock.pause(&"capture")


func _place_camera() -> void:
	if not (_args.has("pos") or _args.has("look")):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		get_tree().current_scene.add_child(cam)
		cam.current = true
	if _args.has("pos"):
		var p: PackedStringArray = String(_args["pos"]).split(",")
		if p.size() == 3:
			cam.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if _args.has("look"):
		var l: PackedStringArray = String(_args["look"]).split(",")
		if l.size() == 2:
			cam.rotation_degrees = Vector3(float(l[1]), float(l[0]), 0.0)
