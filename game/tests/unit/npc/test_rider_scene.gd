extends GutTest

var region: Dictionary = {}


func before_all() -> void:
	region = AudioSession.load_default_region()


func test_player_on_road_detected_by_passing_rider() -> void:
	# Rider at East Road node, facing player 25 m down the road
	var rider_pos := Vector3(1000, 0, 2250)
	var rider_facing := Vector3(1, 0, 0).normalized()

	# Player stands on the road 25 m away
	var player_pos := Vector3(1025, 0, 2250)
	var target := RiderPerception.Target.make(player_pos, false, 0.0, 0.0, true)

	var res: RiderPerception.Result = RiderPerception.evaluate(rider_pos, rider_facing, target, false)
	assert_true(res.seen, "standing player on road within 25 m should be seen")
	assert_eq(res.eye, RiderPerception.EyeState.SEEN)


func test_player_10m_off_road_crouched_in_bushes_undetected() -> void:
	# Rider at East Road node, facing along the road
	var rider_pos := Vector3(1000, 0, 2250)
	var rider_facing := Vector3(1, 0, 0).normalized()

	# Player 10 m off the road, 20 m away from rider, crouched in dense bush (concealment 0.75)
	var player_pos := Vector3(1015, 0, 2260)
	var bush := ConcealmentVolume.new()
	add_child_autofree(bush)
	bush.concealment = 0.75

	var pc := PlayerController.new()
	add_child_autofree(pc)
	pc.global_position = player_pos
	pc.set_crouched(true)
	pc.add_concealment_source(bush)

	assert_almost_eq(pc.get_vegetation_concealment(), 0.75, 0.001)

	var off_road_m: float = 10.0
	var target: RiderPerception.Target = pc.perception_target(-1.0, off_road_m)
	assert_eq(target.crouched, true)
	assert_almost_eq(target.concealment, 0.75, 0.001)

	var res: RiderPerception.Result = RiderPerception.evaluate(rider_pos, rider_facing, target, false)
	assert_false(res.seen, "crouched player in bush with effective concealment 1.0 cannot be seen")
	assert_false(res.sniffed, "sniff radius is reduced to 7.5 m off-road so rider at 20 m cannot sniff player")
	assert_eq(res.eye, RiderPerception.EyeState.HIDDEN, "player remains completely hidden")


func test_rider_manager_spawns_and_updates_hud_and_audio() -> void:
	WorldState.reset()
	var now: int = GameDate.parse("3018-09-23T19:00")
	WorldClock.now = now

	# Khamûl at Bagshot Row on the evening of Sept 23rd
	var khamul_pos := Vector3(780, 0, 2200)
	WorldState.spawn_entity("black_rider_khamul", "wraith", khamul_pos, "eriador_west", {"alive": true})

	var viewer := Node3D.new()
	add_child_autofree(viewer)
	viewer.global_position = Vector3(800, 0, 2200) # 20 m away

	var hud := HUD.new()
	add_child_autofree(hud)

	var audio := AudioSession.new()
	add_child_autofree(audio)

	var manager := RiderManager.new()
	manager.viewer = viewer
	manager.hud = hud
	manager.audio = audio
	add_child_autofree(manager)

	manager.scan()
	assert_true(manager.active_riders.has("black_rider_khamul"), "Khamûl should spawn near viewer")

	var rider_node: RiderAINode = manager.active_riders["black_rider_khamul"] as RiderAINode
	assert_not_null(rider_node)
	assert_eq(rider_node.entity_id, "black_rider_khamul")
