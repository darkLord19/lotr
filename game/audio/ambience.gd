class_name Ambience
extends Node
## Thin player around AmbienceLogic: one looping AudioStreamPlayer per layer, gains eased toward
## the logic's targets so location/weather/time changes crossfade instead of popping.
## The world scene feeds it through set_location / set_weather / set_threat (no scene references).

## The whole "audio" config section; `cfg` is its "ambience" part.
var all_cfg: Dictionary = {}
var cfg: Dictionary = {}
var inputs: AmbienceLogic.Inputs = AmbienceLogic.Inputs.new()
## Current eased gain per layer (0..1), exposed for tests and debug overlays.
var gains: Dictionary = {}
var targets: Dictionary = {}
## >= 0 pins the hour (tests, cutscenes); negative follows WorldClock.
var hour_override: float = -1.0

var _players: Dictionary = {}


func _ready() -> void:
	all_cfg = AudioFade.load_config()
	cfg = all_cfg.get("ambience", {}) as Dictionary
	_build_players()


func _process(delta: float) -> void:
	tick(delta)


func set_location(location: StringName) -> void:
	inputs.location = location


func set_weather(state: StringName, rain_intensity: float = -1.0) -> void:
	inputs.weather_state = state
	inputs.rain_intensity = rain_intensity


func set_threat(level: int) -> void:
	inputs.threat = level


func tick(delta: float) -> void:
	inputs.hour = hour_override if hour_override >= 0.0 else _clock_hour()
	targets = AmbienceLogic.layer_gains(inputs, cfg)
	var fade: float = float(cfg.get("fade_seconds", 4.0))
	for layer: StringName in AmbienceLogic.LAYERS:
		var g: float = AudioFade.step(float(gains.get(layer, 0.0)), float(targets[layer]), delta, fade)
		gains[layer] = g
		_apply(layer, g)


func _clock_hour() -> float:
	return AudioFade.hour_from_minutes(WorldClock.now)


func _build_players() -> void:
	var dir: String = str((all_cfg.get("dirs", {}) as Dictionary).get("ambience", ""))
	var files: Dictionary = cfg.get("files", {}) as Dictionary
	for layer: StringName in AmbienceLogic.LAYERS:
		var path: String = str(cfg.get("heartbeat_file", "")) if layer == &"heartbeat" else dir + str(files.get(layer, ""))
		var stream: AudioStream = AudioFade.load_looping(path)
		if stream == null:
			continue
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = String(layer)
		p.stream = stream
		p.volume_db = float(all_cfg.get("silent_db", -60.0))
		add_child(p)
		_players[layer] = p


func _apply(layer: StringName, g: float) -> void:
	var p: AudioStreamPlayer = _players.get(layer, null) as AudioStreamPlayer
	if p == null:
		return
	var silent_lin: float = float(all_cfg.get("silent_linear", 0.001))
	var silent_db: float = float(all_cfg.get("silent_db", -60.0))
	var bus_db: float = float((all_cfg.get("bus_db", {}) as Dictionary).get("ambience", 0.0))
	p.volume_db = AudioFade.to_db(g, silent_lin, silent_db) + bus_db if g > silent_lin else silent_db
	# Stopped layers cost nothing; restart them when they become audible.
	if g > silent_lin and not p.playing:
		p.play()
	elif g <= silent_lin and p.playing:
		p.stop()
