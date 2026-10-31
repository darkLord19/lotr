class_name RiderAI
extends RefCounted
## Black Rider state machine: patrol -> sniff -> approach -> interrogate.
## Driven entirely by explicit inputs (see step) so it can be unit-tested without a scene.

enum State { PATROL, SNIFF, APPROACH, INTERROGATE }

signal state_changed(old_state: State, new_state: State)
## Fired once when the rider reaches the player; the caller runs the interrogation + soft failure.
signal caught

var state: State = State.PATROL
var position: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3.FORWARD
## Where the rider should head while patrolling (follows the timeline position).
var patrol_target: Vector3 = Vector3.ZERO
## Latest perception, kept for the HUD eye icon and the fear aura.
var last_result: RiderPerception.Result = RiderPerception.Result.new()

var _sniff_timer: float = 0.0
var _lost_timer: float = 0.0
var _scan_base_facing: Vector3 = Vector3.FORWARD


func step(delta: float, target: RiderPerception.Target, is_night: bool) -> void:
	last_result = RiderPerception.evaluate(position, facing, target, is_night)
	match state:
		State.PATROL:
			_patrol(delta)
		State.SNIFF:
			_sniff(delta)
		State.APPROACH:
			_approach(delta, target)
		State.INTERROGATE:
			pass


func _patrol(delta: float) -> void:
	if last_result.detected():
		_enter_sniff()
		return
	_move_toward(patrol_target, RiderPerception.cfg("patrol_speed_mps", 2.5), delta, RiderPerception.cfg("patrol_arrive_m", 3.0))


func _sniff(delta: float) -> void:
	_sniff_timer += delta
	# Head scan: sweep side to side so the vision cone actually moves while standing still.
	var period: float = RiderPerception.cfg("sniff_scan_period_s", 3.0)
	var sweep: float = sin(_sniff_timer / period * TAU) * deg_to_rad(RiderPerception.cfg("sniff_scan_half_angle_deg", 60.0))
	facing = _scan_base_facing.rotated(Vector3.UP, sweep)
	if _sniff_timer < RiderPerception.cfg("sniff_duration_s", 6.0):
		return
	# Player must still be detectable after the full sniff; ducking away in time saves them.
	if last_result.detected():
		_lost_timer = 0.0
		_set_state(State.APPROACH)
	else:
		_set_state(State.PATROL)


func _approach(delta: float, target: RiderPerception.Target) -> void:
	if last_result.detected():
		_lost_timer = 0.0
	else:
		_lost_timer += delta
		if _lost_timer >= RiderPerception.cfg("lose_track_s", 8.0):
			_set_state(State.PATROL)
			return
	var reach: float = RiderPerception.cfg("interrogate_distance_m", 2.5)
	_move_toward(target.position, RiderPerception.cfg("approach_speed_mps", 5.0), delta, reach)
	if Vector2(position.x - target.position.x, position.z - target.position.z).length() <= reach:
		_set_state(State.INTERROGATE)
		caught.emit()


func _enter_sniff() -> void:
	_sniff_timer = 0.0
	_scan_base_facing = facing
	_set_state(State.SNIFF)


## Called by the wrapper once the player has been dealt with so the rider can ride on.
func release() -> void:
	if state == State.INTERROGATE:
		_set_state(State.PATROL)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old: State = state
	state = new_state
	state_changed.emit(old, new_state)


func _move_toward(dest: Vector3, speed: float, delta: float, stop_within: float) -> void:
	var to_dest: Vector3 = dest - position
	to_dest.y = 0.0
	var dist: float = to_dest.length()
	if dist <= stop_within or dist < 0.0001:
		return
	var dir: Vector3 = to_dest / dist
	# Turn rate is capped so a rider cannot snap its cone onto a fleeing player.
	var max_turn: float = RiderPerception.cfg("turn_speed_rad_s", 3.0) * delta
	var flat_facing: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length_squared() < 0.0001:
		facing = dir
	else:
		var angle: float = flat_facing.angle_to(dir)
		if angle <= max_turn:
			facing = dir
		else:
			var sign_y: float = signf(flat_facing.cross(dir).y)
			facing = flat_facing.normalized().rotated(Vector3.UP, max_turn * (sign_y if sign_y != 0.0 else 1.0))
	position += dir * minf(speed * delta, dist)


## HUD eye icon data: hidden / seen / sniffed.
func eye_state() -> RiderPerception.EyeState:
	return last_result.eye
