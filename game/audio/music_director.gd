class_name MusicDirector
extends Node
## Thin player around MusicLogic. All stems are phase-locked inside one AudioStreamSynchronized so
## "crossfading" is just easing each stem's volume; the loops are the same length by construction.
## The world scene feeds it through set_place / set_weather / report_rider.

var all_cfg: Dictionary = {}
var logic: MusicLogic
var inputs: MusicLogic.Inputs = MusicLogic.Inputs.new()
## Eased gain per stem (0..1) and the latest target decision, exposed for tests and debug overlays.
var gains: Dictionary = {}
var decision: MusicLogic.Decision = MusicLogic.Decision.new()
## >= 0 pins the hour (tests, cutscenes); negative follows WorldClock.
var hour_override: float = -1.0

var _player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _slot: Dictionary = {}


func _ready() -> void:
	all_cfg = AudioFade.load_config()
	logic = MusicLogic.new(all_cfg.get("music", {}) as Dictionary)
	_build_stream()


func _process(delta: float) -> void:
	tick(delta)


func set_place(region: StringName, settlement: StringName, area: StringName = &"", in_inn: bool = false) -> void:
	inputs.region = region
	inputs.settlement = settlement
	inputs.area = area
	inputs.in_inn = in_inn


func set_weather(state: StringName) -> void:
	inputs.weather_state = state


## Called by the rider layer each frame the nearest rider is known (state: RiderAI.State, eye: EyeState).
func report_rider(distance_m: float, state: int, eye: int) -> void:
	inputs.rider_distance_m = distance_m
	inputs.rider_state = state
	inputs.eye_state = eye


func clear_rider() -> void:
	inputs.rider_distance_m = INF
	inputs.rider_state = MusicLogic.NO_RIDER_STATE
	inputs.eye_state = RiderPerception.EyeState.HIDDEN


func tick(delta: float) -> void:
	if logic == null:
		return
	inputs.hour = hour_override if hour_override >= 0.0 else AudioFade.hour_from_minutes(WorldClock.now)
	decision = logic.update(inputs, delta)
	for stem: StringName in decision.stem_gains:
		var g: float = AudioFade.step(float(gains.get(stem, 0.0)), float(decision.stem_gains[stem]), delta, decision.fade_seconds)
		gains[stem] = g
		_apply(stem, g)


func _build_stream() -> void:
	var dir: String = str((all_cfg.get("dirs", {}) as Dictionary).get("music", ""))
	var stems: Dictionary = (all_cfg.get("music", {}) as Dictionary).get("stems", {}) as Dictionary
	var silent_db: float = float(all_cfg.get("silent_db", -60.0))
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = stems.size()
	var i: int = 0
	for stem: String in stems:
		var stream: AudioStream = AudioFade.load_looping(dir + str(stems[stem]))
		if stream != null:
			_sync.set_sync_stream(i, stream)
			_sync.set_sync_stream_volume(i, silent_db)
		_slot[StringName(stem)] = i
		i += 1
	_player = AudioStreamPlayer.new()
	_player.name = "Stems"
	_player.stream = _sync
	_player.volume_db = float((all_cfg.get("bus_db", {}) as Dictionary).get("music", 0.0))
	add_child(_player)
	_player.play()


func _apply(stem: StringName, g: float) -> void:
	if _sync == null or not _slot.has(stem):
		return
	var db: float = AudioFade.to_db(g, float(all_cfg.get("silent_linear", 0.001)), float(all_cfg.get("silent_db", -60.0)))
	_sync.set_sync_stream_volume(int(_slot[stem]), db)
