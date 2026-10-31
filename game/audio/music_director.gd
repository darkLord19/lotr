class_name MusicDirector
extends Node
## Dual-path music player driven by MusicLogic.
## 1. Phase-locked stems via AudioStreamSynchronized (default).
## 2. Whole-cue music path (MusicGen cues) crossfading between two players.
## The world scene feeds it through set_place / set_weather / report_rider.

var all_cfg: Dictionary = {}
var logic: MusicLogic
var inputs: MusicLogic.Inputs = MusicLogic.Inputs.new()
## Eased gain per stem (0..1) and the latest target decision, exposed for tests and debug overlays.
var gains: Dictionary = {}
var decision: MusicLogic.Decision = MusicLogic.Decision.new()
## >= 0 pins the hour (tests, cutscenes); negative follows WorldClock.
var hour_override: float = -1.0
## Toggle between stem playback and whole-cue crossfade playback.
var use_whole_cues: bool = false

# Whole-cue playback state
var current_cue: StringName = &""
var cue_gain: float = 0.0
var outgoing_cue: StringName = &""
var outgoing_cue_gain: float = 0.0

var _player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _slot: Dictionary = {}

var _cue_player_a: AudioStreamPlayer
var _cue_player_b: AudioStreamPlayer
var _active_cue_player: AudioStreamPlayer
var _fading_cue_player: AudioStreamPlayer


func _ready() -> void:
	all_cfg = AudioFade.load_config()
	var music_cfg: Dictionary = all_cfg.get("music", {}) as Dictionary
	logic = MusicLogic.new(music_cfg)
	use_whole_cues = bool(music_cfg.get("use_whole_cues", false))
	_build_stream()
	_build_cue_players()


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

	if use_whole_cues:
		if _player != null:
			_player.volume_db = float(all_cfg.get("silent_db", -60.0))
		_tick_whole_cues(delta)
	else:
		if _player != null:
			_player.volume_db = float((all_cfg.get("bus_db", {}) as Dictionary).get("music", 0.0))
		_tick_stems(delta)


func _tick_stems(delta: float) -> void:
	for stem: StringName in decision.stem_gains:
		var g: float = AudioFade.step(float(gains.get(stem, 0.0)), float(decision.stem_gains[stem]), delta, decision.fade_seconds)
		gains[stem] = g
		_apply(stem, g)


func _tick_whole_cues(delta: float) -> void:
	if decision.cue != current_cue:
		_switch_whole_cue(decision.cue)
	cue_gain = AudioFade.step(cue_gain, 1.0, delta, decision.fade_seconds)
	outgoing_cue_gain = AudioFade.step(outgoing_cue_gain, 0.0, delta, decision.fade_seconds)

	var bus_db: float = float((all_cfg.get("bus_db", {}) as Dictionary).get("music", 0.0))
	var silent_lin: float = float(all_cfg.get("silent_linear", 0.001))
	var silent_db: float = float(all_cfg.get("silent_db", -60.0))

	if _active_cue_player != null:
		_active_cue_player.volume_db = AudioFade.to_db(cue_gain, silent_lin, silent_db) + bus_db
		if cue_gain > silent_lin and not _active_cue_player.playing:
			_active_cue_player.play()
	if _fading_cue_player != null:
		_fading_cue_player.volume_db = AudioFade.to_db(outgoing_cue_gain, silent_lin, silent_db) + bus_db
		if outgoing_cue_gain <= silent_lin and _fading_cue_player.playing:
			_fading_cue_player.stop()


func _switch_whole_cue(new_cue: StringName) -> void:
	outgoing_cue = current_cue
	outgoing_cue_gain = cue_gain
	current_cue = new_cue
	cue_gain = 0.0

	_fading_cue_player = _active_cue_player
	_active_cue_player = _cue_player_b if _active_cue_player == _cue_player_a else _cue_player_a

	var file_name: String = get_cue_file(new_cue)
	if file_name.is_empty():
		return
	var dir: String = str((all_cfg.get("dirs", {}) as Dictionary).get("cues", "res://assets/audio/music/cues/"))
	var path: String = dir + file_name
	var stream: AudioStream = AudioFade.load_looping(path)
	if stream != null and _active_cue_player != null:
		_active_cue_player.stream = stream
		_active_cue_player.volume_db = float(all_cfg.get("silent_db", -60.0))
		_active_cue_player.play()


func get_cue_file(cue_name: StringName) -> String:
	var music_cfg: Dictionary = all_cfg.get("music", {}) as Dictionary
	var whole_cues: Dictionary = music_cfg.get("whole_cues", {}) as Dictionary
	if whole_cues.has(String(cue_name)):
		return str(whole_cues[String(cue_name)])
	var cues: Dictionary = music_cfg.get("cues", {}) as Dictionary
	if cues.has(String(cue_name)) and cues[String(cue_name)] is Dictionary:
		var d: Dictionary = cues[String(cue_name)] as Dictionary
		if d.has("file"):
			return str(d["file"])
	return ""


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


func _build_cue_players() -> void:
	_cue_player_a = AudioStreamPlayer.new()
	_cue_player_a.name = "CuePlayerA"
	add_child(_cue_player_a)
	_cue_player_b = AudioStreamPlayer.new()
	_cue_player_b.name = "CuePlayerB"
	add_child(_cue_player_b)
	_active_cue_player = _cue_player_a
	_fading_cue_player = _cue_player_b


func _apply(stem: StringName, g: float) -> void:
	if _sync == null or not _slot.has(stem):
		return
	var db: float = AudioFade.to_db(g, float(all_cfg.get("silent_linear", 0.001)), float(all_cfg.get("silent_db", -60.0)))
	_sync.set_sync_stream_volume(int(_slot[stem]), db)
