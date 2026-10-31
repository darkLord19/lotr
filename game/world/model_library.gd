class_name ModelLibrary
extends RefCounted
## Cached meshes and collision shapes extracted from the generated .glb assets. Models are looked up by
## id "<category>/<name>"; LOD files are "<name>_lod1.glb" / "<name>_lod2.glb" (assets/models/*/manifest.json).
## Collision comes from the glb's `-col` children (Godot imports them as StaticBody3D + shape), so the
## streamer can place the shapes itself, only near the player, instead of keeping thousands of bodies alive.

var root: String = "res://assets/models"
var _meshes: Dictionary = {}    # model_id -> Array[Mesh] (index = LOD)
var _shapes: Dictionary = {}    # model_id -> Array[{shape, xf}]
var _scaled: Dictionary = {}    # "model|sx|sy|sz" -> Array[{shape, xf}]


func _init(models_root: String = "") -> void:
	if not models_root.is_empty():
		root = models_root


func path_for(model_id: String, lod: int) -> String:
	var suffix: String = "" if lod == 0 else "_lod%d" % lod
	return "%s/%s%s.glb" % [root, model_id, suffix]


## Meshes for LOD 0..max_lods-1; missing LOD files are skipped (the array may be shorter).
func meshes(model_id: String, max_lods: int = 3) -> Array[Mesh]:
	if _meshes.has(model_id):
		return _meshes[model_id]
	var out: Array[Mesh] = []
	for lod in max_lods:
		var path: String = path_for(model_id, lod)
		if not ResourceLoader.exists(path):
			break
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			break
		var inst: Node = scene.instantiate()
		var mi: MeshInstance3D = _first_mesh_instance(inst)
		if mi != null and mi.mesh != null:
			out.append(mi.mesh)
		inst.free()
	_meshes[model_id] = out
	return out


## Shapes with their transform relative to the model origin.
func shapes(model_id: String) -> Array:
	if _shapes.has(model_id):
		return _shapes[model_id]
	var out: Array = []
	var path: String = path_for(model_id, 0)
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		if scene != null:
			var inst: Node = scene.instantiate()
			_collect_shapes(inst, inst, out)
			inst.free()
	_shapes[model_id] = out
	return out


## Same as shapes() but with the geometry pre-scaled, for instances that are stretched non-uniformly
## (bridges): physics engines do not scale convex hulls reliably per axis.
func scaled_shapes(model_id: String, s: Vector3) -> Array:
	if is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z):
		return shapes(model_id)
	var key: String = "%s|%.3f|%.3f|%.3f" % [model_id, s.x, s.y, s.z]
	if _scaled.has(key):
		return _scaled[key]
	var out: Array = []
	for e: Dictionary in shapes(model_id):
		var xf: Transform3D = e["xf"]
		var shape: Shape3D = _scale_shape(e["shape"] as Shape3D, xf, s)
		out.append({"shape": shape, "xf": Transform3D.IDENTITY})
	_scaled[key] = out
	return out


func _scale_shape(shape: Shape3D, xf: Transform3D, s: Vector3) -> Shape3D:
	var m: Transform3D = Transform3D(Basis.from_scale(s), Vector3.ZERO) * xf
	if shape is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var scaled := PackedVector3Array()
		scaled.resize(pts.size())
		for i in pts.size():
			scaled[i] = m * pts[i]
		var cs := ConvexPolygonShape3D.new()
		cs.points = scaled
		return cs
	if shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
		var out_faces := PackedVector3Array()
		out_faces.resize(faces.size())
		for i in faces.size():
			out_faces[i] = m * faces[i]
		var cc := ConcavePolygonShape3D.new()
		cc.set_faces(out_faces)
		return cc
	return shape


func triangle_count(model_id: String, lod: int) -> int:
	var ms: Array[Mesh] = meshes(model_id)
	if lod >= ms.size():
		return 0
	var n: int = 0
	var mesh: Mesh = ms[lod]
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _first_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var found: MeshInstance3D = _first_mesh_instance(c)
		if found != null:
			return found
	return null


func _collect_shapes(n: Node, scene_root: Node, out: Array) -> void:
	if n is CollisionShape3D and (n as CollisionShape3D).shape != null:
		var xf: Transform3D = Transform3D.IDENTITY
		var cur: Node = n
		while cur != null and cur != scene_root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		out.append({"shape": (n as CollisionShape3D).shape, "xf": xf})
	for c in n.get_children():
		_collect_shapes(c, scene_root, out)
