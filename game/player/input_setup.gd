class_name InputSetup
extends RefCounted
## Builds InputMap actions from config/controls.json so no key is named in gameplay code.

const MOUSE_PREFIX: String = "mouse:"
const PHYSICAL_PREFIX: String = "phys:"
const DEFAULT_DEADZONE: float = 0.2

const MOUSE_BUTTONS: Dictionary = {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}


## Returns null for an unknown token so a typo in the config cannot crash the game.
static func parse_binding(token: String) -> InputEvent:
	var t: String = token.strip_edges()
	if t.begins_with(MOUSE_PREFIX):
		var name: String = t.substr(MOUSE_PREFIX.length()).to_lower()
		if not MOUSE_BUTTONS.has(name):
			return null
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTONS[name] as MouseButton
		return mb
	var physical: bool = t.begins_with(PHYSICAL_PREFIX)
	if physical:
		t = t.substr(PHYSICAL_PREFIX.length())
	var code: Key = OS.find_keycode_from_string(t)
	if code == KEY_NONE:
		return null
	var key := InputEventKey.new()
	if physical:
		key.physical_keycode = code
	else:
		key.keycode = code
	return key


## Creates/replaces every action listed in the config. Returns the action names that were set up.
static func apply(bindings: Dictionary = {}) -> Array[String]:
	var table: Dictionary = bindings if not bindings.is_empty() else Config.get_value("controls.bindings", {})
	var done: Array[String] = []
	for action: String in table:
		var name := StringName(action)
		if InputMap.has_action(name):
			InputMap.action_erase_events(name)
		else:
			InputMap.add_action(name, DEFAULT_DEADZONE)
		for token: Variant in (table[action] as Array):
			var ev: InputEvent = parse_binding(str(token))
			if ev == null:
				push_warning("InputSetup: unknown binding '%s' for action '%s'" % [token, action])
				continue
			InputMap.action_add_event(name, ev)
		done.append(action)
	return done
