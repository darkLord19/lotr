class_name PlayerController
extends CharacterBody3D
## Third-person player body. Movement is relative to the camera yaw, speeds and noise come from
## config/player.json, key bindings from config/controls.json (via InputSetup). The body follows the
## HeightMapShape3D collision that TerrainChunks keeps around the focus, so it holds still until a
## collision chunk exists under it instead of falling through the world.
## `noise` (0..1) is what RiderPerception callers read; WorldState (entity PLAYER_ID, data.yaw) is
## kept in sync for saves and for other systems that only know entity positions.

signal grounded

enum Gait { IDLE, CROUCH, WALK, RUN }

const FACING_MARKER_SIZE: Vector3 = Vector3(0.12, 0.08, 0.22)
const BODY_COLLISION_LAYER_MASK: int = 1

var race: String = "man"
## Current noise level 0..1 for rider perception.
var noise: float = 0.0
var crouched: bool = false
var gait: Gait = Gait.IDLE
## Set by the session when a menu/dialogue is open.
var input_enabled: bool = true
var camera_rig: CameraRig
var terrain: TerrainChunks
var survival: Survival
var soft_failure: SoftFailure
## Yaw used for camera-relative movement when there is no camera rig (tests).
var move_yaw: float = 0.0
## How often the below-ground safety net had to act. Stays 0 when the real collision works.
var ground_rescues: int = 0

var _visual: Node3D
var _body_mesh: MeshInstance3D
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _scale: float = 1.0
var _ground_ready: bool = false
var _settle_frames: int = 0
var _sync_timer: float = 0.0
var _last_synced: Vector3 = Vector3(INF, INF, INF)


static func cfg(key: String, default: Variant) -> Variant:
	return Config.get_value("player." + key, default)


static func race_scale(race_id: String) -> float:
	var races: Dictionary = cfg("races", {})
	var r: Dictionary = races.get(race_id, races.get(str(cfg("default_race", "man")), {}))
	return float(r.get("scale", 1.0))


static func gait_speed(g: Gait) -> float:
	match g:
		Gait.RUN:
			return float(cfg("speed.run", 4.0))
		Gait.CROUCH:
			return float(cfg("speed.crouch", 0.9))
		Gait.WALK:
			return float(cfg("speed.walk", 1.8))
	return 0.0


static func gait_noise(g: Gait) -> float:
	match g:
		Gait.RUN:
			return float(cfg("noise.run", 1.0))
		Gait.WALK:
			return float(cfg("noise.walk", 0.5))
		Gait.CROUCH:
			return float(cfg("noise.crouch", 0.15))
	return float(cfg("noise.idle", 0.0))


## Pure gait rule: crouching beats running; no input means idle (standing) or crouch-idle.
static func choose_gait(has_input: bool, run_held: bool, is_crouched: bool) -> Gait:
	if is_crouched:
		return Gait.CROUCH
	if not has_input:
		return Gait.IDLE
	return Gait.RUN if run_held else Gait.WALK


## A crouched player who stands still makes no sound at all.
static func noise_for(g: Gait, moving: bool) -> float:
	if not moving:
		return float(cfg("noise.idle", 0.0))
	return gait_noise(g)


# --- setup ------------------------------------------------------------------------------------

## Builds the collision capsule and the placeholder visual for a race (real characters: M1-T07).
func configure(race_id: String, palette_id: String = "") -> void:
	race = race_id
	_scale = race_scale(race_id)
	collision_layer = 2
	collision_mask = BODY_COLLISION_LAYER_MASK
	floor_max_angle = deg_to_rad(float(cfg("max_slope_deg", 55.0)))
	floor_snap_length = float(cfg("floor_snap_m", 0.5))
	_build_collision()
	_build_visual(palette_id)


func _build_collision() -> void:
	if _collision == null:
		_collision = CollisionShape3D.new()
		_capsule = CapsuleShape3D.new()
		_collision.shape = _capsule
		add_child(_collision)
	_apply_stance()


func _build_visual(palette_id: String) -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var palette: Dictionary = NewGame.find_by_id(_palettes(), palette_id)
	var outfit := Color.from_string(str(palette.get("outfit", cfg("body.fallback_color", "#8a7a55"))), Color.GRAY)
	var skin := Color.from_string(str(palette.get("skin", cfg("body.fallback_skin", "#e6b48c"))), Color.WHEAT)
	var radius: float = float(cfg("body.radius_m", 0.3))
	var height: float = float(cfg("body.height_m", 1.8))
	var head_r: float = float(cfg("body.head_radius_m", 0.13))
	_body_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height - head_r
	capsule.radial_segments = 8
	capsule.rings = 3
	_body_mesh.mesh = capsule
	_body_mesh.material_override = _flat(outfit)
	_body_mesh.position.y = (height - head_r) * 0.5
	_visual.add_child(_body_mesh)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = head_r
	sphere.height = head_r * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = _flat(skin)
	head.position.y = height - head_r * 0.5
	_visual.add_child(head)
	# A nose block on the -Z side so facing is readable on an otherwise symmetric capsule.
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = FACING_MARKER_SIZE
	nose.mesh = box
	nose.material_override = _flat(skin.darkened(0.2))
	nose.position = Vector3(0.0, height - head_r * 0.5, -(head_r + FACING_MARKER_SIZE.z * 0.3))
	_visual.add_child(nose)
	_visual.scale = Vector3.ONE * _scale


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


static func _palettes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Variant in NewGame.load_appearance().get("palettes", []):
		if p is Dictionary:
			out.append(p)
	return out


func body_height() -> float:
	return float(cfg("body.height_m", 1.8)) * _scale


func _apply_stance() -> void:
	var full: float = body_height()
	var h: float = full * (float(cfg("body.crouch_height_factor", 0.6)) if crouched else 1.0)
	_capsule.radius = float(cfg("body.radius_m", 0.3)) * _scale
	_capsule.height = maxf(h, _capsule.radius * 2.0)
	_collision.position.y = _capsule.height * 0.5
	if _visual != null:
		_visual.scale = Vector3(_scale, _scale * (h / full), _scale)


# --- state API --------------------------------------------------------------------------------

var facing_yaw: float:
	get:
		return _visual.rotation.y if _visual != null else 0.0
	set(v):
		if _visual != null:
			_visual.rotation.y = v


func set_crouched(v: bool) -> void:
	if crouched == v:
		return
	crouched = v
	if _capsule != null:
		_apply_stance()


func is_ground_ready() -> bool:
	return _ground_ready


## Perception input for the Black Riders: the same flags RiderPerception.Target uses.
func perception_target(concealment: float = 0.0, off_road_m: float = 0.0) -> RiderPerception.Target:
	return RiderPerception.Target.make(global_position, crouched, concealment, off_road_m)


## Puts the body on the ground at x,z and waits for collision again (used by spawn, tp, load).
func place_at(x: float, z: float, yaw: float = NAN) -> void:
	var ground: float = terrain.height_at(x, z) if terrain != null else 0.0
	global_position = Vector3(x, ground + float(cfg("spawn.margin_m", 1.5)), z)
	velocity = Vector3.ZERO
	_ground_ready = terrain == null
	_settle_frames = 0
	if not is_nan(yaw):
		facing_yaw = yaw
		if camera_rig != null:
			camera_rig.yaw = yaw
	if terrain != null:
		terrain.set_focus(global_position)
	_last_synced = Vector3(INF, INF, INF)
	if camera_rig != null and camera_rig.is_inside_tree():
		camera_rig.global_position = global_position + Vector3.UP * body_height() * CameraRig.cfg("pivot_height_factor", 0.85)


# --- WorldState / save ------------------------------------------------------------------------

func _enter_tree() -> void:
	if not InputMap.has_action(&"move_forward"):
		InputSetup.apply()
	SaveSystem.about_to_save.connect(_write_state)
	SaveSystem.loaded.connect(read_state)


func _exit_tree() -> void:
	if SaveSystem.about_to_save.is_connected(_write_state):
		SaveSystem.about_to_save.disconnect(_write_state)
	if SaveSystem.loaded.is_connected(read_state):
		SaveSystem.loaded.disconnect(read_state)


## Pushes position and yaw into the player entity (the single source of truth).
func _write_state() -> void:
	if not WorldState.has_entity(WorldState.PLAYER_ID):
		return
	WorldState.move_entity(WorldState.PLAYER_ID, global_position)
	WorldState.set_entity_data(WorldState.PLAYER_ID, "yaw", facing_yaw)
	_last_synced = global_position


## Reads the entity back: after a load, or at spawn (a new game stores only a POI).
func read_state() -> void:
	var loc: Dictionary = WorldState.entity_location(WorldState.PLAYER_ID)
	var pos: Variant = loc["pos"]
	if pos == null:
		return
	var p: Vector3 = pos
	var yaw: float = float(WorldState.get_entity_data(WorldState.PLAYER_ID, "yaw", 0.0))
	place_at(p.x, p.z, yaw)


# --- physics ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _ground_ready:
		_wait_for_ground()
		return
	var wish: Vector2 = Vector2.ZERO
	var run_held: bool = false
	if input_enabled:
		wish = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		run_held = Input.is_action_pressed(&"run")
		_update_crouch()
	var has_input: bool = wish.length_squared() > 0.0001
	gait = choose_gait(has_input, run_held, crouched)
	var speed: float = gait_speed(gait) * _speed_multiplier()
	var yaw: float = camera_rig.yaw if camera_rig != null else move_yaw
	var dir: Vector3 = Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	var target: Vector3 = dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = float(cfg("speed.acceleration", 14.0)) if has_input else float(cfg("speed.deceleration", 18.0))
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
		if input_enabled and not crouched and Input.is_action_just_pressed(&"jump"):
			velocity.y = float(cfg("jump_velocity", 3.2))
	else:
		velocity.y -= float(cfg("gravity", 14.0)) * delta
	move_and_slide()
	_rescue_if_below_ground()
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.1
	noise = noise_for(gait, moving)
	if has_input and moving:
		_turn_towards(dir, delta)
	if gait == Gait.RUN and moving and survival != null:
		var stamina: float = soft_failure.stamina_multiplier() if soft_failure != null else 1.0
		# Real minutes of running; the debuff halves stamina, so the same run costs twice as much.
		survival.add_exertion(delta / 60.0 / maxf(stamina, 0.01))
	_sync_to_state(delta)


func _speed_multiplier() -> float:
	var m: float = survival.move_speed_multiplier() if survival != null else 1.0
	if soft_failure != null and soft_failure.black_breath_active():
		m *= float(cfg("black_breath_speed_factor", 0.85))
	return m


func _update_crouch() -> void:
	if bool(cfg("crouch_toggle", true)):
		if Input.is_action_just_pressed(&"crouch"):
			set_crouched(not crouched)
	else:
		set_crouched(Input.is_action_pressed(&"crouch"))


func _turn_towards(dir: Vector3, delta: float) -> void:
	var want: float = atan2(-dir.x, -dir.z)
	facing_yaw = lerp_angle(facing_yaw, want, clampf(float(cfg("speed.turn_rate", 10.0)) * delta, 0.0, 1.0))


# Keeps the body still (no gravity) until a collision chunk exists under it, then a couple of
# physics frames more so Jolt has the new shape in its broadphase.
func _wait_for_ground() -> void:
	if terrain == null:
		_ground_ready = true
		grounded.emit()
		return
	terrain.set_focus(global_position)
	if not terrain.has_collision_at(global_position):
		terrain.build_all_sync()
		_settle_frames = 0
		return
	_settle_frames += 1
	if _settle_frames >= int(cfg("spawn.settle_physics_frames", 2)):
		_ground_ready = true
		grounded.emit()


# Safety net only: with working collision it never fires (tests assert ground_rescues == 0).
func _rescue_if_below_ground() -> void:
	if terrain == null:
		return
	var ground: float = terrain.height_at(global_position.x, global_position.z)
	if global_position.y < ground - float(cfg("spawn.below_ground_rescue_m", 1.0)):
		ground_rescues += 1
		global_position.y = ground + 0.1
		velocity.y = 0.0


func _sync_to_state(delta: float) -> void:
	_sync_timer += delta
	if _sync_timer < float(cfg("sync.interval_s", 0.5)):
		return
	_sync_timer = 0.0
	if global_position.distance_to(_last_synced) >= float(cfg("sync.min_move_m", 0.75)):
		_write_state()
