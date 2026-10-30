class_name CameraRig
extends Node3D
## Third-person camera: mouse orbit, scroll zoom, a SpringArm3D that pulls in against terrain and
## walls, and an over-the-shoulder offset when an NPC is within talking range. Lives under the player
## but is top-level so the body's own motion never shakes the view.
## Yaw convention (engine coords = region coords): yaw 0 looks north (-Z), east is yaw -90 deg.

var yaw: float = 0.0
var pitch: float = 0.0
var zoom: float = 4.0
var input_enabled: bool = true

var camera: Camera3D
var arm: SpringArm3D

var _target: Node3D
var _zoom_goal: float = 4.0
var _pivot_height: float = 1.5
var _shoulder_target: Node3D
var _shoulder_blend: float = 0.0
var _conversation_pos: Variant = null


static func cfg(key: String, default: float) -> float:
	return float(Config.get_value("player.camera." + key, default))


## Camera yaw that looks from `from` toward `to` on the ground plane.
static func yaw_for_direction(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


## Zoom after scroll steps (positive = zoom out), clamped to the configured range.
static func clamp_zoom(value: float) -> float:
	return clampf(value, cfg("zoom_min_m", 1.5), cfg("zoom_max_m", 8.0))


func _ready() -> void:
	top_level = true
	arm = SpringArm3D.new()
	arm.name = "Arm"
	var shape := SphereShape3D.new()
	shape.radius = cfg("collision_radius_m", 0.2)
	arm.shape = shape
	arm.collision_mask = 1
	add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	var cam_cfg: Dictionary = Config.get_value("world.camera", {})
	camera.fov = float(cam_cfg.get("fov", 70.0))
	camera.near = float(cam_cfg.get("near", 0.3))
	camera.far = float(cam_cfg.get("far", 6000.0))
	arm.add_child(camera)
	zoom = clamp_zoom(cfg("zoom_default_m", 4.0))
	_zoom_goal = zoom
	pitch = deg_to_rad(cfg("pitch_default_deg", -15.0))
	arm.spring_length = zoom
	arm.rotation.x = pitch
	camera.make_current()


## Follows `target` (the player body); `body_height` sets the orbit pivot (scales with race).
func follow(target: Node3D, body_height: float) -> void:
	_target = target
	_pivot_height = body_height * cfg("pivot_height_factor", 0.85)
	if target is CollisionObject3D:
		arm.add_excluded_object((target as CollisionObject3D).get_rid())
	global_position = target.global_position + Vector3.UP * _pivot_height
	rotation.y = yaw


func set_shoulder_target(node: Node3D) -> void:
	_shoulder_target = node


func shoulder_blend() -> float:
	return _shoulder_blend


func frame_conversation(npc_pos: Vector3) -> void:
	_conversation_pos = npc_pos


func end_conversation() -> void:
	_conversation_pos = null


func is_in_conversation() -> bool:
	return _conversation_pos != null


## Mouse motion in pixels. Inverted pitch sign so moving the mouse up looks up.
func orbit(relative: Vector2, sensitivity: float) -> void:
	var step: float = cfg("mouse_radians_per_px", 0.0025) * sensitivity
	yaw = wrapf(yaw - relative.x * step, -PI, PI)
	pitch = clampf(pitch - relative.y * step, deg_to_rad(cfg("pitch_min_deg", -75.0)), deg_to_rad(cfg("pitch_max_deg", 55.0)))


func zoom_by(steps: float) -> void:
	_zoom_goal = clamp_zoom(_zoom_goal + steps * cfg("zoom_step_m", 0.5))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit((event as InputEventMouseMotion).relative, Settings.mouse_sensitivity())
	elif event.is_action_pressed(&"zoom_in"):
		zoom_by(-1.0)
	elif event.is_action_pressed(&"zoom_out"):
		zoom_by(1.0)


func _process(delta: float) -> void:
	if _target == null:
		return
	if _conversation_pos != null:
		var d: Vector3 = (_conversation_pos as Vector3) - _target.global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			yaw = lerp_angle(yaw, yaw_for_direction(d), clampf(cfg("conversation_yaw_speed", 3.0) * delta, 0.0, 1.0))
	var want_shoulder: bool = _shoulder_target != null or _conversation_pos != null
	_shoulder_blend = move_toward(_shoulder_blend, 1.0 if want_shoulder else 0.0, cfg("shoulder_blend_speed", 4.0) * delta)
	var goal: float = _zoom_goal
	if _shoulder_blend > 0.0:
		goal = minf(goal, lerpf(goal, cfg("shoulder_zoom_m", 2.6), _shoulder_blend))
	zoom = lerpf(zoom, goal, clampf(cfg("zoom_smooth", 10.0) * delta, 0.0, 1.0))
	var anchor: Vector3 = _target.global_position + Vector3.UP * _pivot_height
	global_position = global_position.lerp(anchor, clampf(cfg("follow_smooth", 14.0) * delta, 0.0, 1.0))
	rotation.y = yaw
	arm.rotation.x = pitch
	arm.spring_length = zoom
	arm.position.x = _shoulder_blend * cfg("shoulder_offset_m", 0.6)
