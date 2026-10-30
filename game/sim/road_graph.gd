class_name RoadGraph
extends RefCounted
## Road graph over the region's POIs: shortest paths, "edge + t" positions and their world
## coordinates. Pure data/maths (no nodes), so the off-screen sim and the 3D body spawner
## share one definition of where a character is.
##
## A *route* is {"nodes": Array[String], "cum": Array[float], "length": float}; cum[i] is the
## distance along the route to nodes[i]. A *position ref* is either {"poi": id, "pos": Vector3}
## or {"edge": [a, b], "t": 0..1 (from a to b), "pos": Vector3}.

const DEFAULT_REGION_PATH: String = "res://content/regions/eriador_west.json"
# Region edges are [a, b, kind] with an optional 4th element overriding the length (metres),
# e.g. for a winding road whose polyline is much longer than the straight line.
const EDGE_LENGTH_INDEX: int = 3

var region_id: String = ""
# poi id -> Vector3 (y is 0 here; terrain height is a seam resolved by whoever places a body)
var _pos: Dictionary = {}
var _abstract: Dictionary = {}
var _settlement: Dictionary = {}
# node id -> Array of {"to": String, "len": float, "kind": String}
var _adj: Dictionary = {}
var _route_cache: Dictionary = {}


func load_region(path: String = DEFAULT_REGION_PATH) -> bool:
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK \
			or not (json.data is Dictionary):
		push_warning("RoadGraph: cannot load region %s" % path)
		return false
	load_dict(json.data)
	return true


func load_dict(region: Dictionary) -> void:
	region_id = str(region.get("id", ""))
	_pos = {}
	_abstract = {}
	_settlement = {}
	_adj = {}
	_route_cache = {}
	for raw: Variant in region.get("pois", []):
		var p: Dictionary = raw
		var a: Array = p.get("pos", [0, 0, 0])
		var id: String = str(p.get("id", ""))
		_pos[id] = Vector3(float(a[0]), float(a[1]), float(a[2]))
		_abstract[id] = bool(p.get("abstract", false))
		_settlement[id] = str(p.get("settlement", ""))
	var graph: Dictionary = region.get("road_graph", {})
	for raw: Variant in graph.get("edges", []):
		var e: Array = raw
		var from_id: String = str(e[0])
		var to_id: String = str(e[1])
		# Abstract POIs are off the map (Tom Bombadil's house): never routable.
		if not _pos.has(from_id) or not _pos.has(to_id) or _abstract[from_id] or _abstract[to_id]:
			continue
		var length: float = (_pos[from_id] as Vector3).distance_to(_pos[to_id])
		if e.size() > EDGE_LENGTH_INDEX:
			length = float(e[EDGE_LENGTH_INDEX])
		var kind: String = str(e[2]) if e.size() > 2 else "path"
		_link(from_id, to_id, length, kind)
		_link(to_id, from_id, length, kind)


func _link(a: String, b: String, length: float, kind: String) -> void:
	if not _adj.has(a):
		_adj[a] = []
	(_adj[a] as Array).append({"to": b, "len": length, "kind": kind})


# --- queries ---------------------------------------------------------------

func has_poi(id: String) -> bool:
	return _pos.has(id)


func is_abstract(id: String) -> bool:
	return bool(_abstract.get(id, false))


# True when the POI has at least one road/path edge.
func is_routable(id: String) -> bool:
	return _adj.has(id)


func poi_pos(id: String) -> Vector3:
	return _pos.get(id, Vector3.ZERO)


func settlement_of(id: String) -> String:
	return str(_settlement.get(id, ""))


func poi_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _pos:
		out.append(str(k))
	return out


func edge_length(a: String, b: String) -> float:
	for e: Variant in _adj.get(a, []):
		if (e as Dictionary)["to"] == b:
			return float((e as Dictionary)["len"])
	return -1.0


# Closest routable, non-abstract POI; where a character that "emerges" from an abstract
# place (the Old Forest, Bombadil's house) rejoins the map.
func nearest_routable(pos: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for id: String in _adj:
		var d: float = Vector2(pos.x, pos.z).distance_to(Vector2(_pos[id].x, _pos[id].z))
		if d < best_d:
			best_d = d
			best = id
	return best


# --- routing ---------------------------------------------------------------

# Dijkstra. The graph has dozens of nodes, so a linear scan beats a heap in clarity.
# Returns {} when either end is abstract/unknown or the ends are not connected.
func route(from_id: String, to_id: String) -> Dictionary:
	var key: String = from_id + ">" + to_id
	if _route_cache.has(key):
		return (_route_cache[key] as Dictionary).duplicate(true)
	var result: Dictionary = _dijkstra(from_id, to_id)
	_route_cache[key] = result
	return result.duplicate(true)


func _dijkstra(from_id: String, to_id: String) -> Dictionary:
	if not _adj.has(from_id) or not _adj.has(to_id):
		return {}
	var dist: Dictionary = {from_id: 0.0}
	var prev: Dictionary = {}
	var open: Array[String] = [from_id]
	while not open.is_empty():
		var cur: String = open[0]
		for n in open:
			if float(dist[n]) < float(dist[cur]):
				cur = n
		open.erase(cur)
		if cur == to_id:
			break
		for e: Variant in _adj[cur]:
			var ed: Dictionary = e
			var nd: float = float(dist[cur]) + float(ed["len"])
			var to: String = ed["to"]
			if not dist.has(to) or nd < float(dist[to]):
				dist[to] = nd
				prev[to] = cur
				if to not in open:
					open.append(to)
	if not dist.has(to_id):
		return {}
	var nodes: Array[String] = [to_id]
	while nodes[0] != from_id:
		nodes.push_front(str(prev[nodes[0]]))
	var cum: Array[float] = [0.0]
	for i in range(1, nodes.size()):
		cum.append(cum[i - 1] + edge_length(nodes[i - 1], nodes[i]))
	return {"nodes": nodes, "cum": cum, "length": cum[cum.size() - 1]}


# Distance along the route at which `node` is reached, or -1 if the route avoids it.
func distance_to_node(r: Dictionary, node: String) -> float:
	var nodes: Array = r.get("nodes", [])
	var i: int = nodes.find(node)
	return -1.0 if i < 0 else float((r["cum"] as Array)[i])


# Position `s` metres along a route. Exactly on a route end gives the POI form so callers
# can tell "at a place" from "between places".
func locate(r: Dictionary, s: float) -> Dictionary:
	var nodes: Array = r["nodes"]
	var cum: Array = r["cum"]
	var length: float = float(r["length"])
	if nodes.size() == 1 or s <= 0.0:
		return {"poi": nodes[0], "pos": poi_pos(nodes[0])}
	if s >= length:
		var last: String = nodes[nodes.size() - 1]
		return {"poi": last, "pos": poi_pos(last)}
	var i: int = 1
	while float(cum[i]) < s:
		i += 1
	var seg_len: float = float(cum[i]) - float(cum[i - 1])
	var t: float = (s - float(cum[i - 1])) / seg_len if seg_len > 0.0 else 0.0
	return {"edge": [nodes[i - 1], nodes[i]], "t": t, "pos": edge_pos(str(nodes[i - 1]), str(nodes[i]), t)}


func edge_pos(a: String, b: String, t: float) -> Vector3:
	return poi_pos(a).lerp(poi_pos(b), clampf(t, 0.0, 1.0))


# Back-conversion for a stored position ref (e.g. a saved {"edge","t"}).
func world_pos(ref: Dictionary) -> Vector3:
	if ref.has("edge"):
		var e: Array = ref["edge"]
		return edge_pos(str(e[0]), str(e[1]), float(ref.get("t", 0.0)))
	return poi_pos(str(ref.get("poi", "")))
