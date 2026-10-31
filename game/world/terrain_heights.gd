class_name TerrainHeights
extends RefCounted
# CPU copy of the engine terrain (height_4m.r16 + splat_4m.png). World coordinates equal region
# coordinates: x east, z SOUTH, origin at the north-west corner (see docs/REVIEW.md, M1-T03).

const U16_MAX: float = 65535.0
const BYTES_PER_SAMPLE: int = 2

static var _shared: TerrainHeights

var cols: int = 0
var rows: int = 0
var metres_per_px: float = 4.0
var height_max_m: float = 320.0
var splat: Image
var _h: PackedFloat32Array = PackedFloat32Array()


# Decoding 2M samples takes a moment, so every consumer shares one instance.
static func shared() -> TerrainHeights:
	if _shared == null:
		var t := TerrainHeights.new()
		if t.load_from_config():
			_shared = t
		else:
			return null
	return _shared


func load_from_config() -> bool:
	var dir: String = String(Config.get_value("world.terrain.data_dir", ""))
	var size_px: Array = Config.get_value("world.terrain.size_px", [0, 0])
	cols = int(size_px[0])
	rows = int(size_px[1])
	metres_per_px = float(Config.get_value("world.terrain.metres_per_px", 4.0))
	height_max_m = float(Config.get_value("height_max_m", 320.0))
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(String(Config.get_value("world.terrain.height_file", ""))))
	if raw.size() != cols * rows * BYTES_PER_SAMPLE:
		push_error("TerrainHeights: height file has %d bytes, expected %d" % [raw.size(), cols * rows * BYTES_PER_SAMPLE])
		return false
	_h.resize(cols * rows)
	var scale: float = height_max_m / U16_MAX
	for i in _h.size():
		_h[i] = raw.decode_u16(i * BYTES_PER_SAMPLE) * scale
	# Imported (not raw-loaded) so it also works in exported builds. splat_4m.png.import turns off
	# fix_alpha_border, which would otherwise wipe the RGB data wherever the alpha (field) channel is 0.
	var tex: Texture2D = load(dir.path_join(String(Config.get_value("world.terrain.splat_file", "")))) as Texture2D
	splat = tex.get_image() if tex != null else null
	return splat != null


func size_m() -> Vector2:
	return Vector2(cols, rows) * metres_per_px


# Bilinear. Positions outside the region clamp to the border so streaming near an edge never reads garbage.
func height_at(x: float, z: float) -> float:
	var fx: float = clampf(x / metres_per_px, 0.0, cols - 1.0)
	var fz: float = clampf(z / metres_per_px, 0.0, rows - 1.0)
	var ix: int = mini(int(fx), cols - 2)
	var iz: int = mini(int(fz), rows - 2)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var i: int = iz * cols + ix
	var top: float = lerpf(_h[i], _h[i + 1], tx)
	var bottom: float = lerpf(_h[i + cols], _h[i + cols + 1], tx)
	return lerpf(top, bottom, tz)


# Surface normal from central differences; `step` trades detail for stability on coarse LODs.
func normal_at(x: float, z: float, step: float) -> Vector3:
	var dx: float = height_at(x + step, z) - height_at(x - step, z)
	var dz: float = height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


# Splat weights at a world position: (path, riverbank, forest floor, field). Grass is the remainder.
func splat_at(x: float, z: float) -> Color:
	var px: int = clampi(int(x / metres_per_px), 0, cols - 1)
	var pz: int = clampi(int(z / metres_per_px), 0, rows - 1)
	return splat.get_pixel(px, pz)
