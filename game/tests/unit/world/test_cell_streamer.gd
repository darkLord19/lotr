extends GutTest
## CellStreamer against the real placements file and real glb assets (headless: no rendering needed).

const BAG_END := Vector3(900.0, 49.0, 2110.0)
const FAR_FROM_EVERYTHING := Vector3(100.0, 40.0, 100.0)

var placements: Placements
var heights: TerrainHeights


func before_all() -> void:
	heights = TerrainHeights.shared()
	placements = Placements.load_file(str(Config.get_value("population.placements_path")), heights.size_m())


func _streamer() -> CellStreamer:
	var s := CellStreamer.new()
	s.setup(placements, ModelLibrary.new())
	s.heights = heights
	add_child_autofree(s)
	return s


func test_placements_loaded_and_indexed() -> void:
	assert_not_null(placements)
	assert_gt(placements.cells.size(), 100)
	assert_gt(placements.object_defs().size(), 200)
	var counted: int = 0
	for c: Vector2i in placements.cells:
		counted += placements.foliage_count(c)
	assert_gt(counted, 10000, "foliage instances")
	assert_lt(counted, 100000, "foliage stays in the tens of thousands")


func test_cells_load_only_within_radius() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var radius: float = float(Config.get_value("population.load_radius_m"))
	assert_gt(s.loaded_cells().size(), 4)
	for c in s.loaded_cells():
		assert_lte(placements.cell_distance(c, BAG_END), radius + 0.01, "cell %s inside the load radius" % c)
	# and every populated cell inside the radius is there
	for c in placements.cells_within(BAG_END, radius):
		assert_true(s.is_loaded(c), "cell %s loaded" % c)


func test_cells_unload_when_focus_moves_away() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var first: Array[Vector2i] = s.loaded_cells()
	assert_true(first.size() > 0)
	var freed: Array[Vector2i] = []
	s.cell_unloaded.connect(func(c: Vector2i) -> void: freed.append(c))
	var far := Vector3(5400.0, 50.0, 2300.0)
	s.set_focus(far)
	s.build_all_sync()
	var limit: float = float(Config.get_value("population.load_radius_m")) + float(Config.get_value("population.unload_margin_m"))
	for c in s.loaded_cells():
		assert_lte(placements.cell_distance(c, far), limit, "stale cell %s" % c)
	assert_gt(freed.size(), 0)
	for c in first:
		assert_false(s.is_loaded(c), "cell %s near Bag End unloaded after teleport" % c)


func test_streaming_over_frames_loads_nearest_first() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(s.loaded_cells().size(), 0)
	assert_gt(s.pending_count(), 0, "cells_per_frame spreads loading over frames")
	var cell: Vector2i = placements.cell_of(BAG_END.x, BAG_END.z)
	assert_true(s.is_loaded(cell), "the cell under the focus is built first")


func test_instance_counts_bounded_around_every_poi() -> void:
	var max_inst: int = int(Config.get_value("population.budget.max_foliage_instances"))
	var s: CellStreamer = _streamer()
	for p: Dictionary in placements.pois:
		var pos: Array = p["pos"]
		s.set_focus(Vector3(pos[0], pos[1], pos[2]))
		s.build_all_sync()
		assert_lte(s.foliage_instance_count(), max_inst, "foliage near %s" % p["id"])
		assert_eq(s.foliage_instance_count() > 0 or s.object_count() > 0, true)


func test_loaded_foliage_matches_budget_counter() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var b: Dictionary = s.budget_for(BAG_END)
	assert_eq(s.foliage_instance_count(), int(b["foliage_instances"]))
	assert_eq(s.object_count(), int(b["objects"]))
	assert_eq(s.loaded_cells().size(), int(b["cells"]))
	assert_gt(s.multimesh_count(), 0)


func test_foliage_uses_lod_tiers_with_visibility_fade() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var tiers: Dictionary = {}
	var found_fade: bool = false
	for cell_node in s.get_children():
		for n in cell_node.get_children():
			var mmi := n as MultiMeshInstance3D
			if mmi == null:
				continue
			tiers[mmi.visibility_range_end] = true
			if mmi.visibility_range_end_margin > 0.0 and mmi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
				found_fade = true
	assert_true(found_fade, "foliage multimeshes fade by visibility range")
	assert_gte(tiers.size(), 3, "near, mid and far tiers exist")


func test_buildings_loaded_near_bag_end() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var hole: Node3D = s.object_node("bag_end")
	assert_not_null(hole, "Bag End hobbit-hole")
	assert_lt(Vector2(hole.position.x - 900.0, hole.position.z - 2110.0).length(), 8.0)
	assert_not_null(s.poi_node("bag_end"))


func test_collision_only_within_radius() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var radius: float = float(Config.get_value("population.collision.radius_m")) + float(Config.get_value("population.collision.hysteresis_m"))
	assert_gt(s.collision_shape_count(), 0, "something solid near Bag End")
	for cell_node in s.get_children():
		var body: StaticBody3D = cell_node.get_node_or_null("Collision")
		if body == null:
			continue
		for cs in body.get_children():
			var p: Vector3 = (cs as CollisionShape3D).transform.origin
			# object shapes are positioned at the model origin plus a hull offset (largest hobbit-hole path ~ 11 m)
			assert_lte(Vector2(p.x - BAG_END.x, p.z - BAG_END.z).length(), radius + 40.0, "shape %s too far" % cs.name)
	var near: int = s.collision_shape_count()
	s.set_focus(FAR_FROM_EVERYTHING)
	s.refresh_collision(true)
	assert_lt(s.collision_shape_count(), near, "shapes released when the focus leaves")


func test_collision_follows_focus_and_stays_bounded() -> void:
	var s: CellStreamer = _streamer()
	var forest := Vector3(6400.0, 60.0, 3000.0)   # Old Forest: the densest place in the region
	s.set_focus(forest)
	s.build_all_sync()
	var n: int = s.collision_shape_count()
	assert_gt(n, 50, "trees around the focus are solid")
	assert_lt(n, 3000, "but only those within the collision radius")
	assert_lt(n, s.foliage_instance_count() / 5)


func test_old_forest_wall_blocks_even_between_trunks() -> void:
	var edge_poi: Dictionary = placements.poi_def("old_forest_edge")
	var pos: Array = edge_poi["pos"]
	var s: CellStreamer = _streamer()
	s.set_focus(Vector3(pos[0], pos[1], pos[2]))
	s.build_all_sync()
	var boxes: int = 0
	for cell_node in s.get_children():
		var body: StaticBody3D = cell_node.get_node_or_null("Collision")
		if body == null:
			continue
		for cs in body.get_children():
			if (cs as CollisionShape3D).shape is BoxShape3D:
				boxes += 1
	assert_gt(boxes, 3, "barrier boxes along the Old Forest edge")


func test_interactables_registered_in_group() -> void:
	var s: CellStreamer = _streamer()
	var pony: Dictionary = placements.poi_def("prancing_pony")
	var pos: Array = pony["pos"]
	s.set_focus(Vector3(pos[0], pos[1], pos[2]))
	s.build_all_sync()
	var kinds: Dictionary = {}
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it := n as Interactable
		if s.is_ancestor_of(it):
			kinds[it.kind] = true
	for k: StringName in [Interactable.KIND_DOOR, Interactable.KIND_BED, Interactable.KIND_FOOD]:
		assert_true(kinds.has(k), "Prancing Pony area has a %s interactable" % k)
	var poi: Poi = s.poi_node("prancing_pony")
	assert_not_null(poi)
	assert_gte(poi.interactables().size(), 3, "door, bed and food are children of the POI")
	assert_gt(s.interactable_count(), 3)


func test_interactables_unregister_when_cell_unloads() -> void:
	var s: CellStreamer = _streamer()
	s.set_focus(BAG_END)
	s.build_all_sync()
	var before: int = get_tree().get_nodes_in_group(Interactable.GROUP).size()
	assert_gt(before, 0)
	s.set_focus(Vector3(7800.0, 60.0, 3900.0))
	s.build_all_sync()
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		assert_true(s.is_ancestor_of(n), "only interactables of loaded cells remain")
	var ids: Dictionary = {}
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		ids[n.get_instance_id()] = true
	assert_lt(ids.size(), before + 1)


func test_forage_nodes_match_foraging_format() -> void:
	var nodes: Array = placements.forage_nodes()
	assert_gt(nodes.size(), 20)
	var zoned: int = 0
	for n: Dictionary in nodes:
		for k in ["id", "item", "pos", "yield"]:
			assert_true(n.has(k), "forage node has %s" % k)
		assert_eq((n["pos"] as Array).size(), 3)
		if str(n.get("zone", "")) == "maggots_fields":
			zoned += 1
			assert_true(Tuning.dict("foraging.zones").has("maggots_fields"))
	assert_gt(zoned, 3, "Maggot's fields are flagged")
	# really usable by the Foraging system
	var f := Foraging.new(nodes, Inventory.new("test_player"))
	assert_eq(f.node_ids().size(), nodes.size())


func test_poi_interaction_volume_signals_and_children() -> void:
	var poi: Poi = Poi.make("test_poi", "Test", "inn", 5.0)
	add_child_autofree(poi)
	poi.position = Vector3(10, 0, 10)
	var door: Interactable = poi.add_interactable(Interactable.KIND_DOOR, "the door", Vector3(12, 1, 10))
	assert_true(door.is_in_group(Interactable.GROUP))
	assert_eq(door.global_position, Vector3(12, 1, 10))
	assert_eq(poi.interactables().size(), 1)
	assert_not_null(poi.volume)
	assert_false(poi.occupied())


func test_budget_counters_across_region() -> void:
	# Counter-based budget: no renderer, just the placement data. The real frame-time benchmark is
	# deferred to the Mac (docs/LOCAL_TODO.md).
	var s: CellStreamer = _streamer()
	var b: Dictionary = Config.get_value("population.budget")
	var step: float = float(b["grid_step_m"])
	var worst: Dictionary = {"foliage_instances": 0, "foliage_triangles": 0, "multimeshes": 0, "objects": 0}
	var worst_at: Dictionary = {}
	var z: float = step * 0.5
	while z < 4096.0:
		var x: float = step * 0.5
		while x < 8192.0:
			var r: Dictionary = s.budget_for(Vector3(x, 0.0, z))
			for k: String in worst:
				if int(r[k]) > int(worst[k]):
					worst[k] = int(r[k])
					worst_at[k] = Vector2(x, z)
			x += step
		z += step
	gut.p("budget worst cases: %s at %s" % [worst, worst_at])
	assert_lte(int(worst["foliage_instances"]), int(b["max_foliage_instances"]), "resident foliage instances")
	assert_lte(int(worst["foliage_triangles"]), int(b["max_foliage_triangles"]), "estimated foliage triangles")
	assert_lte(int(worst["multimeshes"]), int(b["max_multimeshes"]), "multimesh nodes")
	assert_lte(int(worst["objects"]), int(b["max_objects"]), "scene objects")
