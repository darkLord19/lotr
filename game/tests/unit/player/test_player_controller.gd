extends GutTest
## M1-T08: scripted input on the real terrain collision. The body holds 3 s of W, runs, crouches;
## none of it may fall through the HeightMapShape3D ground.

const START_X: float = 900.0
const START_Z: float = 2110.0  # Bag End
const HOLD_SECONDS: float = 3.0
const WALK_MIN_M: float = 3.0
const WALK_MAX_M: float = 6.0
const GROUND_TOLERANCE_M: float = 0.4
const TEST_VIEW_RADIUS_M: float = 300.0

var world: WorldRoot
var player: PlayerController
var saved_radius: Variant


func before_all() -> void:
	InputSetup.apply()
	# A small streaming radius keeps the synchronous terrain build quick; collision radius is unchanged.
	var t: Dictionary = Config.get_value("world.terrain")
	saved_radius = t["view_radius_m"]
	t["view_radius_m"] = TEST_VIEW_RADIUS_M


func after_all() -> void:
	(Config.get_value("world.terrain") as Dictionary)["view_radius_m"] = saved_radius


func before_each() -> void:
	world = (load("res://world/world_root.tscn") as PackedScene).instantiate()
	add_child_autofree(world)
	WorldState.reset()
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", Vector3(START_X, 0.0, START_Z), "eriador_west", {"race": "man"})
	player = _spawn("man")


func after_each() -> void:
	for a: StringName in [&"move_forward", &"run", &"crouch", &"jump"]:
		Input.action_release(a)
	WorldState.reset()


func _spawn(race: String) -> PlayerController:
	var p := PlayerController.new()
	p.terrain = world.terrain
	p.configure(race)
	world.add_child(p)
	world.focus_node = p
	p.place_at(START_X, START_Z, 0.0)
	return p


func _wait_grounded(p: PlayerController) -> void:
	var guard: int = 0
	while not p.is_ground_ready() and guard < 300:
		await get_tree().physics_frame
		guard += 1
	# Land and settle on the ground before measuring.
	for i in 30:
		await get_tree().physics_frame


## Holds actions for `seconds` of physics time; returns {dist, min_clearance, noise, start}.
func _hold(p: PlayerController, actions: Array[StringName], seconds: float) -> Dictionary:
	await _wait_grounded(p)
	var start: Vector3 = p.global_position
	var min_clear: float = INF
	var noise_sum: float = 0.0
	var ticks: int = int(seconds * Engine.physics_ticks_per_second)
	for a: StringName in actions:
		Input.action_press(a)
	for i in ticks:
		await get_tree().physics_frame
		min_clear = minf(min_clear, p.global_position.y - world.height_at(p.global_position.x, p.global_position.z))
		noise_sum += p.noise
	for a: StringName in actions:
		Input.action_release(a)
	var flat: Vector3 = p.global_position - start
	flat.y = 0.0
	return {"dist": flat.length(), "delta": flat, "min_clearance": min_clear, "noise": noise_sum / ticks}


func test_spawns_above_ground_and_waits_for_collision() -> void:
	assert_gt(player.global_position.y, world.height_at(START_X, START_Z))
	await _wait_grounded(player)
	assert_true(world.terrain.has_collision_at(player.global_position))
	var ground: float = world.height_at(player.global_position.x, player.global_position.z)
	assert_almost_eq(player.global_position.y, ground, GROUND_TOLERANCE_M)
	assert_eq(player.ground_rescues, 0)


func test_hold_w_for_three_seconds_moves_forward_without_falling() -> void:
	var r: Dictionary = await _hold(player, [&"move_forward"], HOLD_SECONDS)
	gut.p("walk 3s dist=%.2f clearance=%.2f" % [r["dist"], r["min_clearance"]])
	assert_between(float(r["dist"]), WALK_MIN_M, WALK_MAX_M, "walked distance")
	assert_lt((r["delta"] as Vector3).z, 0.0, "yaw 0 walks north (-Z)")
	assert_gt(float(r["min_clearance"]), -GROUND_TOLERANCE_M, "stayed on the terrain")
	assert_eq(player.ground_rescues, 0, "real collision held; safety net unused")


func test_running_is_faster_than_walking() -> void:
	var walk: Dictionary = await _hold(player, [&"move_forward"], HOLD_SECONDS)
	var runner: PlayerController = _spawn("man")
	runner.place_at(START_X + 40.0, START_Z, 0.0)
	var run: Dictionary = await _hold(runner, [&"move_forward", &"run"], HOLD_SECONDS)
	gut.p("walk=%.2f run=%.2f" % [walk["dist"], run["dist"]])
	assert_gt(float(run["dist"]), float(walk["dist"]) * 1.5)
	assert_gt(float(run["noise"]), float(walk["noise"]))
	assert_gt(float(run["min_clearance"]), -GROUND_TOLERANCE_M)


func test_stealth_is_slower_and_quieter() -> void:
	var walk: Dictionary = await _hold(player, [&"move_forward"], HOLD_SECONDS)
	var sneaker: PlayerController = _spawn("man")
	sneaker.place_at(START_X + 40.0, START_Z, 0.0)
	await _wait_grounded(sneaker)
	Input.action_press(&"crouch")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(&"crouch")
	assert_true(sneaker.crouched, "C toggles crouch")
	var sneak: Dictionary = await _hold(sneaker, [&"move_forward"], HOLD_SECONDS)
	gut.p("walk=%.2f sneak=%.2f noise %.2f vs %.2f" % [walk["dist"], sneak["dist"], walk["noise"], sneak["noise"]])
	assert_lt(float(sneak["dist"]), float(walk["dist"]))
	assert_lt(float(sneak["noise"]), float(walk["noise"]))
	assert_true(sneaker.perception_target().crouched)


func test_bound_key_event_drives_the_action() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_W
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	assert_true(Input.is_action_pressed(&"move_forward"))
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	assert_false(Input.is_action_pressed(&"move_forward"))


func test_hobbit_is_smaller() -> void:
	var hobbit: PlayerController = _spawn("hobbit")
	assert_almost_eq(hobbit.body_height(), 0.6 * player.body_height(), 0.001)


func test_position_and_yaw_sync_to_world_state_and_back() -> void:
	await _wait_grounded(player)
	player.facing_yaw = 1.25
	player.global_position = Vector3(930.0, world.height_at(930.0, 2100.0) + 0.1, 2100.0)
	SaveSystem.about_to_save.emit()
	var loc: Dictionary = WorldState.entity_location(WorldState.PLAYER_ID)
	assert_almost_eq((loc["pos"] as Vector3).x, 930.0, 0.001)
	assert_almost_eq(float(WorldState.get_entity_data(WorldState.PLAYER_ID, "yaw")), 1.25, 0.001)
	WorldState.move_entity(WorldState.PLAYER_ID, Vector3(950.0, 0.0, 2150.0))
	WorldState.set_entity_data(WorldState.PLAYER_ID, "yaw", -0.5)
	SaveSystem.loaded.emit()
	assert_almost_eq(player.global_position.x, 950.0, 0.001)
	assert_almost_eq(player.facing_yaw, -0.5, 0.001)
	assert_false(player.is_ground_ready(), "re-grounds after a load")


func test_gait_and_noise_rules() -> void:
	assert_eq(PlayerController.choose_gait(true, true, true), PlayerController.Gait.CROUCH)
	assert_eq(PlayerController.choose_gait(true, true, false), PlayerController.Gait.RUN)
	assert_eq(PlayerController.choose_gait(true, false, false), PlayerController.Gait.WALK)
	assert_eq(PlayerController.choose_gait(false, true, false), PlayerController.Gait.IDLE)
	assert_lt(PlayerController.gait_speed(PlayerController.Gait.CROUCH), PlayerController.gait_speed(PlayerController.Gait.WALK))
	assert_lt(PlayerController.gait_speed(PlayerController.Gait.WALK), PlayerController.gait_speed(PlayerController.Gait.RUN))
	assert_eq(PlayerController.noise_for(PlayerController.Gait.CROUCH, false), 0.0)
	assert_lt(PlayerController.noise_for(PlayerController.Gait.CROUCH, true), PlayerController.noise_for(PlayerController.Gait.WALK, true))
