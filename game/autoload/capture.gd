extends Node

# Agent-facing screenshot tool. Args after `--`: --capture=<abs png> --after=<sec> --scene=<res path>
# --pos=x,y,z --look=yaw,pitch --date=<content date> --hide-ui

const EXIT_SCENE_FAILED: int = 2

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
