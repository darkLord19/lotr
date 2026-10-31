class_name BenchRunner
extends Node
## Frame-time benchmark. Flies a camera along a route from config/bench.json through the real
## world scene and logs frame times and memory. Args after `--`: --route=<name> --out=<abs csv>
## [--max-seconds=<n>] [--weather=<state>] [--date=<iso>]. Exit code 0 = targets met, 3 = missed.
## Run through tools/bench.sh.

const EXIT_BAD_ARGS: int = 2
const EXIT_MISSED: int = 3
const WORLD_SCENE: String = "res://world/world_root.tscn"
const REGION_PATH: String = "res://content/regions/eriador_west.json"
const GIB: float = 1073741824.0
const MIB: float = 1048576.0

var _route: Dictionary = {}
var _path: Array[Vector2] = []
var _speed: float = 10.0
var _eye: float = 1.7
var _out_path: String = ""
var _max_seconds: float = -1.0
var _warmup: float = 5.0
var _targets: Dictionary = {}

var _world: WorldRoot
var _camera: Camera3D
var _dist: float = 0.0
var _total: float = 0.0
var _elapsed: float = 0.0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _rows: PackedStringArray = PackedStringArray()
var _peak_mem: float = 0.0
var _peak_vram: float = 0.0
var _peak_draws: float = 0.0
var _next_sample: float = 0.0
var _running: bool = false


func _ready() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var routes: Dictionary = Config.get_value("bench.routes", {})
	var route_name: String = String(args.get("route", ""))
	if not routes.has(route_name):
		printerr("Bench: unknown route '%s' (have: %s)" % [route_name, ", ".join(routes.keys())])
		get_tree().quit(EXIT_BAD_ARGS)
		return
	_route = routes[route_name]
	_out_path = String(args.get("out", "user://bench_%s.csv" % route_name))
	_max_seconds = float(args.get("max-seconds", "-1"))
	_warmup = float(Config.get_value("bench.warmup_seconds", 5.0))
	_targets = Config.get_value("bench.targets", {})
	_speed = float(_route.get("speed_mps", 10.0))
	_eye = float(_route.get("eye_height_m", 1.7))
	var date: String = String(args.get("date", _route.get("date", "")))
	if not date.is_empty():
		WorldClock.now = GameDate.parse(date)
	WorldClock.pause(&"bench")
	_path = _resolve_waypoints(_route.get("waypoints", []))
	if _path.size() < 2:
		printerr("Bench: route '%s' has fewer than 2 waypoints" % route_name)
		get_tree().quit(EXIT_BAD_ARGS)
		return
	for i in range(1, _path.size()):
		_total += _path[i - 1].distance_to(_path[i])
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldRoot
	add_child(_world)
	_camera = _world.camera
	var weather := WeatherDayNight.new()
	weather.name = "WeatherDayNight"
	weather.sun = _world.sun
	weather.world_environment = _world.world_environment
	weather.forced_state = StringName(String(args.get("weather", _route.get("weather", ""))))
	weather.minute_override = WorldClock.now
	_world.add_child(weather)
	_place_camera(0.0)
	_rows.append("t_s,fps,frame_ms,mem_mib,vram_mib,draw_calls,objects,dist_m")
	print("BENCH_START route=%s length=%.0f m speed=%.1f m/s window=%s" % [route_name, _total, _speed, get_window().size])
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed < _warmup:
		_place_camera(0.0)
		return
	var t: float = _elapsed - _warmup
	_dist += _speed * delta
	_frame_ms.append(delta * 1000.0)
	var mem: float = float(OS.get_static_memory_usage())
	var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	_peak_mem = maxf(_peak_mem, mem)
	_peak_vram = maxf(_peak_vram, vram)
	_peak_draws = maxf(_peak_draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if t >= _next_sample:
		_next_sample = t + 1.0
		_rows.append("%.1f,%d,%.2f,%.0f,%.0f,%d,%d,%.0f" % [t, Engine.get_frames_per_second(), delta * 1000.0, mem / MIB, vram / MIB,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), _dist])
	_place_camera(_dist)
	if _dist >= _total or (_max_seconds > 0.0 and t >= _max_seconds):
		_finish()


## Camera at `dist` metres along the route, eye above the terrain, looking along the heading.
func _place_camera(dist: float) -> void:
	var p: Vector2 = _path[0]
	var ahead: Vector2 = _path[1]
	var left: float = dist
	for i in range(1, _path.size()):
		var seg: float = _path[i - 1].distance_to(_path[i])
		p = _path[i - 1]
		ahead = _path[i]
		if left <= seg or i == _path.size() - 1:
			p = p.lerp(ahead, clampf(left / maxf(seg, 0.001), 0.0, 1.0))
			break
		left -= seg
	_camera.global_position = Vector3(p.x, _world.height_at(p.x, p.y) + _eye, p.y)
	var heading: Vector2 = (ahead - p).normalized() if ahead.distance_to(p) > 0.01 else Vector2.RIGHT
	_camera.look_at(_camera.global_position + Vector3(heading.x, -0.03, heading.y), Vector3.UP)


func _resolve_waypoints(raw: Array) -> Array[Vector2]:
	var pois: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION_PATH))
	if parsed is Dictionary:
		for poi: Dictionary in (parsed as Dictionary).get("pois", []):
			pois[String(poi["id"])] = Vector2(float(poi["pos"][0]), float(poi["pos"][2]))
	var out: Array[Vector2] = []
	for w: Variant in raw:
		if w is Array:
			out.append(Vector2(float((w as Array)[0]), float((w as Array)[1])))
		elif pois.has(String(w)):
			out.append(pois[String(w)])
		else:
			printerr("Bench: unknown waypoint %s" % w)
	return out


func _finish() -> void:
	_running = false
	var summary: Dictionary = summarise(_frame_ms)
	summary["peak_mem_gb"] = _peak_mem / GIB
	summary["peak_vram_gb"] = _peak_vram / GIB
	summary["peak_draw_calls"] = _peak_draws
	var ok: bool = meets_targets(summary, _targets)
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_rows) + "\n")
	print("BENCH_RESULT avg_fps=%.1f p1_low_fps=%.1f worst_ms=%.1f frames=%d peak_mem_gb=%.2f peak_vram_gb=%.2f peak_draws=%d verdict=%s" % [
			summary["avg_fps"], summary["p1_low_fps"], summary["worst_ms"], summary["frames"], summary["peak_mem_gb"], summary["peak_vram_gb"],
			int(summary["peak_draw_calls"]), "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else EXIT_MISSED)


## avg fps over the whole run; 1% low = fps of the mean of the slowest 1% of frames.
static func summarise(frame_ms: PackedFloat32Array) -> Dictionary:
	var n: int = frame_ms.size()
	if n == 0:
		return {"avg_fps": 0.0, "p1_low_fps": 0.0, "worst_ms": 0.0, "frames": 0}
	var sorted: PackedFloat32Array = frame_ms.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v in sorted:
		total += v
	var tail: int = maxi(1, int(ceil(n * 0.01)))
	var tail_sum: float = 0.0
	for i in range(n - tail, n):
		tail_sum += sorted[i]
	return {
		"avg_fps": 1000.0 * n / total,
		"p1_low_fps": 1000.0 / (tail_sum / tail),
		"worst_ms": sorted[n - 1],
		"frames": n,
	}


static func meets_targets(summary: Dictionary, targets: Dictionary) -> bool:
	return float(summary["avg_fps"]) >= float(targets.get("avg_fps", 0.0)) \
			and float(summary["p1_low_fps"]) >= float(targets.get("p1_low_fps", 0.0)) \
			and float(summary.get("peak_mem_gb", 0.0)) < float(targets.get("peak_mem_gb", INF))


static func _parse(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in argv:
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
