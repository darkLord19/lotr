class_name RiderPerception
extends RefCounted
## Pure perception maths for the Black Riders. No scene queries: the caller passes positions
## and flags so every rule is unit-testable. The scene layer supplies `has_line_of_sight`
## (a raycast) and `road_distance_m` (distance to the nearest road segment).
## NOTE: the scene-level check (player 10 m off the road crouched in bushes, rider passes) needs
## terrain and raycasts and is intentionally not covered here; see M1-T11 in PLAN.md.

enum EyeState { HIDDEN, SEEN, SNIFFED }

const CFG_PREFIX: String = "riders."

## What the riders can perceive about the player this frame.
class Target extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var crouched: bool = false
	## Max concealment of the vegetation volumes the player is inside (0 = open, 1 = invisible).
	var concealment: float = 0.0
	var road_distance_m: float = 0.0
	var has_line_of_sight: bool = true

	static func make(pos: Vector3, crouch: bool = false, conceal: float = 0.0, off_road_m: float = 0.0, los: bool = true) -> Target:
		var t: Target = Target.new()
		t.position = pos
		t.crouched = crouch
		t.concealment = conceal
		t.road_distance_m = off_road_m
		t.has_line_of_sight = los
		return t


class Result extends RefCounted:
	var seen: bool = false
	var sniffed: bool = false
	var eye: EyeState = EyeState.HIDDEN
	var distance: float = 0.0
	var vision_range: float = 0.0
	var sniff_radius: float = 0.0

	func detected() -> bool:
		return seen or sniffed


static func cfg(key: String, default: float) -> float:
	return float(Config.get_value(CFG_PREFIX + key, default))


## Vegetation volumes overlap; the densest one wins rather than stacking, so a hedge inside a
## forest does not make the player a ghost.
static func combine_concealment(volume_values: Array[float]) -> float:
	var best: float = 0.0
	for v: float in volume_values:
		best = maxf(best, v)
	return clampf(best, 0.0, 1.0)


## Crouching only helps when there is something to crouch behind.
static func effective_concealment(base: float, crouched: bool) -> float:
	if base <= 0.0:
		return 0.0
	var bonus: float = cfg("crouch_concealment_bonus", 0.25) if crouched else 0.0
	return clampf(base + bonus, 0.0, 1.0)


static func vision_range(concealment: float, is_night: bool) -> float:
	var r: float = cfg("vision_range_m", 40.0) * (1.0 - clampf(concealment, 0.0, 1.0))
	if is_night:
		r *= cfg("night_vision_range_factor", 0.5)
	return r


static func vision_half_angle_rad(is_night: bool) -> float:
	var a: float = deg_to_rad(cfg("vision_half_angle_deg", 45.0))
	if is_night:
		a *= cfg("night_vision_angle_factor", 0.6)
	return a


## Sniffing ignores line of sight and darkness but not stealth: hiding low in cover or
## staying far from the road reduces it once (the two do not stack).
static func sniff_radius(crouched_in_cover: bool, road_distance_m: float) -> float:
	var r: float = cfg("sniff_radius_m", 15.0)
	if crouched_in_cover or road_distance_m > cfg("sniff_off_road_m", 6.0):
		r *= cfg("sniff_reduced_factor", 0.5)
	return r


static func in_vision_cone(rider_pos: Vector3, rider_facing: Vector3, target_pos: Vector3, half_angle_rad: float) -> bool:
	var to_target: Vector3 = target_pos - rider_pos
	to_target.y = 0.0
	var facing: Vector3 = rider_facing
	facing.y = 0.0
	if to_target.length_squared() < 0.0001:
		return true
	if facing.length_squared() < 0.0001:
		return false
	return facing.angle_to(to_target) <= half_angle_rad


static func evaluate(rider_pos: Vector3, rider_facing: Vector3, target: Target, is_night: bool) -> Result:
	var res: Result = Result.new()
	res.distance = _flat_distance(rider_pos, target.position)
	var conceal: float = effective_concealment(target.concealment, target.crouched)
	res.vision_range = vision_range(conceal, is_night)
	res.sniff_radius = sniff_radius(target.crouched and target.concealment > 0.0, target.road_distance_m)
	res.seen = target.has_line_of_sight \
		and res.distance <= res.vision_range \
		and in_vision_cone(rider_pos, rider_facing, target.position, vision_half_angle_rad(is_night))
	res.sniffed = res.distance <= res.sniff_radius
	if res.seen:
		res.eye = EyeState.SEEN
	elif res.sniffed:
		res.eye = EyeState.SNIFFED
	return res


# --- fear aura ---------------------------------------------------------------

## 0 outside the aura, rising linearly to 1 on top of the rider.
static func fear_strength(distance: float) -> float:
	var radius: float = cfg("fear_radius_m", 8.0)
	if distance >= radius:
		return 0.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


## Multiplier on player movement speed.
static func fear_move_factor(distance: float) -> float:
	return lerpf(1.0, cfg("fear_min_move_factor", 0.5), fear_strength(distance))


## 0..max screen desaturation.
static func fear_desaturation(distance: float) -> float:
	return fear_strength(distance) * cfg("fear_max_desaturation", 0.8)


## 0..1 drive for the heartbeat audio layer (volume/tempo); audio itself comes later.
static func fear_heartbeat(distance: float) -> float:
	return fear_strength(distance)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
