class_name NPCBody
extends CharacterBody3D
## 3D body of an NPC: loads res://assets/characters/<npc_id>.glb and drives its baked animations through an
## AnimationTree that is assembled here in code from the glb's AnimationPlayer actions (so any glb with the
## standard action names works, hand-made or generated).
##
## Tree layout (BlendTree):  stand (idle/walk/run blend) | crouch (crouch_walk) --stance--> loco_ts (time scale
## so strides match ground speed) --hold--> {free, sit, sleep, faint} --> one-shots (talk_gesture, eat, pick_up,
## sniff) --> output.  Holds are non-looping clips whose last pose stays, so sit/sleep/faint remain until
## release_hold(). talk_gesture/eat/sniff only key the upper body and layer over any gait.
##
## Movement is kinematic: the body is placed by follow_path()/walk_to() (or by the owner). Spawning, despawning and
## deciding where to walk is the off-screen sim's business (later task); bind_sim() only wires the seam
## OffscreenSim.set_body_driven / report_body_progress so one truth is kept.

signal path_finished
signal oneshot_started(anim: StringName)
signal oneshot_finished(anim: StringName)

const CONFIG_PATH: String = "res://config/characters.json"
const MANIFEST_NAME: String = "manifest.json"
const STAND: StringName = &"stand"
const CROUCH: StringName = &"crouch"
const STANCE: StringName = &"stance"
const LOCO_TS: StringName = &"loco_ts"
const HOLD: StringName = &"hold"
const FREE: StringName = &"free"
const BONE_UPPER_LEG_R: String = "UpperLeg_R"

static var _cfg_cache: Dictionary = {}
static var _manifest_cache: Dictionary = {}

var npc_id: String = ""
var model: Node3D
var player: AnimationPlayer
var tree: AnimationTree
var skeleton: Skeleton3D
var speed: float = 0.0
var crouched: bool = false
## Optional: returns ground height for (x, z); without it the body keeps the y it was given.
var height_provider: Callable = Callable()

var _entry: Dictionary = {}
var _oneshots: Array[StringName] = []
var _holds: Array[StringName] = []
var _active_oneshot: StringName = &""
var _hold: StringName = FREE
var _path: PackedVector3Array = PackedVector3Array()
var _path_i: int = 0
var _path_speed: float = 0.0
var _sim: OffscreenSim
var _sim_id: String = ""
var _report_t: float = 0.0


# --- static helpers ---------------------------------------------------------------------------

static func cfg() -> Dictionary:
	if _cfg_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			_cfg_cache = (parsed as Dictionary).get("characters", {})
	return _cfg_cache


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var path: String = str(cfg().get("model_dir", "")) + MANIFEST_NAME
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_manifest_cache = parsed
	return _manifest_cache


static func manifest_entry(id: String) -> Dictionary:
	for e: Variant in manifest().get("characters", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == id:
			return e
	return {}


static func model_path(id: String) -> String:
	return str(cfg().get("model_dir", "")) + id + ".glb"


static func has_model(id: String) -> bool:
	return not manifest_entry(id).is_empty()


## Best glb id for an NPC: its own, else the villager base for its race (hobbit/man).
static func resolve_model_id(id: String, race: String = "") -> String:
	if has_model(id):
		return id
	var fb: Dictionary = cfg().get("villager_fallbacks", {})
	return str(fb.get(race, ""))


## Randomised role->hex colours for a villager base: deterministic per seed.
static func roll_look(template_id: String, rng_seed: int) -> Dictionary:
	var pal: Dictionary = (manifest().get("villager_palettes", {}) as Dictionary).get(template_id, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Dictionary = {}
	for role: String in pal:
		var opts: Array = pal[role]
		out[role] = str(opts[rng.randi() % opts.size()])
	return out


# --- setup ------------------------------------------------------------------------------------

## Loads the model and builds the AnimationTree. `look` = role->hex overrides (see roll_look). Returns false if no glb.
func setup(id: String, look: Dictionary = {}, race: String = "") -> bool:
	var mid: String = resolve_model_id(id, race)
	if mid.is_empty():
		return false
	var ps: Variant = load(model_path(mid))
	if not ps is PackedScene:
		return false
	npc_id = id
	_entry = manifest_entry(mid)
	if model != null:
		model.queue_free()
	model = (ps as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	player = _find(model, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	if player == null:
		return false
	_build_tree()
	if not look.is_empty():
		apply_look(look)
	return true


func _find(n: Node, type_name: String) -> Node:
	if n.is_class(type_name):
		return n
	for c in n.get_children():
		var r: Node = _find(c, type_name)
		if r != null:
			return r
	return null


func height_m() -> float:
	return float(_entry.get("height_m", 1.0))


func natural_speed(anim: String) -> float:
	return float((_entry.get("natural_speed", {}) as Dictionary).get(anim, 0.0))


func has_anim(anim: StringName) -> bool:
	return player != null and player.has_animation(anim)


func _build_tree() -> void:
	var c: Dictionary = cfg()
	var loops: Array = c.get("loop_anims", [])
	for a: String in player.get_animation_list():
		var anim: Animation = player.get_animation(a)
		anim.loop_mode = Animation.LOOP_LINEAR if a in loops else Animation.LOOP_NONE
	var root := AnimationNodeBlendTree.new()
	# Locomotion by speed: position 0 idle, 1 walk, 2 run (riders have no run: max 1).
	var stand := AnimationNodeBlendSpace1D.new()
	var has_run: bool = has_anim(&"run")
	stand.min_space = 0.0
	stand.max_space = 2.0 if has_run else 1.0
	stand.sync = false
	_add_point(stand, &"idle", 0.0)
	_add_point(stand, &"walk", 1.0)
	if has_run:
		_add_point(stand, &"run", 2.0)
	root.add_node(STAND, stand)
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = 1.0
	_add_point(crouch, &"crouch_walk" if has_anim(&"crouch_walk") else &"walk", 0.0)
	_add_point(crouch, &"crouch_walk" if has_anim(&"crouch_walk") else &"walk", 1.0)
	root.add_node(CROUCH, crouch)
	var stance := AnimationNodeTransition.new()
	stance.input_count = 2
	stance.set_input_name(0, "stand")
	stance.set_input_name(1, "crouch")
	stance.xfade_time = 0.25
	root.add_node(STANCE, stance)
	root.connect_node(STANCE, 0, STAND)
	root.connect_node(STANCE, 1, CROUCH)
	var ts := AnimationNodeTimeScale.new()
	root.add_node(LOCO_TS, ts)
	root.connect_node(LOCO_TS, 0, STANCE)
	# Hold states (sit/sleep/faint) as inputs of one transition: input 0 is normal locomotion.
	_holds.clear()
	for h: String in c.get("hold_anims", []):
		if has_anim(StringName(h)):
			_holds.append(StringName(h))
	var hold := AnimationNodeTransition.new()
	hold.input_count = 1 + _holds.size()
	hold.set_input_name(0, String(FREE))
	hold.xfade_time = float(c.get("xfade_hold_s", 0.35))
	root.add_node(HOLD, hold)
	root.connect_node(HOLD, 0, LOCO_TS)
	for i in _holds.size():
		hold.set_input_name(i + 1, String(_holds[i]))
		var an := AnimationNodeAnimation.new()
		an.animation = _holds[i]
		var nm := StringName("hold_" + String(_holds[i]))
		root.add_node(nm, an)
		root.connect_node(HOLD, i + 1, nm)
	var last: StringName = HOLD
	_oneshots.clear()
	for o: String in c.get("oneshot_anims", []):
		if not has_anim(StringName(o)):
			continue
		var sn := StringName(o)
		_oneshots.append(sn)
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = float(c.get("oneshot_fade_s", 0.2))
		shot.fadeout_time = float(c.get("oneshot_fade_s", 0.2))
		var an2 := AnimationNodeAnimation.new()
		an2.animation = sn
		var an_name := StringName("anim_" + o)
		root.add_node(an_name, an2)
		var shot_name := StringName("shot_" + o)
		root.add_node(shot_name, shot)
		root.connect_node(shot_name, 0, last)
		root.connect_node(shot_name, 1, an_name)
		last = shot_name
	root.connect_node(&"output", 0, last)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = root
	tree.active = true
	set_speed(0.0)


func _add_point(space: AnimationNodeBlendSpace1D, anim: StringName, pos: float) -> void:
	var an := AnimationNodeAnimation.new()
	an.animation = anim
	space.add_blend_point(an, pos, -1, StringName("%s_%d" % [anim, space.get_blend_point_count()]))


# --- animation API ----------------------------------------------------------------------------

## Maps ground speed (m/s) to the locomotion blend position: 0 idle, 1 walk, 2 run.
static func blend_position_for(v: float) -> float:
	var c: Dictionary = cfg()
	var walk: float = float(c.get("walk_speed", 1.8))
	var run: float = float(c.get("run_speed", 4.0))
	if v <= float(c.get("speed_deadzone", 0.05)):
		return 0.0
	if v <= walk:
		return v / walk
	return 1.0 + clampf((v - walk) / maxf(run - walk, 0.01), 0.0, 1.0)


func set_speed(v: float) -> void:
	speed = maxf(v, 0.0)
	if tree == null:
		return
	var pos: float = blend_position_for(speed)
	tree.set("parameters/%s/blend_position" % STAND, pos)
	tree.set("parameters/%s/blend_position" % CROUCH, 1.0 if speed > float(cfg().get("speed_deadzone", 0.05)) else 0.0)
	tree.set("parameters/%s/transition_request" % STANCE, "crouch" if crouched else "stand")
	tree.set("parameters/%s/scale" % LOCO_TS, _time_scale(pos))


func set_crouched(v: bool) -> void:
	crouched = v
	set_speed(speed)


# Stride matching: scale the cycle so feet don't slide. Idle and (crouch) standstill keep real time or freeze.
func _time_scale(pos: float) -> float:
	var c: Dictionary = cfg()
	if speed <= float(c.get("speed_deadzone", 0.05)):
		return 0.0 if crouched else 1.0
	var key: String = "crouch_walk" if crouched else ("walk" if pos <= 1.0 else "run")
	var nat: float = natural_speed(key)
	if nat <= 0.0:
		return 1.0
	if not crouched and pos < 1.0:
		nat *= maxf(pos, 0.3)  # slow walk: blend is partly idle, so don't speed the cycle up
	return clampf(speed / nat, float(c.get("timescale_min", 0.5)), float(c.get("timescale_max", 2.3)))


## Starts a one-shot (talk_gesture, eat, pick_up, sniff) or a hold (sit, sleep, faint; ends with release_hold()).
func play_oneshot(anim: StringName) -> bool:
	if tree == null:
		return false
	if anim in _holds:
		_hold = anim
		tree.set("parameters/%s/transition_request" % HOLD, String(anim))
		oneshot_started.emit(anim)
		return true
	if anim in _oneshots:
		tree.set("parameters/shot_%s/request" % anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_active_oneshot = anim
		oneshot_started.emit(anim)
		return true
	return false


func release_hold() -> void:
	if tree != null and _hold != FREE:
		tree.set("parameters/%s/transition_request" % HOLD, String(FREE))
		oneshot_finished.emit(_hold)
		_hold = FREE


func current_hold() -> StringName:
	return _hold


func is_oneshot_active() -> bool:
	return tree != null and _active_oneshot != &"" and bool(tree.get("parameters/shot_%s/active" % _active_oneshot))


## Dominant locomotion clip right now, for UI/tests: idle, walk, run or crouch_walk.
func locomotion_state() -> StringName:
	if tree == null:
		return &""
	if crouched and speed > float(cfg().get("speed_deadzone", 0.05)):
		return &"crouch_walk"
	var pos: float = blend_position_for(speed)
	if pos < 0.5:
		return &"idle"
	return &"walk" if pos < 1.5 else &"run"


## Recolours the glb's role-named materials (skin, hair, shirt, vest, ...) without touching the shared resources.
func apply_look(look: Dictionary) -> void:
	if model == null:
		return
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(s)
			if mat is StandardMaterial3D and look.has(mat.resource_name):
				var copy: StandardMaterial3D = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.albedo_color = Color.from_string(str(look[mat.resource_name]), copy.albedo_color)
				m.set_surface_override_material(s, copy)


# --- movement ---------------------------------------------------------------------------------

## Walks the polyline at `spd` m/s, then emits path_finished and stands still.
func follow_path(points: PackedVector3Array, spd: float) -> void:
	_path = points
	_path_i = 0
	_path_speed = spd
	if points.is_empty():
		set_speed(0.0)


func walk_to(target: Vector3, spd: float) -> void:
	follow_path(PackedVector3Array([target]), spd)


func stop() -> void:
	_path = PackedVector3Array()
	set_speed(0.0)


func is_walking() -> bool:
	return _path_i < _path.size()


func face_direction(dir: Vector3, delta: float = 1.0) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	# Models face -Z (Godot forward), same as PlayerController.
	var want: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(float(cfg().get("turn_rate", 9.0)) * delta, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if _hold != FREE:
		set_speed(0.0)
		return
	if is_walking():
		var target: Vector3 = _path[_path_i]
		var to: Vector3 = target - global_position
		to.y = 0.0
		var step: float = _path_speed * delta
		if to.length() <= maxf(step, float(cfg().get("arrive_radius_m", 0.15))):
			global_position = Vector3(target.x, global_position.y, target.z)
			_path_i += 1
			if _path_i >= _path.size():
				_path = PackedVector3Array()
				set_speed(0.0)
				_snap_ground()
				path_finished.emit()
				return
		else:
			var dir: Vector3 = to.normalized()
			global_position += dir * step
			face_direction(dir, delta)
			set_speed(_path_speed)
		_snap_ground()
	_poll_oneshot()
	if _sim != null:
		_report_t += delta
		if _report_t >= float(cfg().get("report_interval_s", 0.5)):
			_report_t = 0.0
			_sim.report_body_progress(_sim_id, global_position)


func _snap_ground() -> void:
	if height_provider.is_valid():
		global_position.y = float(height_provider.call(global_position.x, global_position.z))


func _poll_oneshot() -> void:
	if _active_oneshot != &"" and not is_oneshot_active():
		var done: StringName = _active_oneshot
		_active_oneshot = &""
		oneshot_finished.emit(done)


# --- sim seam ---------------------------------------------------------------------------------

## While bound, the sim stops moving this character and takes its real position from the body.
func bind_sim(sim: OffscreenSim, id: String) -> void:
	unbind_sim()
	_sim = sim
	_sim_id = id
	sim.set_body_driven(id, true)


func unbind_sim() -> void:
	if _sim != null:
		_sim.set_body_driven(_sim_id, false)
	_sim = null
	_sim_id = ""


func _exit_tree() -> void:
	unbind_sim()
