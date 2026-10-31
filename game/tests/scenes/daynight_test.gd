extends Node3D
# Capture fixture for the day/night + weather node. Extra args (after `--`):
#   --weather=clear|overcast|light_rain|fog   force a state
#   --dawnfog                                 force the dawn river mist

@onready var weather: WeatherDayNight = $WeatherDayNight


func _ready() -> void:
	# Keep the clock still so a slow software-rendered capture shows the requested minute.
	if not WorldClock.is_paused():
		WorldClock.pause(&"daynight_test")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			weather.force(StringName(a.substr("--weather=".length())), weather.forced_dawn_fog)
		elif a == "--dawnfog":
			weather.forced_dawn_fog = true
