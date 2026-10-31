class_name CellStreamer
extends Node3D
## Streams the placements (buildings, props, foliage, POIs, forage) in 256 m cells around a focus point.
##
## - Cells whose rectangle is within load_radius_m (768 m) of the focus are built; cells past
##   load_radius_m + unload_margin_m are freed. Building is spread over frames (cells_per_frame).
## - Foliage = one MultiMeshInstance3D per (cell, model, LOD tier) sharing one transform buffer. Tiers use
##   the _lod1/_lod2 meshes with visibility_range fade. Godot measures that range to the instance AABB centre,
##   so ranges are wide and overlap to absorb the up-to-half-a-cell error; they live in config/population.json.
## - Buildings and props are individual scenes (MeshInstance3D per LOD, exact distances).
## - Collision exists only within collision.radius_m of the focus, as shapes taken from the glb `-col` nodes and
##   added to one StaticBody3D per cell (diffed as the focus moves, never rebuilt wholesale).
## - POIs get a Poi marker (interaction volume + Interactable children); other doors/wells are plain Interactables.
##
## Navigation (decision for M1-T06): no NavigationMesh. NPC bodies walk the RoadGraph polylines
## (sim/road_graph.gd), snapping to the terrain with height_at(); the road corridors are 4-8 m wide, kept free of
## trees and buildings by the placement generator, and settlements are small enough for steering + CharacterBody
## slide. Baking a NavigationMesh for an 8 km x 4 km region would cost minutes per bake and tens of MB, for
## NPCs that only follow roads.

signal cell_loaded(cell: Vector2i)
signal cell_unloaded(cell: Vector2i)

class LoadedCell:
	var coord: Vector2i
	var node: Node3D
	var body: StaticBody3D
	var shapes: Dictionary = {}          # key String -> CollisionShape3D
	var multimeshes: int = 0
	var foliage_instances: int = 0
	## One per (model): {mi, kind, n, buf, meshes, ranges, mmis: Array (a MultiMeshInstance3D or null per LOD tier)}.
	var groups: Array = []
	var objects: Dictionary = {}         # object id -> Node3D
	var col_objects: Array = []          # [{key, model, xf, scale}]
	var pois: Dictionary = {}            # poi id -> Poi
	var interactables: int = 0
	var forage: int = 0

var placements: Placements
var library: ModelLibrary
var heights: TerrainHeights
var enabled: bool = true

var _cfg: Dictionary = {}
var _cells: Dictionary = {}
var _queue: Array[Vector2i] = []
var _focus: Vector3 = Vector3.ZERO
var _focus_set: bool = false
var _last_plan_focus: Vector3 = Vector3(INF, 0.0, INF)
var _last_col_focus: Vector3 = Vector3(INF, 0.0, INF)
var _load_radius: float
var _unload_margin: float
var _per_frame: int
var _refocus: float
var _col_radius: float
var _col_hyst: float
var _col_refresh: float
var _barrier_thickness: float


func _ready() -> void:
	_read_config()
	if placements == null and enabled:
		var size: Vector2 = Vector2(8192, 4096)
		if heights == null:
			heights = TerrainHeights.shared()
		if heights != null:
			size = heights.size_m()
		var path: String = str(_cfg.get("placements_path", ""))
		if FileAccess.file_exists(path):
			placements = Placements.load_file(path, size)
		else:
			push_warning("CellStreamer: no placements file at %s (run tools/terrain/place_world.py)" % path)
	if heights == null:
		heights = TerrainHeights.shared()
	if library == null:
		library = ModelLibrary.new(str(_cfg.get("models_root", "res://assets/models")))


## Tests and tools inject their own data before the node enters the tree.
func setup(p: Placements, lib: ModelLibrary = null) -> void:
	placements = p
	library = lib


func _read_config() -> void:
	_cfg = Config.get_value("population", {})
	enabled = bool(_cfg.get("enabled", true))
	_load_radius = float(_cfg.get("load_radius_m", 768.0))
	_unload_margin = float(_cfg.get("unload_margin_m", 128.0))
	_per_frame = int(_cfg.get("cells_per_frame", 1))
	_refocus = float(_cfg.get("refocus_distance_m", 24.0))
	var col: Dictionary = _cfg.get("collision", {})
	_col_radius = float(col.get("radius_m", 128.0))
	_col_hyst = float(col.get("hysteresis_m", 16.0))
	_col_refresh = float(col.get("refresh_distance_m", 12.0))
	_barrier_thickness = float(col.get("barrier_thickness_m", 3.0))


# --- public API ---------------------------------------------------------------------------------

func set_focus(p: Vector3) -> void:
	_focus = p
	_focus_set = true


func loaded_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in _cells:
		out.append(c)
	return out


func is_loaded(c: Vector2i) -> bool:
	return _cells.has(c)


func pending_count() -> int:
	return _queue.size()


## Cells that should exist around p (pure: no nodes involved).
func desired_cells(p: Vector3) -> Array[Vector2i]:
	return placements.cells_within(p, _load_radius) if placements != null else ([] as Array[Vector2i])


func foliage_instance_count() -> int:
	var n: int = 0
	for c: Vector2i in _cells:
		n += (_cells[c] as LoadedCell).foliage_instances
	return n


func multimesh_count() -> int:
	var n: int = 0
	for c: Vector2i in _cells:
		n += (_cells[c] as LoadedCell).multimeshes
	return n


func object_count() -> int:
	var n: int = 0
	for c: Vector2i in _cells:
		n += (_cells[c] as LoadedCell).objects.size()
	return n


func interactable_count() -> int:
	var n: int = 0
	for c: Vector2i in _cells:
		n += (_cells[c] as LoadedCell).interactables
	return n


func collision_shape_count() -> int:
	var n: int = 0
	for c: Vector2i in _cells:
		n += (_cells[c] as LoadedCell).shapes.size()
	return n


func poi_node(poi_id: String) -> Poi:
	for c: Vector2i in _cells:
		var lc: LoadedCell = _cells[c]
		if lc.pois.has(poi_id):
			return lc.pois[poi_id]
	return null


func object_node(object_id: String) -> Node3D:
	for c: Vector2i in _cells:
		var lc: LoadedCell = _cells[c]
		if lc.objects.has(object_id):
			return lc.objects[object_id]
	return null


## Forage nodes for player/foraging.gd (format {id,item,pos,yield,zone}), for the whole region.
func forage_nodes() -> Array:
	return placements.forage_nodes() if placements != null else []


## Builds everything wanted around the focus right now (load time, captures, tests).
func build_all_sync() -> void:
	if placements == null:
		return
	_plan()
	while not _queue.is_empty():
		_build_next()
	refresh_collision(true)


## Counter-based cost estimate for a focus position, computed from the placement data only (no nodes), so a
## budget test can sweep the whole region without a renderer. A (cell, model) group is drawn in every LOD tier
## whose range covers the distance to the cell centre (adjacent tiers overlap while fading, which is counted).
func budget_for(p: Vector3) -> Dictionary:
	var out: Dictionary = {"cells": 0, "foliage_instances": 0, "foliage_drawn": 0, "foliage_triangles": 0,
		"multimeshes": 0, "multimeshes_drawn": 0, "objects": 0}
	if placements == null:
		return out
	for c: Vector2i in desired_cells(p):
		out["cells"] += 1
		var data: Dictionary = placements.cell_data(c)
		out["objects"] += (data["objects"] as Array).size()
		var centre: Vector3 = placements.cell_center(c)
		var dist: float = Vector2(p.x - centre.x, p.z - centre.z).length()
		var span: Vector2 = _cell_span(c, p)
		var per_model: Dictionary = data["foliage"]
		for mi: int in per_model:
			var n: int = (per_model[mi] as PackedFloat32Array).size() / Placements.FOLIAGE_STRIDE
			var info: Dictionary = placements.models[mi]
			var tris: Array = info.get("tris", [])
			var ranges: Array = _foliage_ranges(str(info["kind"]), int(info["lods"]))
			out["foliage_instances"] += n
			var drawn: bool = false
			for t in ranges.size():
				var r: Array = ranges[t]
				if _tier_needed(r, span, 0.0):
					out["multimeshes"] += 1
				if dist >= float(r[0]) and dist <= float(r[1]):
					drawn = true
					out["multimeshes_drawn"] += 1
					if not tris.is_empty():
						out["foliage_triangles"] += n * int(tris[mini(t, tris.size() - 1)])
			if drawn:
				out["foliage_drawn"] += n
	return out


# --- streaming ----------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if placements == null or not enabled or not _focus_set:
		return
	if _focus.distance_to(_last_plan_focus) > _refocus:
		_plan()
	var built: bool = false
	for i in _per_frame:
		if _queue.is_empty():
			break
		_build_next()
		built = true
	if built or _focus.distance_to(_last_col_focus) > _col_refresh:
		refresh_collision(false)


func _plan() -> void:
	_last_plan_focus = _focus
	var want: Array = []
	for c in desired_cells(_focus):
		if not _cells.has(c):
			want.append([placements.cell_distance(c, _focus), c])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_queue.clear()
	for w in want:
		_queue.append(w[1] as Vector2i)
	var drop: Array[Vector2i] = []
	for c: Vector2i in _cells:
		if placements.cell_distance(c, _focus) > _load_radius + _unload_margin:
			drop.append(c)
	for c in drop:
		_free_cell(c)
	for c: Vector2i in _cells:
		_sync_tiers(_cells[c] as LoadedCell)


func _build_next() -> void:
	var c: Vector2i = _queue.pop_front()
	if not _cells.has(c):
		_build_cell(c)


func _free_cell(c: Vector2i) -> void:
	var lc: LoadedCell = _cells[c]
	_cells.erase(c)
	# Out of the tree immediately so Interactable group membership and physics shapes disappear this frame.
	remove_child(lc.node)
	lc.node.queue_free()
	cell_unloaded.emit(c)


func _build_cell(c: Vector2i) -> void:
	var data: Dictionary = placements.cell_data(c)
	var lc := LoadedCell.new()
	lc.coord = c
	lc.node = Node3D.new()
	lc.node.name = "cell_%d_%d" % [c.x, c.y]
	lc.body = StaticBody3D.new()
	lc.body.name = "Collision"
	lc.node.add_child(lc.body)
	_build_foliage(lc, data)
	_build_objects(lc, data)
	_build_pois(lc, data)
	_build_forage(lc, data)
	add_child(lc.node)
	_cells[c] = lc
	cell_loaded.emit(c)


# --- foliage ------------------------------------------------------------------------------------

## [[begin, end], ...] per LOD tier for a model kind. 3 LODs use the configured tiers, 2 LODs the nearest
## and farthest, 1 LOD a single range by kind (small plants vanish early, trees stay visible).
func _foliage_ranges(kind: String, lods: int) -> Array:
	var f: Dictionary = _cfg.get("foliage", {})
	var tiers: Array = f.get("tier_ranges_m", [[0.0, 300.0], [250.0, 620.0], [560.0, 900.0]])
	return _ranges(tiers, f.get("single_lod_range_m", {}), kind, lods)


func _object_ranges(kind: String, lods: int) -> Array:
	var o: Dictionary = _cfg.get("objects", {})
	return _ranges(o.get("tier_ranges_m", [[0.0, 170.0], [140.0, 420.0], [380.0, 1000.0]]), o.get("single_lod_range_m", {}), kind, lods)


func _ranges(tiers: Array, single: Dictionary, kind: String, lods: int) -> Array:
	if lods <= 1:
		return [[0.0, float(single.get(kind, single.get("default", 240.0)))]]
	if lods == 2:
		return [tiers[0], [(tiers[1] as Array)[0], (tiers[tiers.size() - 1] as Array)[1]]]
	return tiers


## (nearest, farthest) flat distance from p to a cell's rectangle: the range of AABB-centre distances any
## instance group of the cell can have.
func _cell_span(c: Vector2i, p: Vector3) -> Vector2:
	var near: float = placements.cell_distance(c, p)
	var x0: float = c.x * placements.cell_m
	var z0: float = c.y * placements.cell_m
	var far: float = 0.0
	for ox in [0.0, placements.cell_m]:
		for oz in [0.0, placements.cell_m]:
			far = maxf(far, Vector2(x0 + ox - p.x, z0 + oz - p.z).length())
	return Vector2(near, far)


func _tier_needed(r: Array, span: Vector2, margin: float) -> bool:
	return float(r[1]) + margin >= span.x and float(r[0]) - margin <= span.y


func _build_foliage(lc: LoadedCell, data: Dictionary) -> void:
	var per_model: Dictionary = data["foliage"]
	for mi: int in per_model:
		var arr: PackedFloat32Array = per_model[mi]
		var info: Dictionary = placements.models[mi]
		var meshes: Array[Mesh] = library.meshes(str(info["id"]))
		if meshes.is_empty():
			continue
		var n: int = arr.size() / Placements.FOLIAGE_STRIDE
		var mmis: Array = []
		mmis.resize(meshes.size())
		lc.groups.append({"mi": mi, "kind": str(info["kind"]), "n": n, "buf": _transform_buffer(arr, n), "meshes": meshes,
			"ranges": _foliage_ranges(str(info["kind"]), meshes.size()), "mmis": mmis})
		lc.foliage_instances += n
	_sync_tiers(lc)


## Creates the LOD tiers whose distance range can reach the cell from the current focus and frees the ones that
## cannot (with a margin so a hovering focus never thrashes). This keeps resident MultiMeshes near what is drawn.
func _sync_tiers(lc: LoadedCell) -> void:
	var fcfg: Dictionary = _cfg.get("foliage", {})
	var fade: float = float(fcfg.get("fade_margin_m", 40.0))
	var shadow_tiers: int = int(fcfg.get("shadow_tiers", 1))
	var shadow_kinds: Array = fcfg.get("shadow_kinds", ["tree"])
	var span: Vector2 = _cell_span(lc.coord, _focus)
	var keep_margin: float = _refocus * 2.0 + fade
	for g: Dictionary in lc.groups:
		var mmis: Array = g["mmis"]
		var ranges: Array = g["ranges"]
		var meshes: Array = g["meshes"]
		for t in mmis.size():
			var r: Array = ranges[mini(t, ranges.size() - 1)]
			var exists: bool = mmis[t] != null
			if not exists and _tier_needed(r, span, 0.0):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = meshes[t] as Mesh
				mm.instance_count = int(g["n"])
				mm.buffer = g["buf"] as PackedFloat32Array
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "mm_%s_t%d" % [str(placements.models[int(g["mi"])]["id"]).get_file(), t]
				mmi.multimesh = mm
				_apply_range(mmi, r, fade)
				var casts: bool = t < shadow_tiers and str(g["kind"]) in shadow_kinds
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				lc.node.add_child(mmi)
				mmis[t] = mmi
				lc.multimeshes += 1
			elif exists and not _tier_needed(r, span, keep_margin):
				(mmis[t] as MultiMeshInstance3D).queue_free()
				(mmis[t] as MultiMeshInstance3D).get_parent().remove_child(mmis[t] as Node)
				mmis[t] = null
				lc.multimeshes -= 1


func _apply_range(gi: GeometryInstance3D, r: Array, fade: float) -> void:
	gi.visibility_range_begin = float(r[0])
	gi.visibility_range_end = float(r[1])
	gi.visibility_range_begin_margin = fade if float(r[0]) > 0.0 else 0.0
	gi.visibility_range_end_margin = fade
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# Row-major 3x4 per instance (basis rows with the origin as 4th column), yaw about Y plus uniform scale.
func _transform_buffer(arr: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n * 12)
	for i in n:
		var s: int = i * Placements.FOLIAGE_STRIDE
		var yaw: float = arr[s + 3]
		var sc: float = arr[s + 4]
		var cy: float = cos(yaw) * sc
		var sy: float = sin(yaw) * sc
		var o: int = i * 12
		buf[o] = cy
		buf[o + 1] = 0.0
		buf[o + 2] = sy
		buf[o + 3] = arr[s]
		buf[o + 4] = 0.0
		buf[o + 5] = sc
		buf[o + 6] = 0.0
		buf[o + 7] = arr[s + 1]
		buf[o + 8] = -sy
		buf[o + 9] = 0.0
		buf[o + 10] = cy
		buf[o + 11] = arr[s + 2]
	return buf


# --- objects ------------------------------------------------------------------------------------

func _object_transform(o: Dictionary) -> Transform3D:
	var pos: Array = o["pos"]
	var sc: Array = o.get("scale", [1.0, 1.0, 1.0])
	var basis: Basis = Basis(Vector3.UP, float(o.get("yaw", 0.0))) * Basis.from_scale(Vector3(float(sc[0]), float(sc[1]), float(sc[2])))
	return Transform3D(basis, Vector3(float(pos[0]), float(pos[1]), float(pos[2])))


func _build_objects(lc: LoadedCell, data: Dictionary) -> void:
	var ocfg: Dictionary = _cfg.get("objects", {})
	var fade: float = float(ocfg.get("fade_margin_m", 24.0))
	for o: Dictionary in data["objects"]:
		var mid: String = str(o["model"])
		var meshes: Array[Mesh] = library.meshes(mid)
		var root := Node3D.new()
		root.name = str(o["id"])
		root.transform = _object_transform(o)
		var ranges: Array = _object_ranges(str(o["kind"]), meshes.size())
		for t in meshes.size():
			var mi := MeshInstance3D.new()
			mi.name = "lod%d" % t
			mi.mesh = meshes[t]
			_apply_range(mi, ranges[mini(t, ranges.size() - 1)], fade)
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			root.add_child(mi)
		lc.node.add_child(root)
		lc.objects[str(o["id"])] = root
		if not library.shapes(mid).is_empty():
			var sc: Array = o.get("scale", [1.0, 1.0, 1.0])
			var sv := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
			var uniform: bool = is_equal_approx(sv.x, sv.y) and is_equal_approx(sv.y, sv.z)
			# Non-uniform stretch (bridges) is baked into the shape geometry, so the node transform must not scale again.
			var xf: Transform3D = root.transform if uniform else Transform3D(Basis(Vector3.UP, float(o.get("yaw", 0.0))), root.position)
			lc.col_objects.append({"key": str(o["id"]), "model": mid, "xf": xf, "scale": sv})


func _build_forage(lc: LoadedCell, data: Dictionary) -> void:
	var rng_end: float = float((_cfg.get("objects", {}) as Dictionary).get("forage_range_m", 120.0))
	for f: Dictionary in data["forage"]:
		var mid: String = str(placements.forage_models.get(str(f["item"]), ""))
		if mid.is_empty():
			continue
		var meshes: Array[Mesh] = library.meshes(mid, 1)
		if meshes.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "forage_%s" % str(f["id"])
		mi.mesh = meshes[0]
		var pos: Array = f["pos"]
		mi.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		mi.visibility_range_end = rng_end
		lc.node.add_child(mi)
		lc.forage += 1


# --- POIs and interactables ---------------------------------------------------------------------

func _build_pois(lc: LoadedCell, data: Dictionary) -> void:
	var radius: float = float(Config.get_value("population.poi.volume_radius_m", 14.0))
	for p: Dictionary in data["pois"]:
		var pos: Array = p["pos"]
		var poi: Poi = Poi.make(str(p["id"]), str(p["name"]), str(p["kind"]), radius)
		poi.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		lc.node.add_child(poi)
		lc.pois[str(p["id"])] = poi
	for it: Dictionary in data["interactables"]:
		var pos: Array = it["pos"]
		var wp := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var kind := StringName(str(it["kind"]))
		var poi_id: String = str(it.get("poi", ""))
		if not poi_id.is_empty() and lc.pois.has(poi_id):
			(lc.pois[poi_id] as Poi).add_interactable(kind, str(it["label"]), wp, it.get("payload", {}) as Dictionary)
		else:
			var node: Interactable = Interactable.make(kind, str(it["label"]), "", it.get("payload", {}) as Dictionary)
			node.name = str(it["id"])
			lc.node.add_child(node)
			node.position = wp
		lc.interactables += 1


# --- collision ----------------------------------------------------------------------------------

## Adds/removes collision shapes so that exactly the instances within collision.radius_m of the focus
## (plus hysteresis) have bodies. Cheap when nothing moved: only distance checks over nearby cells.
func refresh_collision(_force: bool) -> void:
	if placements == null:
		return
	_last_col_focus = _focus
	var reach: float = _col_radius + _col_hyst
	for c: Vector2i in _cells:
		var lc: LoadedCell = _cells[c]
		if placements.cell_distance(c, _focus) > reach:
			if not lc.shapes.is_empty():
				_clear_shapes(lc)
			continue
		var data: Dictionary = placements.cell_data(c)
		_refresh_foliage_shapes(lc, data)
		_refresh_object_shapes(lc)
		_refresh_barriers(lc, data)


func _clear_shapes(lc: LoadedCell) -> void:
	for k: String in lc.shapes:
		(lc.shapes[k] as CollisionShape3D).queue_free()
	lc.shapes.clear()


func _within(x: float, z: float, key_present: bool) -> bool:
	var dx: float = x - _focus.x
	var dz: float = z - _focus.z
	var d2: float = dx * dx + dz * dz
	var r: float = _col_radius + (_col_hyst if key_present else 0.0)
	return d2 <= r * r


func _add_shapes(lc: LoadedCell, key: String, model: String, xf: Transform3D, scale: Vector3) -> void:
	var list: Array = library.scaled_shapes(model, scale) if not (is_equal_approx(scale.x, scale.y) and is_equal_approx(scale.y, scale.z)) else library.shapes(model)
	for k in list.size():
		var e: Dictionary = list[k]
		var cs := CollisionShape3D.new()
		cs.shape = e["shape"] as Shape3D
		cs.transform = xf * (e["xf"] as Transform3D)
		lc.body.add_child(cs)
		lc.shapes["%s#%d" % [key, k]] = cs


func _remove_shapes(lc: LoadedCell, key: String) -> void:
	var k: int = 0
	while lc.shapes.has("%s#%d" % [key, k]):
		var name_: String = "%s#%d" % [key, k]
		(lc.shapes[name_] as CollisionShape3D).queue_free()
		lc.shapes.erase(name_)
		k += 1


func _refresh_foliage_shapes(lc: LoadedCell, data: Dictionary) -> void:
	var per_model: Dictionary = data["foliage"]
	for mi: int in per_model:
		var info: Dictionary = placements.models[mi]
		if not bool(info.get("collide", false)):
			continue
		var mid: String = str(info["id"])
		if library.shapes(mid).is_empty():
			continue
		var arr: PackedFloat32Array = per_model[mi]
		for i in arr.size() / Placements.FOLIAGE_STRIDE:
			var s: int = i * Placements.FOLIAGE_STRIDE
			var key: String = "f%d_%d" % [mi, i]
			var present: bool = lc.shapes.has(key + "#0")
			var near: bool = _within(arr[s], arr[s + 2], present)
			if near and not present:
				var sc: float = arr[s + 4]
				var xf := Transform3D(Basis(Vector3.UP, arr[s + 3]) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(arr[s], arr[s + 1], arr[s + 2]))
				_add_shapes(lc, key, mid, xf, Vector3(sc, sc, sc))
			elif present and not near:
				_remove_shapes(lc, key)


func _refresh_object_shapes(lc: LoadedCell) -> void:
	for e: Dictionary in lc.col_objects:
		var xf: Transform3D = e["xf"]
		var key: String = "o" + str(e["key"])
		var present: bool = lc.shapes.has(key + "#0")
		var near: bool = _within(xf.origin.x, xf.origin.z, present)
		if near and not present:
			_add_shapes(lc, key, str(e["model"]), xf, e["scale"] as Vector3)
		elif present and not near:
			_remove_shapes(lc, key)


func _refresh_barriers(lc: LoadedCell, data: Dictionary) -> void:
	var segs: Array = data["barriers"]
	for i in segs.size():
		var s: PackedFloat32Array = segs[i]
		var key: String = "b%d" % i
		var present: bool = lc.shapes.has(key + "#0")
		var mx: float = (s[0] + s[2]) * 0.5
		var mz: float = (s[1] + s[3]) * 0.5
		var near: bool = _within(mx, mz, present)
		if near and not present:
			var length: float = Vector2(s[2] - s[0], s[3] - s[1]).length()
			var base: float = heights.height_at(mx, mz) if heights != null else 0.0
			var box := BoxShape3D.new()
			box.size = Vector3(length + 0.5, s[4], s[5] if s[5] > 0.0 else _barrier_thickness)
			var cs := CollisionShape3D.new()
			cs.shape = box
			# Centre below the surface so the wall also holds on slopes between the segment ends.
			cs.transform = Transform3D(Basis(Vector3.UP, atan2(-(s[3] - s[1]), s[2] - s[0])), Vector3(mx, base + s[4] * 0.5 - 3.0, mz))
			lc.body.add_child(cs)
			lc.shapes[key + "#0"] = cs
		elif present and not near:
			_remove_shapes(lc, key)
