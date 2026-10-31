extends GutTest

var g: RoadGraph


func before_each() -> void:
	g = RoadGraph.new()
	assert_true(g.load_region())


func test_route_follows_edges_and_sums_lengths() -> void:
	var r: Dictionary = g.route("bag_end", "bree_west_gate")
	assert_false(r.is_empty())
	assert_eq(r["nodes"][0], "bag_end")
	assert_eq(r["nodes"][r["nodes"].size() - 1], "bree_west_gate")
	assert_true("brandywine_bridge" in r["nodes"])
	var sum: float = 0.0
	for i in range(1, r["nodes"].size()):
		sum += g.edge_length(r["nodes"][i - 1], r["nodes"][i])
	assert_almost_eq(float(r["length"]), sum, 0.01)
	# Never shorter than the straight line.
	assert_gte(float(r["length"]), g.poi_pos("bag_end").distance_to(g.poi_pos("bree_west_gate")))


func test_route_is_shortest_not_first() -> void:
	# frogmorton -> woody_end_camp has a direct edge that beats going round via three_farthing_stone.
	var r: Dictionary = g.route("frogmorton", "woody_end_camp")
	assert_eq(r["nodes"], ["frogmorton", "woody_end_camp"] as Array[String])


func test_route_to_self_is_a_single_node() -> void:
	var r: Dictionary = g.route("bywater", "bywater")
	assert_eq(float(r["length"]), 0.0)
	assert_eq(g.locate(r, 5.0)["poi"], "bywater")


func test_abstract_poi_is_unreachable() -> void:
	assert_true(g.is_abstract("bombadil_house"))
	assert_false(g.is_routable("bombadil_house"))
	assert_true(g.route("bag_end", "bombadil_house").is_empty())
	assert_true(g.route("bombadil_house", "bag_end").is_empty())
	assert_true(g.route("bag_end", "no_such_place").is_empty())


func test_nearest_routable_for_abstract_origin() -> void:
	assert_eq(g.nearest_routable(g.poi_pos("bombadil_house")), "old_forest_edge")


func test_locate_gives_edge_and_t_and_world_position() -> void:
	var r: Dictionary = g.route("bag_end", "party_field")
	var half: Dictionary = g.locate(r, float(r["length"]) * 0.5)
	assert_eq(half["edge"], ["bag_end", "party_field"] as Array[String])
	assert_almost_eq(float(half["t"]), 0.5, 0.001)
	assert_almost_eq((half["pos"] as Vector3).distance_to(g.poi_pos("bag_end").lerp(g.poi_pos("party_field"), 0.5)), 0.0, 0.01)
	assert_eq(g.world_pos(half), half["pos"])
	assert_eq(g.locate(r, 0.0)["poi"], "bag_end")
	assert_eq(g.locate(r, float(r["length"]) + 10.0)["poi"], "party_field")


func test_locate_on_multi_edge_route_snaps_to_nodes() -> void:
	var r: Dictionary = g.route("bag_end", "bywater")
	var at_node: Dictionary = g.locate(r, g.distance_to_node(r, "party_field"))
	assert_eq(at_node["poi"], "party_field")


func test_explicit_edge_length_overrides_straight_line() -> void:
	var small: RoadGraph = RoadGraph.new()
	small.load_dict({"id": "t", "pois": [
			{"id": "a", "pos": [0, 0, 0]}, {"id": "b", "pos": [100, 0, 0]}, {"id": "c", "pos": [100, 0, 100]}],
			"road_graph": {"edges": [["a", "b", "road", 500], ["b", "c", "road"], ["a", "c", "road", 120]]}})
	assert_eq(small.edge_length("a", "b"), 500.0)
	assert_almost_eq(small.edge_length("b", "c"), 100.0, 0.01)
	# a->c direct (120) beats a->b->c (600).
	assert_eq(small.route("a", "c")["nodes"], ["a", "c"] as Array[String])


func test_settlements_near() -> void:
	var near: Array[String] = g.settlements_near(g.poi_pos("bag_end"), 100.0)
	assert_true("hobbiton" in near)
	assert_false("bree" in near)
