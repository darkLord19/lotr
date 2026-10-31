extends Node3D
## Lays every generated model (LOD0) out by category, plus a LOD strip, for visual checks. M1-T05.
## Capture: tools/capture.sh res://tests/scenes/asset_lineup.tscn docs/reports/m1_style/asset_lineup.png

const MODEL_ROOT: String = "res://assets/models"
const CATEGORIES: Array[String] = ["nature", "shire", "bree", "props"]
const ROW_WIDTH_M: float = 175.0
const PROP_SCALE: float = 2.5  # props are tiny; scaled up here only so they read in the capture
const GAP_M: float = 1.6

var _loaded: int = 0
var _failed: int = 0


func _ready() -> void:
	var z: float = 0.0
	var max_x: float = 0.0
	for cat in CATEGORIES:
		var res: Dictionary = _layout_category(cat, z)
		z = float(res["z"]) + 4.0
		max_x = maxf(max_x, float(res["max_x"]))
	_add_ground(max_x, z)
	_add_camera(max_x, z)
	print("LINEUP loaded=%d failed=%d extent=%.0fx%.0f" % [_loaded, _failed, max_x, z])


func _manifest(cat: String) -> Array:
	var txt: String = FileAccess.get_file_as_string("%s/%s/manifest.json" % [MODEL_ROOT, cat])
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return (parsed as Dictionary).get("assets", [])
	return []


func _layout_category(cat: String, z0: float) -> Dictionary:
	var x: float = 0.0
	var row_depth: float = 0.0
	var z: float = z0
	var max_x: float = 0.0
	for a in _manifest(cat):
		var asset: Dictionary = a
		var sz: Array = asset["size_m"]
		var sc: float = PROP_SCALE if asset["kind"] == "prop" else 1.0
		var w: float = maxf(float(sz[0]), float(sz[1])) * sc
		var d: float = w
		var lods: Array = asset["files"]
		var slots: int = lods.size() if asset["kind"] in ["tree", "bush", "rock"] else 1
		var need: float = (w + GAP_M) * slots
		if x + need > ROW_WIDTH_M:
			x = 0.0
			z += row_depth + GAP_M
			row_depth = 0.0
		for i in slots:
			var ps: Variant = load("%s/%s/%s" % [MODEL_ROOT, cat, lods[i]])
			if not ps is PackedScene:
				_failed += 1
				printerr("LINEUP cannot load %s" % lods[i])
				continue
			var inst: Node3D = (ps as PackedScene).instantiate() as Node3D
			add_child(inst)
			inst.scale = Vector3.ONE * sc
			inst.position = Vector3(x + w * 0.5, -float(asset["min_z"]) * sc * 0.0, z + d * 0.5)
			x += w + GAP_M
			_loaded += 1
		row_depth = maxf(row_depth, d)
		max_x = maxf(max_x, x)
	return {"z": z + row_depth, "max_x": max_x}


func _add_ground(w: float, d: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 40.0, d + 40.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#5aa832")
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(w * 0.5, -0.02, d * 0.5)
	add_child(mi)


func _add_camera(w: float, d: float) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_color = Color("#ffe6bd")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bcd4ee")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fb4d4")
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(d * 0.9 + 14.0, w * 0.5625 + 8.0)
	cam.far = 2000.0
	add_child(cam)
	var centre := Vector3(w * 0.5, 0.0, d * 0.5)
	cam.position = centre + Vector3(0.0, 0.866, 0.5) * 300.0
	cam.look_at(centre, Vector3.UP)
	cam.current = true
