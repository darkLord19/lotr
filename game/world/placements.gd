class_name Placements
extends RefCounted
## Index over content/regions/eriador_west_placements.json (written by tools/terrain/place_world.py).
## Everything is bucketed by 256 m cell once at load so CellStreamer and the budget counters never scan
## the whole region. World coordinates = region coordinates (x east, z south).

const FOLIAGE_STRIDE: int = 5   # x, y, z, yaw, scale per instance

var cell_m: float = 256.0
var models: Array = []
var pois: Array = []
var forage_models: Dictionary = {}
var cols: int = 0
var rows: int = 0
## Vector2i -> {"foliage": {model_idx: PackedFloat32Array}, "objects": Array, "forage": Array,
##              "interactables": Array, "barriers": Array (each PackedFloat32Array x1,z1,x2,z2,height), "pois": Array}
var cells: Dictionary = {}
var _poi_cell: Dictionary = {}
var _forage: Array = []
var _interactables: Array = []
var _barrier_defs: Array = []
var _objects: Array = []


static func load_file(path: String, region_size: Vector2 = Vector2(8192, 4096)) -> Placements:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Placements: cannot read %s" % path)
		return null
	var p := Placements.new()
	p.build(parsed as Dictionary, region_size)
	return p


func build(doc: Dictionary, region_size: Vector2) -> void:
	cell_m = float(doc.get("cell_m", 256.0))
	models = doc.get("models", [])
	pois = doc.get("pois", [])
	forage_models = doc.get("forage_models", {})
	cols = int(ceil(region_size.x / cell_m))
	rows = int(ceil(region_size.y / cell_m))
	_forage = doc.get("forage", [])
	_interactables = doc.get("interactables", [])
	_objects = doc.get("objects", [])
	_barrier_defs = doc.get("barriers", [])
	for p: Dictionary in pois:
		var pos: Array = p["pos"]
		_poi_cell[str(p["id"])] = cell_of(float(pos[0]), float(pos[2]))
		_cell(_poi_cell[str(p["id"])] as Vector2i)["pois"].append(p)
	var buckets: Dictionary = {}   # Vector2i -> {model_idx: Array[float]}
	for row: Array in doc.get("foliage", []):
		var c: Vector2i = cell_of(float(row[1]), float(row[3]))
		var per_model: Dictionary
		if buckets.has(c):
			per_model = buckets[c]
		else:
			per_model = {}
			buckets[c] = per_model
		var mi: int = int(row[0])
		if not per_model.has(mi):
			per_model[mi] = PackedFloat32Array()
		var arr: PackedFloat32Array = per_model[mi]
		# file order is [mi, x, y, z, yaw, scale]
		arr.append(float(row[1]))
		arr.append(float(row[2]))
		arr.append(float(row[3]))
		arr.append(float(row[4]))
		arr.append(float(row[5]))
		per_model[mi] = arr
	for c: Vector2i in buckets:
		_cell(c)["foliage"] = buckets[c]
	for o: Dictionary in _objects:
		var pos: Array = o["pos"]
		_cell(cell_of(float(pos[0]), float(pos[2])))["objects"].append(o)
	for f: Dictionary in _forage:
		var pos: Array = f["pos"]
		_cell(cell_of(float(pos[0]), float(pos[2])))["forage"].append(f)
	for it: Dictionary in _interactables:
		var c: Vector2i
		if it.has("poi") and _poi_cell.has(str(it["poi"])):
			c = _poi_cell[str(it["poi"])]   # POI children live with the POI, even when the door is across a cell border
		else:
			var pos: Array = it["pos"]
			c = cell_of(float(pos[0]), float(pos[2]))
		_cell(c)["interactables"].append(it)
	for b: Dictionary in _barrier_defs:
		for s: Array in b["segs"]:
			var mx: float = (float(s[0]) + float(s[2])) * 0.5
			var mz: float = (float(s[1]) + float(s[3])) * 0.5
			_cell(cell_of(mx, mz))["barriers"].append(PackedFloat32Array([s[0], s[1], s[2], s[3], float(b.get("height_m", 14.0)), float(b.get("thickness_m", 3.0))]))


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor(x / cell_m)), 0, cols - 1), clampi(int(floor(z / cell_m)), 0, rows - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * cell_m, 0.0, (c.y + 0.5) * cell_m)


## Flat (xz) distance from p to the nearest point of the cell's rectangle (0 inside).
func cell_distance(c: Vector2i, p: Vector3) -> float:
	var x0: float = c.x * cell_m
	var z0: float = c.y * cell_m
	var dx: float = maxf(maxf(x0 - p.x, p.x - (x0 + cell_m)), 0.0)
	var dz: float = maxf(maxf(z0 - p.z, p.z - (z0 + cell_m)), 0.0)
	return sqrt(dx * dx + dz * dz)


## Cells (that hold anything) whose rectangle is within `radius` of p.
func cells_within(p: Vector3, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0: Vector2i = cell_of(p.x - radius, p.z - radius)
	var c1: Vector2i = cell_of(p.x + radius, p.z + radius)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var c := Vector2i(cx, cz)
			if cells.has(c) and cell_distance(c, p) <= radius:
				out.append(c)
	return out


func cell_data(c: Vector2i) -> Dictionary:
	return cells.get(c, {})


func foliage_count(c: Vector2i) -> int:
	var n: int = 0
	var d: Dictionary = cells.get(c, {})
	for mi: int in d.get("foliage", {}):
		n += (d["foliage"][mi] as PackedFloat32Array).size() / FOLIAGE_STRIDE
	return n


func model_id(mi: int) -> String:
	return str((models[mi] as Dictionary)["id"])


func forage_nodes() -> Array:
	return _forage


func interactable_defs() -> Array:
	return _interactables


func object_defs() -> Array:
	return _objects


func poi_def(poi_id: String) -> Dictionary:
	for p: Dictionary in pois:
		if str(p["id"]) == poi_id:
			return p
	return {}


func _cell(c: Vector2i) -> Dictionary:
	if not cells.has(c):
		cells[c] = {"foliage": {}, "objects": [], "forage": [], "interactables": [], "barriers": [], "pois": []}
	return cells[c]
