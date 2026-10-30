extends GutTest


func test_zoom_is_clamped_to_1_5_8_m() -> void:
	assert_eq(CameraRig.clamp_zoom(0.1), 1.5)
	assert_eq(CameraRig.clamp_zoom(100.0), 8.0)
	assert_eq(CameraRig.clamp_zoom(4.0), 4.0)


func test_yaw_for_direction_follows_engine_convention() -> void:
	assert_almost_eq(CameraRig.yaw_for_direction(Vector3(0, 0, -1)), 0.0, 0.0001, "north")
	assert_almost_eq(CameraRig.yaw_for_direction(Vector3(1, 0, 0)), -PI / 2.0, 0.0001, "east")
	assert_almost_eq(absf(CameraRig.yaw_for_direction(Vector3(0, 0, 1))), PI, 0.0001, "south")


func test_orbit_clamps_pitch_and_zoom_steps() -> void:
	var rig: CameraRig = autofree(CameraRig.new())
	rig.orbit(Vector2(0, -100000.0), 1.0)
	assert_almost_eq(rig.pitch, deg_to_rad(float(Config.get_value("player.camera.pitch_max_deg"))), 0.0001)
	rig.orbit(Vector2(0, 100000.0), 1.0)
	assert_almost_eq(rig.pitch, deg_to_rad(float(Config.get_value("player.camera.pitch_min_deg"))), 0.0001)
	rig.zoom_by(100.0)
	assert_eq(rig._zoom_goal, 8.0)


func test_every_binding_in_controls_json_parses() -> void:
	var table: Dictionary = Config.get_value("controls.bindings")
	for action: String in table:
		for token: Variant in table[action]:
			assert_not_null(InputSetup.parse_binding(str(token)), "%s: %s" % [action, token])
	assert_null(InputSetup.parse_binding("NotAKey"))


func test_apply_creates_actions_and_physical_keys() -> void:
	InputSetup.apply()
	for a: String in ["move_forward", "run", "crouch", "jump", "interact", "inventory", "journal", "debug_console"]:
		assert_true(InputMap.has_action(a), a)
	var ev: InputEventKey = InputMap.action_get_events(&"move_forward")[0]
	assert_eq(ev.physical_keycode, KEY_W)
