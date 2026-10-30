extends Node3D
## Capture scene for tools/capture.sh: the player at Bag End seen from behind (third-person rig).
## --stage=back (default) | npc (an NPC stand-in in talking range: prompt and shoulder framing).
## Example: tools/capture.sh res://tests/scenes/m1_player_capture.tscn out.png --after=0.05

const BAG_END: Vector2 = Vector2(900.0, 2110.0)
const NPC_OFFSET: Vector3 = Vector3(1.4, 0.0, -1.6)
const PALETTE: String = "fair_meadow"
const DATE: String = "3018-09-20T10:00"
const CAPTURE_YAW_DEG: float = -35.0
const CAPTURE_PITCH_DEG: float = -12.0
const CAPTURE_ZOOM_M: float = 3.2
const SETTLE_FRAMES: int = 90

var session: PlayerSession
var world: WorldRoot
var stage: String = "back"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr("--stage=".length())
	WorldState.reset()
	WorldClock.now = GameDate.parse(DATE)
	WorldClock.pause(&"capture")
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", Vector3(BAG_END.x, 0.0, BAG_END.y), "eriador_west", {"race": "hobbit", "appearance": {"palette": PALETTE, "hair": "curly"}})
	world = (load("res://world/world_root.tscn") as PackedScene).instantiate()
	add_child(world)
	session = PlayerSession.new()
	session.world = world
	add_child(session)
	if stage == "npc":
		_add_npc()


func _add_npc() -> void:
	var pos: Vector3 = session.controller.global_position + NPC_OFFSET
	var npc := Node3D.new()
	npc.name = "Sam"
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3 * 0.6
	capsule.height = 1.8 * 0.6
	mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#7a5a3c")
	mesh.material_override = mat
	mesh.position.y = capsule.height * 0.5
	npc.add_child(mesh)
	world.add_child(npc)
	npc.add_child(Interactable.make(Interactable.KIND_NPC, "Sam", "sam"))
	pos.y = world.height_at(pos.x, pos.z)
	npc.global_position = pos


func capture_prepare() -> void:
	var c: PlayerController = session.controller
	while not c.is_ground_ready():
		await get_tree().physics_frame
	for i in SETTLE_FRAMES:
		await get_tree().physics_frame
	var rig: CameraRig = session.rig
	rig.yaw = deg_to_rad(CAPTURE_YAW_DEG)
	rig.pitch = deg_to_rad(CAPTURE_PITCH_DEG)
	rig._zoom_goal = CAPTURE_ZOOM_M
	rig.zoom = CAPTURE_ZOOM_M
	c.facing_yaw = rig.yaw
	if stage == "npc":
		session.interaction._process(0.0)
		rig.set_shoulder_target(session.interaction.current())
	world.terrain.set_focus(c.global_position)
	world.terrain.build_all_sync()
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
