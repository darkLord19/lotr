class_name TerrainChunks
extends Node3D
# Streamed chunked terrain (the plan's Terrain3D fallback). 256 m chunks are built as ArrayMeshes
# around a focus point, coarser with distance. Cracks between LODs are hidden by skirts.
# Physics: HeightMapShape3D bodies exist only for chunks within a short radius of the focus.

signal chunk_built(key: Vector2i)

class Chunk:
	var mesh_instance: MeshInstance3D
	var lod: int = -1
	var body: StaticBody3D

var heights: TerrainHeights
var material: Material
var _chunks: Dictionary = {}
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false
var _last_stream_focus: Vector3 = Vector3(INF, 0.0, INF)
var _last_collision_focus: Vector3 = Vector3(INF, 0.0, INF)
var _queue: Array[Vector2i] = []
var _chunk_m: float
var _lods: Array = []
var _hysteresis: float
var _view_radius: float
var _unload_margin: float
var _per_frame: int
var _refocus: float
var _skirt: float
var _collision_radius: float
var _collision_refresh: float
var _grid_cols: int
var _grid_rows: int


func _ready() -> void:
	if heights == null:
		heights = TerrainHeights.shared()
	if heights == null:
		push_error("TerrainChunks: terrain data missing")
		return
	_read_config()
	if material == null:
		material = StyleMaterials.terrain_material(heights)


func _read_config() -> void:
	var t: Dictionary = Config.get_value("world.terrain", {})
	_chunk_m = float(t.get("chunk_m", 256.0))
	_lods = t.get("lods", [])
	_hysteresis = float(t.get("lod_hysteresis_m", 64.0))
	_view_radius = float(t.get("view_radius_m", 2500.0))
	_unload_margin = float(t.get("unload_margin_m", 300.0))
	_per_frame = int(t.get("chunks_per_frame", 2))
	_refocus = float(t.get("refocus_distance_m", 32.0))
	_skirt = float(t.get("skirt_m", 24.0))
	_collision_radius = float(t.get("collision_radius_m", 128.0))
	_collision_refresh = float(t.get("collision_refresh_m", 16.0))
	var sz: Vector2 = heights.size_m()
	_grid_cols = int(ceil(sz.x / _chunk_m))
	_grid_rows = int(ceil(sz.y / _chunk_m))


# --- public API -----------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return heights.height_at(x, z)


func set_focus(p: Vector3) -> void:
	_focus = p
	_focus_set = true


func chunk_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _queue.size()


func collision_body_count() -> int:
	var n: int = 0
	for key in _chunks:
		if (_chunks[key] as Chunk).body != null:
			n += 1
	return n


func has_chunk(key: Vector2i) -> bool:
	return _chunks.has(key)


func chunk_lod(key: Vector2i) -> int:
	return (_chunks[key] as Chunk).lod if _chunks.has(key) else -1


# Builds everything wanted around the focus right now. Used at load time and by the capture tool;
# in play the per-frame budget in _process does the same work gradually.
func build_all_sync() -> void:
	_stream(true)
	while not _queue.is_empty():
		_build_next()
	_update_collision(true)


func _process(_delta: float) -> void:
	if heights == null or not _focus_set:
		return
	if _focus.distance_to(_last_stream_focus) > _refocus:
		_stream(false)
	for i in _per_frame:
		if _queue.is_empty():
			break
		_build_next()
	if _focus.distance_to(_last_collision_focus) > _collision_refresh:
		_update_collision(false)


# --- streaming ------------------------------------------------------------------------------

# Distance from a point to the chunk's rectangle (0 inside). Using the rectangle, not the centre,
# keeps the chunk under the camera at full detail even though its centre may be 180 m away.
func chunk_distance(key: Vector2i, p: Vector3) -> float:
	var lo := Vector2(key.x * _chunk_m, key.y * _chunk_m)
	var dx: float = maxf(maxf(lo.x - p.x, p.x - (lo.x + _chunk_m)), 0.0)
	var dz: float = maxf(maxf(lo.y - p.z, p.z - (lo.y + _chunk_m)), 0.0)
	return sqrt(dx * dx + dz * dz)


func lod_for_distance(dist: float, current: int) -> int:
	var base: int = _lods.size() - 1
	for i in _lods.size():
		if dist < float((_lods[i] as Dictionary)["max_dist_m"]):
			base = i
			break
	if current < 0 or current == base:
		return base
	# Hysteresis: only change once clearly past the boundary, so a hovering camera never flickers.
	if current < base:
		return base if dist > float((_lods[current] as Dictionary)["max_dist_m"]) + _hysteresis else current
	return base if dist < float((_lods[current - 1] as Dictionary)["max_dist_m"]) - _hysteresis else current


func _stream(_force: bool) -> void:
	_last_stream_focus = _focus
	var want: Array = []
	var reach: int = int(ceil(_view_radius / _chunk_m)) + 1
	var fc := Vector2i(int(floor(_focus.x / _chunk_m)), int(floor(_focus.z / _chunk_m)))
	for cz in range(maxi(fc.y - reach, 0), mini(fc.y + reach + 1, _grid_rows)):
		for cx in range(maxi(fc.x - reach, 0), mini(fc.x + reach + 1, _grid_cols)):
			var key := Vector2i(cx, cz)
			var d: float = chunk_distance(key, _focus)
			if d > _view_radius:
				continue
			var cur: int = (_chunks[key] as Chunk).lod if _chunks.has(key) else -1
			var lod: int = lod_for_distance(d, cur)
			if lod != cur:
				want.append([d, key])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_queue.clear()
	for w in want:
		_queue.append(w[1] as Vector2i)
	var drop: Array[Vector2i] = []
	for key in _chunks:
		if chunk_distance(key as Vector2i, _focus) > _view_radius + _unload_margin:
			drop.append(key as Vector2i)
	for key in drop:
		_free_chunk(key)


func _build_next() -> void:
	var key: Vector2i = _queue.pop_front()
	var d: float = chunk_distance(key, _focus)
	var cur: int = (_chunks[key] as Chunk).lod if _chunks.has(key) else -1
	build_chunk(key, lod_for_distance(d, cur))


# Creates or replaces one chunk at a LOD index.
func build_chunk(key: Vector2i, lod: int) -> void:
	var step: float = float((_lods[lod] as Dictionary)["step_m"])
	var chunk: Chunk = _chunks.get(key)
	if chunk == null:
		chunk = Chunk.new()
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.name = "chunk_%d_%d" % [key.x, key.y]
		chunk.mesh_instance.position = Vector3(key.x * _chunk_m, 0.0, key.y * _chunk_m)
		chunk.mesh_instance.material_override = material
		add_child(chunk.mesh_instance)
		_chunks[key] = chunk
	chunk.mesh_instance.mesh = build_chunk_mesh(key, step)
	chunk.lod = lod
	chunk_built.emit(key)


func build_chunk_mesh(key: Vector2i, step: float) -> ArrayMesh:
	var n: int = int(round(_chunk_m / step))
	var ox: float = key.x * _chunk_m
	var oz: float = key.y * _chunk_m
	# One extra ring of samples around the chunk so border normals match the neighbour's.
	var span: int = n + 3
	var hs := PackedFloat32Array()
	hs.resize(span * span)
	for j in span:
		for i in span:
			hs[j * span + i] = heights.height_at(ox + (i - 1) * step, oz + (j - 1) * step)
	var stride: int = n + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(stride * stride)
	normals.resize(stride * stride)
	for j in stride:
		for i in stride:
			var c: int = (j + 1) * span + i + 1
			verts[j * stride + i] = Vector3(i * step, hs[c], j * step)
			var dx: float = hs[c + 1] - hs[c - 1]
			var dz: float = hs[c + span] - hs[c - span]
			normals[j * stride + i] = Vector3(-dx, 2.0 * step, -dz).normalized()
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var w: int = 0
	for j in n:
		for i in n:
			var a: int = j * stride + i
			var b: int = a + 1
			var c2: int = a + stride
			var d2: int = c2 + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = c2
			idx[w + 3] = b
			idx[w + 4] = d2
			idx[w + 5] = c2
			w += 6
	_add_skirts(verts, normals, idx, n, stride)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# A downward-hanging wall around the chunk border. Where two LODs meet, the coarser edge can sit
# above or below the finer one; the wall closes that gap so no sky shows through.
func _add_skirts(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array, n: int, stride: int) -> void:
	var ring: Array[int] = []
	for i in n:
		ring.append(i)
	for j in n:
		ring.append(j * stride + n)
	for i in range(n, 0, -1):
		ring.append(n * stride + i)
	for j in range(n, 0, -1):
		ring.append(j * stride)
	var base: int = verts.size()
	for r in ring:
		var v: Vector3 = verts[r]
		verts.append(Vector3(v.x, v.y - _skirt, v.z))
		normals.append(normals[r])
	var count: int = ring.size()
	for k in count:
		var k2: int = (k + 1) % count
		idx.append_array(PackedInt32Array([ring[k], ring[k2], base + k, ring[k2], base + k2, base + k]))


func _free_chunk(key: Vector2i) -> void:
	var chunk: Chunk = _chunks.get(key)
	if chunk == null:
		return
	if chunk.body != null:
		chunk.body.queue_free()
	chunk.mesh_instance.queue_free()
	_chunks.erase(key)


# --- collision ------------------------------------------------------------------------------

func _update_collision(_force: bool) -> void:
	_last_collision_focus = _focus
	for key in _chunks:
		var chunk: Chunk = _chunks[key]
		var near: bool = chunk_distance(key as Vector2i, _focus) <= _collision_radius
		if near and chunk.body == null:
			chunk.body = _make_body(key as Vector2i)
			chunk.mesh_instance.add_child(chunk.body)
		elif not near and chunk.body != null:
			chunk.body.queue_free()
			chunk.body = null


# Collision uses the source data spacing (4 m) at every LOD: it must match what the player sees up close.
func _make_body(key: Vector2i) -> StaticBody3D:
	var spacing: float = heights.metres_per_px
	var n: int = int(round(_chunk_m / spacing))
	var count: int = n + 1
	var data := PackedFloat32Array()
	data.resize(count * count)
	var ox: float = key.x * _chunk_m
	var oz: float = key.y * _chunk_m
	for j in count:
		for i in count:
			data[j * count + i] = heights.height_at(ox + i * spacing, oz + j * spacing)
	var shape := HeightMapShape3D.new()
	shape.map_width = count
	shape.map_depth = count
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# The shape is centred on its node and has 1 m cell size; scale it to our spacing and shift to chunk centre.
	cs.scale = Vector3(spacing, 1.0, spacing)
	cs.position = Vector3(_chunk_m * 0.5, 0.0, _chunk_m * 0.5)
	var body := StaticBody3D.new()
	body.name = "ground"
	body.add_child(cs)
	return body
