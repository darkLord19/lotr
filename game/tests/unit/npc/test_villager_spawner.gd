extends GutTest

var graph: RoadGraph
var spawner: VillagerSpawner
var viewer: Node3D


func before_each() -> void:
	graph = RoadGraph.new()
	graph.load_region()
	viewer = Node3D.new()
	add_child_autofree(viewer)
	spawner = VillagerSpawner.new()
	spawner.graph = graph
	spawner.viewer = viewer
	add_child_autofree(spawner)


func test_villagers_loaded() -> void:
	assert_gt(spawner.villagers.size(), 10)
	var found_hob: bool = false
	for v: Variant in spawner.villagers:
		if (v as Dictionary).get("id") == "hobbiton_hob":
			found_hob = true
			break
	assert_true(found_hob)


func test_spawns_near_villagers_and_skips_distant() -> void:
	# Viewer at Hobbiton center
	viewer.global_position = Vector3(950, 0, 2200)
	WorldClock.now = GameDate.parse("3018-09-24T12:00")
	spawner.scan()

	assert_gt(spawner.bodies.size(), 0)
	assert_true(spawner.bodies.has("hobbiton_hob"))
	assert_false(spawner.bodies.has("bree_tom"), "Bree villagers should not spawn near Hobbiton")

	var hob_body: NPCBody = spawner.bodies["hobbiton_hob"] as NPCBody
	assert_not_null(hob_body)
	# Body has interactable
	var found_interact: bool = false
	for child: Node in hob_body.get_children():
		if child is Interactable:
			found_interact = true
			assert_eq(child.target_id, "hobbiton_hob")
			break
	assert_true(found_interact)


func test_moves_and_despawns_when_player_leaves() -> void:
	# Viewer starts in Hobbiton
	viewer.global_position = Vector3(950, 0, 2200)
	WorldClock.now = GameDate.parse("3018-09-24T12:00")
	spawner.scan()
	assert_true(spawner.bodies.has("hobbiton_hob"))

	# Move viewer to Bree (7400, 2300), ~6.5 km away
	viewer.global_position = Vector3(7400, 0, 2300)
	spawner.scan()

	assert_false(spawner.bodies.has("hobbiton_hob"), "Hobbiton villagers should despawn when player is in Bree")
	assert_true(spawner.bodies.has("bree_tom"), "Bree villagers should spawn when player is in Bree")
