extends GutTest
## M1-T07: the AnimationTree built from a glb must change state with speed, run one-shots and holds.

const STEP: float = 0.05

var body: NPCBody


func before_each() -> void:
	body = NPCBody.new()
	add_child_autofree(body)


func _pump(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		body.tree.advance(STEP)
		t += STEP


# Thigh pitch swing seen over one second of playback: idle ~ tiny, walk bigger, run biggest.
func _leg_swing() -> float:
	var idx: int = body.skeleton.find_bone(NPCBody.BONE_UPPER_LEG_R)
	var lo: float = INF
	var hi: float = -INF
	for i in 24:
		body.tree.advance(STEP)
		var a: float = body.skeleton.get_bone_pose_rotation(idx).get_euler().x
		lo = minf(lo, a)
		hi = maxf(hi, a)
	return hi - lo


func test_every_character_glb_loads_with_standard_actions() -> void:
	var count: int = 0
	for e: Variant in NPCBody.manifest().get("characters", []):
		var id: String = str((e as Dictionary)["id"])
		var b := NPCBody.new()
		add_child_autofree(b)
		assert_true(b.setup(id), "setup %s" % id)
		for a: String in (e as Dictionary)["anims"]:
			assert_true(b.has_anim(StringName(a)), "%s has %s" % [id, a])
		count += 1
	assert_eq(count, 20)


func test_tree_state_follows_speed() -> void:
	assert_true(body.setup("frodo"))
	body.set_speed(0.0)
	assert_eq(body.locomotion_state(), &"idle")
	assert_almost_eq(float(body.tree.get("parameters/stand/blend_position")), 0.0, 0.001)
	_pump(1.0)
	var idle_swing: float = _leg_swing()
	body.set_speed(1.8)
	assert_eq(body.locomotion_state(), &"walk")
	assert_almost_eq(float(body.tree.get("parameters/stand/blend_position")), 1.0, 0.001)
	_pump(1.0)
	var walk_swing: float = _leg_swing()
	body.set_speed(4.0)
	assert_eq(body.locomotion_state(), &"run")
	assert_almost_eq(float(body.tree.get("parameters/stand/blend_position")), 2.0, 0.001)
	_pump(1.0)
	var run_swing: float = _leg_swing()
	assert_lt(idle_swing, 0.1)
	assert_gt(walk_swing, idle_swing + 0.3)
	assert_gt(run_swing, walk_swing)


func test_crouch_and_time_scale() -> void:
	assert_true(body.setup("sam"))
	body.set_speed(1.8)
	var normal_scale: float = float(body.tree.get("parameters/loco_ts/scale"))
	assert_gt(normal_scale, 1.0, "a hobbit's short legs need a faster cycle to cover 1.8 m/s")
	body.set_crouched(true)
	body.set_speed(0.9)
	assert_eq(body.locomotion_state(), &"crouch_walk")
	_pump(0.5)
	assert_eq(str(body.tree.get("parameters/stance/current_state")), "crouch")


func test_oneshot_and_hold() -> void:
	assert_true(body.setup("strider"))
	assert_true(body.play_oneshot(&"talk_gesture"))
	_pump(0.3)
	assert_true(body.is_oneshot_active())
	_pump(3.0)
	assert_false(body.is_oneshot_active(), "finite one-shot ends by itself")
	assert_true(body.play_oneshot(&"sit"))
	_pump(1.0)
	assert_eq(body.current_hold(), &"sit")
	# seated: hips dropped well below standing height
	var hips: int = body.skeleton.find_bone("Hips")
	var standing_y: float = body.skeleton.get_bone_rest(hips).origin.y
	_pump(2.5)
	assert_lt(body.skeleton.get_bone_pose_position(hips).y, standing_y - 0.2)
	body.release_hold()
	assert_eq(body.current_hold(), &"free")
	assert_false(body.play_oneshot(&"sniff"), "humans have no sniff clip")


func test_rider_has_sniff_and_no_run() -> void:
	assert_true(body.setup("black_rider_khamul"))
	assert_false(body.has_anim(&"run"))
	assert_true(body.play_oneshot(&"sniff"))
	body.set_speed(4.0)  # no run clip: must not break
	_pump(0.5)
	assert_true(body.is_oneshot_active())


func test_follow_path_moves_and_finishes() -> void:
	assert_true(body.setup("pippin"))
	var done: Array[bool] = [false]
	body.path_finished.connect(func() -> void: done[0] = true)
	body.follow_path(PackedVector3Array([Vector3(0, 0, -2), Vector3(2, 0, -2)]), 4.0)
	for i in 200:
		body._physics_process(0.02)
		if done[0]:
			break
	assert_true(done[0])
	assert_almost_eq(body.global_position.x, 2.0, 0.2)
	assert_almost_eq(body.global_position.z, -2.0, 0.2)
	assert_eq(body.locomotion_state(), &"idle")


func test_facing_uses_minus_z_forward() -> void:
	assert_true(body.setup("frodo"))
	body.rotation.y = 0.0
	body.face_direction(Vector3(-1, 0, 0), 100.0)
	assert_almost_eq(body.rotation.y, PI / 2.0, 0.01)  # turning left (west) = +90 deg about Y


func test_villager_look_roll_and_apply() -> void:
	var look: Dictionary = NPCBody.roll_look("shire_hobbit_villager", 7)
	assert_true(look.has("skin") and look.has("vest"))
	assert_eq(NPCBody.roll_look("shire_hobbit_villager", 7), look, "deterministic per seed")
	assert_true(body.setup("some_unknown_hobbit", look, "hobbit"), "falls back to the hobbit villager base")
	assert_eq(body.height_m(), 1.08)
