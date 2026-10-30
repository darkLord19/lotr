extends GutTest
# Reference values come from build/terrain/eriador_west_height.r16 (1 m) via
# .venv/bin/python (see tools/terrain/export_engine_terrain.py); grid-aligned points must match to
# the r16 quantisation (0.005 m), off-grid points to the bilinear difference between 1 m and 4 m data.

const GRID_TOLERANCE_M: float = 0.01
const OFFGRID_TOLERANCE_M: float = 1.0

var heights: TerrainHeights


func before_all() -> void:
	heights = TerrainHeights.shared()


func test_data_loaded() -> void:
	assert_not_null(heights)
	assert_eq(heights.size_m(), Vector2(8192, 4096))


func test_height_matches_python_on_grid_points() -> void:
	assert_almost_eq(heights.height_at(1236.0, 2344.0), 39.2145, GRID_TOLERANCE_M)
	assert_almost_eq(heights.height_at(4000.0, 1000.0), 36.0650, GRID_TOLERANCE_M)
	assert_almost_eq(heights.height_at(5312.0, 1900.0), 44.8249, GRID_TOLERANCE_M)
	assert_almost_eq(heights.height_at(7520.0, 2208.0), 115.2605, GRID_TOLERANCE_M)
	assert_almost_eq(heights.height_at(0.0, 0.0), 218.5922, GRID_TOLERANCE_M)


func test_bag_end_and_bree_hill_heights() -> void:
	assert_almost_eq(heights.height_at(900.0, 2110.0), 49.10, OFFGRID_TOLERANCE_M, "Bag End")
	assert_almost_eq(heights.height_at(7520.0, 2210.0), 115.26, OFFGRID_TOLERANCE_M, "Bree-hill")


func test_river_cell_is_lower_than_both_banks() -> void:
	# Brandywine centre line at z = 1900 is x ~ 5313.4.
	var centre: float = heights.height_at(5313.0, 1900.0)
	assert_lt(centre, heights.height_at(5213.0, 1900.0) - 1.0)
	assert_lt(centre, heights.height_at(5413.0, 1900.0) - 1.0)


func test_height_clamps_outside_region_without_nan() -> void:
	for p in [Vector2(-500, -500), Vector2(9000, 5000), Vector2(8192, 4096), Vector2(-1, 2000)]:
		var h: float = heights.height_at(p.x, p.y)
		assert_false(is_nan(h))
		assert_between(h, 0.0, 320.0)


func test_normals_are_unit_and_upward() -> void:
	for p in [Vector2(900, 2110), Vector2(7520, 2210), Vector2(5313, 1900), Vector2(10, 10)]:
		var n: Vector3 = heights.normal_at(p.x, p.y, 4.0)
		assert_almost_eq(n.length(), 1.0, 0.001)
		assert_gt(n.y, 0.0)


func test_splat_has_dirt_on_the_east_road() -> void:
	# East Road passes (1060, 2250); the road centre must be dirt, a point 100 m off must not.
	assert_gt(heights.splat_at(1060.0, 2250.0).r, 0.8)
	assert_lt(heights.splat_at(1060.0, 2350.0).r, 0.1)


func _make_terrain() -> TerrainChunks:
	var t := TerrainChunks.new()
	add_child_autofree(t)
	return t


func test_chunk_mesh_is_finite_and_has_skirts() -> void:
	var t: TerrainChunks = _make_terrain()
	var mesh: ArrayMesh = t.build_chunk_mesh(Vector2i(3, 8), 8.0)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var n: int = 32
	assert_eq(verts.size(), (n + 1) * (n + 1) + 4 * n, "grid plus one skirt vertex per border vertex")
	for v in verts:
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z))
	for nv in normals:
		assert_almost_eq(nv.length(), 1.0, 0.001)
	assert_eq(mesh.get_aabb().size.x, 256.0)


func test_adjacent_chunk_edges_share_heights() -> void:
	var t: TerrainChunks = _make_terrain()
	var a: PackedVector3Array = t.build_chunk_mesh(Vector2i(4, 8), 16.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = t.build_chunk_mesh(Vector2i(5, 8), 16.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n: int = 16
	for j in n + 1:
		assert_almost_eq(a[j * (n + 1) + n].y, b[j * (n + 1)].y, 0.0001)


func test_streaming_builds_bounded_chunk_set_with_lods() -> void:
	var t: TerrainChunks = _make_terrain()
	t.set_focus(Vector3(900.0, 60.0, 2200.0))
	t.build_all_sync()
	var count: int = t.chunk_count()
	assert_gt(count, 20)
	assert_lt(count, 400, "must not build the 512-chunk region eagerly")
	assert_eq(t.pending_count(), 0)
	assert_eq(t.chunk_lod(Vector2i(3, 8)), 0, "chunk under the focus is full detail")
	assert_gt(t.chunk_lod(Vector2i(10, 8)), 1, "far chunk is coarse")
	assert_false(t.has_chunk(Vector2i(25, 8)), "chunk 6 km away is not built")


func test_collision_only_near_focus() -> void:
	var t: TerrainChunks = _make_terrain()
	t.set_focus(Vector3(900.0, 60.0, 2200.0))
	t.build_all_sync()
	var bodies: int = t.collision_body_count()
	assert_between(bodies, 1, 4)
	t.set_focus(Vector3(5000.0, 60.0, 2000.0))
	t.build_all_sync()
	assert_between(t.collision_body_count(), 1, 4)
	assert_false(t.has_chunk(Vector2i(3, 8)), "old area is unloaded")


func test_lod_hysteresis_prevents_flicker() -> void:
	var t: TerrainChunks = _make_terrain()
	var boundary: float = 450.0
	assert_eq(t.lod_for_distance(boundary - 1.0, -1), 0)
	assert_eq(t.lod_for_distance(boundary + 10.0, 0), 0, "stays fine just past the boundary")
	assert_eq(t.lod_for_distance(boundary + 100.0, 0), 1)
	assert_eq(t.lod_for_distance(boundary - 10.0, 1), 1, "stays coarse just inside the boundary")
	assert_eq(t.lod_for_distance(boundary - 100.0, 1), 0)


func test_ground_collision_stops_a_ray() -> void:
	var t: TerrainChunks = _make_terrain()
	t.set_focus(Vector3(900.0, 60.0, 2200.0))
	t.build_all_sync()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = t.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(900.0, 300.0, 2200.0), Vector3(900.0, -10.0, 2200.0))
	var hit: Dictionary = space.intersect_ray(q)
	assert_false(hit.is_empty(), "ray down from above hits the ground shape")
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, heights.height_at(900.0, 2200.0), 0.5)
