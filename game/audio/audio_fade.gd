class_name AudioFade
extends RefCounted
## Small helpers shared by the ambience and music players: linear gain ramps and linear->dB.


# Moves `current` toward `target` so a full 0..1 swing takes `fade_seconds`. A linear ramp in gain
# (not dB) keeps crossfades of two layers at roughly constant combined loudness.
static func step(current: float, target: float, delta: float, fade_seconds: float) -> float:
	if fade_seconds <= 0.0:
		return target
	return move_toward(current, target, delta / fade_seconds)


# Below `silent_linear` we report `silent_db` instead of -inf so players can be stopped cleanly.
static func to_db(linear: float, silent_linear: float, silent_db: float) -> float:
	if linear <= silent_linear:
		return silent_db
	return linear_to_db(linear)


static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/audio.json"))
	if parsed is Dictionary:
		return ((parsed as Dictionary).get("audio", {}) as Dictionary)
	return {}


# Loads an imported OGG and marks it looping; null (with a warning) if the asset is missing so a
# machine without the generated audio still boots.
static func load_looping(path: String) -> AudioStream:
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	if res == null:
		push_warning("AudioFade: missing audio asset %s" % path)
		return null
	if res is AudioStreamOggVorbis:
		var ogg: AudioStreamOggVorbis = (res as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		ogg.loop = true
		return ogg
	return res as AudioStream


# Hour of day (0..24) from the world clock minute counter.
static func hour_from_minutes(minutes: int) -> float:
	return float(GameDate.hour_of(minutes)) + float(GameDate.minute_of(minutes)) / 60.0
