class_name WorldRoot
extends Node3D
# The playable world: streamed terrain, river water, sun, sky/fog environment and a fallback camera.
# Weather/day-night (world/weather_daynight.gd) can later take over Sun and WorldEnvironment by
# node name; nothing here depends on it.

@onready var terrain: TerrainChunks = $Terrain
@onready var water: WaterRibbons = $Water
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var camera: Camera3D = $Camera3D

# Focus override (e.g. the player body). Null = follow the active camera.
var focus_node: Node3D


func _ready() -> void:
	var heights: TerrainHeights = TerrainHeights.shared()
	if heights == null:
		push_error("WorldRoot: terrain data missing; run tools/terrain/export_engine_terrain.py")
		return
	water.heights = heights
	water.build()
	world_environment.environment = StyleMaterials.environment()
	StyleMaterials.configure_sun(sun)
	var cam: Dictionary = Config.get_value("world.camera", {})
	var pos: Array = cam.get("default_pos", [0, 100, 0])
	var look: Array = cam.get("default_look", [0, 0])
	camera.position = Vector3(pos[0], pos[1], pos[2])
	camera.rotation_degrees = Vector3(look[1], look[0], 0.0)
	camera.fov = float(cam.get("fov", 70.0))
	camera.near = float(cam.get("near", 0.3))
	camera.far = float(cam.get("far", 6000.0))
	terrain.set_focus(_focus_position())
	terrain.build_all_sync()


func _process(_delta: float) -> void:
	var p: Vector3 = _focus_position()
	terrain.set_focus(p)
	var env: Environment = world_environment.environment
	if env != null and env.fog_enabled:
		env.fog_light_color = StyleMaterials.fog_color_at(p.x)


func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# Called by the Capture autoload after it moved the camera: build every chunk the new view needs
# so the screenshot never shows half-streamed terrain.
func capture_prepare() -> void:
	terrain.set_focus(_focus_position())
	terrain.build_all_sync()
	await get_tree().process_frame


func _focus_position() -> Vector3:
	if focus_node != null:
		return focus_node.global_position
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return (cam if cam != null else camera).global_position
