class_name WaterRibbons
extends Node3D
# One ribbon mesh per river polyline in the region JSON. The surface sits at channel bed +
# water_fill * depth (tools/terrain/heightfield.py carves the channel with the same depth rule),
# smoothed along the river so it never steps.

const REGION_PATH: String = "res://content/regions/eriador_west.json"

var heights: TerrainHeights
var material: Material


func build() -> void:
	if heights == null:
		heights = TerrainHeights.shared()
	if material == null:
		material = StyleMaterials.water_material()
	for child in get_children():
		child.queue_free()
	var region: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION_PATH))
	if not region is Dictionary:
		push_error("WaterRibbons: cannot read %s" % REGION_PATH)
		return
	for river in (region as Dictionary).get("rivers", []):
		var mi := MeshInstance3D.new()
		mi.name = String((river as Dictionary).get("id", "river"))
		mi.mesh = build_river_mesh(river as Dictionary)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# Dense points along the polyline as Vector3(x, surface_y, z), plus matching along-river distance.
func sample_river(river: Dictionary) -> PackedVector3Array:
	var spacing: float = float(Config.get_value("world.water.sample_spacing_m", 24.0))
	var pts: Array = river["points"]
	var width: float = float(river["width"])
	var rv: Dictionary = Config.get_value("rivers", {})
	var depth: float = clampf(float(rv.get("depth_per_width", 0.09)) * width, float(rv.get("depth_min_m", 1.5)), float(rv.get("depth_max_m", 4.5)))
	var fill: float = float(rv.get("water_fill", 0.6))
	var out := PackedVector3Array()
	for s in range(pts.size() - 1):
		var a := Vector2(pts[s][0], pts[s][1])
		var b := Vector2(pts[s + 1][0], pts[s + 1][1])
		var count: int = maxi(int(ceil(a.distance_to(b) / spacing)), 1)
		for k in count:
			var p: Vector2 = a.lerp(b, float(k) / count)
			out.append(Vector3(p.x, heights.height_at(p.x, p.y), p.y))
	var last: Array = pts[pts.size() - 1]
	out.append(Vector3(last[0], heights.height_at(last[0], last[1]), last[1]))
	# Bed height, smoothed with a moving average, then lifted to the water line.
	var win: int = int(Config.get_value("world.water.smooth_samples", 4))
	var smooth := PackedVector3Array()
	for i in out.size():
		var sum: float = 0.0
		var cnt: int = 0
		for k in range(maxi(i - win, 0), mini(i + win + 1, out.size())):
			sum += out[k].y
			cnt += 1
		smooth.append(Vector3(out[i].x, sum / cnt + fill * depth + float(Config.get_value("world.water.lift_m", 0.0)), out[i].z))
	return smooth


func build_river_mesh(river: Dictionary) -> ArrayMesh:
	var pts: PackedVector3Array = sample_river(river)
	var half: float = float(river["width"]) * 0.5 * float(Config.get_value("world.water.width_factor", 0.95))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along: float = 0.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var dir := Vector2(next.x - prev.x, next.z - prev.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		if i > 0:
			along += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		verts.append(Vector3(pts[i].x - side.x * half, pts[i].y, pts[i].z - side.y * half))
		verts.append(Vector3(pts[i].x + side.x * half, pts[i].y, pts[i].z + side.y * half))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, along))
		uvs.append(Vector2(1.0, along))
		if i > 0:
			var a: int = (i - 1) * 2
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
