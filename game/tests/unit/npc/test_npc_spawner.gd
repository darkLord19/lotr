extends GutTest


func test_spawn_has_hysteresis() -> void:
	assert_true(NPCSpawner.wants_body(599.0, false, 600.0, 700.0))
	assert_false(NPCSpawner.wants_body(650.0, false, 600.0, 700.0), "not spawned yet: needs to come inside 600")
	assert_true(NPCSpawner.wants_body(650.0, true, 600.0, 700.0), "already spawned: stays until 700")
	assert_false(NPCSpawner.wants_body(701.0, true, 600.0, 700.0))


func test_rest_offset_is_stable_and_in_range() -> void:
	var a: Vector2 = NPCSpawner.rest_offset("frodo", 2.5, 6.0)
	assert_eq(a, NPCSpawner.rest_offset("frodo", 2.5, 6.0))
	assert_between(a.length(), 2.5, 6.0)
	assert_ne(a, NPCSpawner.rest_offset("sam", 2.5, 6.0))


func test_chase_speed() -> void:
	assert_eq(NPCSpawner.chase_speed(0.2, 0.3, 1.0, 7.0), 0.0)
	assert_almost_eq(NPCSpawner.chase_speed(3.0, 0.3, 1.0, 7.0), 3.0, 0.001)
	assert_eq(NPCSpawner.chase_speed(50.0, 0.3, 1.0, 7.0), 7.0)


func test_spawns_near_and_despawns_far() -> void:
	WorldState.reset()
	var graph := RoadGraph.new()
	graph.load_region()
	var viewer := Node3D.new()
	add_child_autofree(viewer)
	var spawner := NPCSpawner.new()
	spawner.graph = graph
	spawner.viewer = viewer
	add_child_autofree(spawner)
	viewer.global_position = graph.poi_pos("prancing_pony")
	spawner.scan()
	assert_true(spawner.bodies.has("barliman_butterbur"), "Butterbur rests at the Pony")
	assert_false(spawner.bodies.has("frodo"), "Bag End is 6 km away")
	assert_false(spawner.bodies.has("black_rider_khamul"), "riders are not roster bodies")
	var body: NPCBody = spawner.bodies["barliman_butterbur"]
	var talk: Array = body.get_children().filter(func(n: Node) -> bool: return n is Interactable)
	assert_eq(talk.size(), 1)
	assert_eq((talk[0] as Interactable).target_id, "barliman_butterbur")
	viewer.global_position = graph.poi_pos("bag_end")
	spawner.scan()
	assert_false(spawner.bodies.has("barliman_butterbur"))
	assert_true(spawner.bodies.has("frodo"))


func test_follows_the_entity_position() -> void:
	WorldState.reset()
	var graph := RoadGraph.new()
	graph.load_region()
	var viewer := Node3D.new()
	add_child_autofree(viewer)
	var spawner := NPCSpawner.new()
	spawner.graph = graph
	spawner.viewer = viewer
	add_child_autofree(spawner)
	viewer.global_position = graph.poi_pos("bag_end")
	WorldState.spawn_entity("sam", "npc", Vector3(900.0, 0.0, 2300.0))
	spawner.scan()
	var body: NPCBody = spawner.bodies["sam"]
	assert_almost_eq(body.global_position.x, 900.0, 0.01, "in-transit position is used exactly (no rest offset)")
	WorldState.move_entity("sam", Vector3(930.0, 0.0, 2300.0))
	spawner.scan()
	assert_true(body.is_walking(), "30 m away is chased on foot, not teleported")
	assert_almost_eq(body.global_position.x, 900.0, 0.01)
	WorldState.move_entity("sam", Vector3(1000.0, 0.0, 2300.0))
	spawner.scan()
	assert_almost_eq(body.global_position.x, 1000.0, 0.01, "beyond 60 m the body is placed directly")
	WorldState.set_alive("sam", false)
	spawner.scan()
	assert_false(spawner.bodies.has("sam"), "dead NPCs lose their body")
