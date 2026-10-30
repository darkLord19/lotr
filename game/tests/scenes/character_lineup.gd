extends Node3D
## Every character glb standing in idle: hobbits in front, tall folk behind. M1-T07 review capture.
## tools/capture.sh res://tests/scenes/character_lineup.tscn docs/reports/m1_characters/lineup.png --after=0.05

const HOBBITS: Array[String] = ["frodo", "sam", "pippin", "merry", "fatty_bolger", "gaffer_gamgee", "farmer_maggot", "mrs_maggot",
		"lobelia_sackville_baggins", "nob", "shire_hobbit_villager", "bree_hobbit_villager"]
const TALL: Array[String] = ["strider", "gandalf", "gildor_inglorion", "bill_ferny", "barliman_butterbur", "bree_villager",
		"black_rider_khamul", "black_riders_group"]
const HOBBIT_SPACING_M: float = 1.1
const TALL_SPACING_M: float = 1.65
const BACK_ROW_Z: float = -2.2
const CAM_DISTANCE_M: float = 13.5
const CAM_HEIGHT_M: float = 1.6
const CAM_FOV_DEG: float = 34.0
const LOOK_HEIGHT_M: float = 0.95

var loaded: int = 0
var failed: int = 0


func _ready() -> void:
	_row(HOBBITS, HOBBIT_SPACING_M, 0.0)
	_row(TALL, TALL_SPACING_M, BACK_ROW_Z)
	_stage()
	print("CHARACTER_LINEUP loaded=%d failed=%d" % [loaded, failed])


func _row(ids: Array[String], spacing: float, z: float) -> void:
	var x0: float = -spacing * (ids.size() - 1) * 0.5
	for i in ids.size():
		var b := NPCBody.new()
		b.name = ids[i]
		add_child(b)
		b.position = Vector3(x0 + i * spacing, 0.0, z)
		if b.setup(ids[i]):
			loaded += 1
		else:
			failed += 1
			printerr("LINEUP cannot load %s" % ids[i])


func _stage() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 20.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#6aa04a")
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(0.0, 0.0, -3.0)
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_color = Color("#ffe6bd")
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bcd4ee")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fb4d4")
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = CAM_FOV_DEG
	add_child(cam)
	cam.position = Vector3(0.0, CAM_HEIGHT_M, CAM_DISTANCE_M)
	cam.look_at(Vector3(0.0, LOOK_HEIGHT_M, -1.0), Vector3.UP)
	cam.current = true
