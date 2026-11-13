# The throttle's afterburner detent (docs/controls.md §4 "Detent = MIL", modern-iaf/docs/front-end.md §9.2) end to
# end on the 6-DoF engine: a fake joystick's lever set at its detent (Joystick.detent_choice, the Devices pages'
# call), the setting through settings.cfg (write_config / read_config), then the lever around the detent through the
# poller's GEV 9 into IafFlight: below and at the detent and in its hold dry (at most MIL, no afterburner stage),
# past it and at full travel the afterburner. Both games: this file in reborn, modern-iaf/tests/test_detent.gd in the
# sim.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_detent.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const DETENT := 82


func joy() -> Node:
	return root.get_node("Joystick")


## The lever at raw position t (0 idle .. 100 forward, Joystick.raw_throttle): Godot reads forward as −1.
func lever(t: int) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = 2
	e.axis_value = (100 - t) / 50.0 - 1.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The flight's engine after 40 s with the lever at raw t, through the poller as the flight scene takes it
## (terrain_view.gd _command 9: throttle = p1 · 0.01): [throttle, afterburner stage].
func engine_at(flight: Object, t: int) -> Array:
	lever(t)
	for e in joy().poll():
		if int(e[0]) == 9:
			flight.set_controls(Vector2.ZERO, 0.0, int(e[1]) * 0.01, 0.0, false, false)
	for i in 160:
		flight.step(0.25)
	var st: Dictionary = flight.state()
	return [float(st.throttle), int(st.afterburner)]


func run() -> void:
	var s := settings()
	var js := joy()
	s.flight_model = "6dof"
	s.f16_variant = "sufa"
	var dir: String = s.sixdof_data() if s.sixdof_built() else ""
	if dir == "" or not ClassDB.class_exists("IafFlight"):
		print("NEEDS DATA: Modern IAF's 6-DoF data (./modern-iaf-setup) and the extension")
		return
	js.fake_devices = [0]
	js.tune = []
	s.throttle = 1
	s.joy_axes = [0, 1, 2, 3, -1]
	await frames(2)  # the autoload sees the device
	# The Devices page: the lever in its click, Set at lever; then saved and read back.
	lever(DETENT)
	s.throttle_detent = js.detent_choice(true)
	check(s.throttle_detent == DETENT, "Set at lever stores the lever's raw position (%d)" % s.throttle_detent)
	var cfg: ConfigFile = s.write_config()
	s.throttle_detent = -1
	s.read_config(cfg)
	check(s.throttle_detent == DETENT, "the detent survives settings.cfg (%d)" % s.throttle_detent)

	var flight: Object = ClassDB.instantiate("IafFlight")
	var flags := {"airborne": true, "engine_on": true, "real_data": true, "f16_variant": "sufa", "sixdof_data": dir}
	var err: String = flight.start(s.own_dir(), "F-16", Vector3(0, 4000, 0), Vector3.ZERO, Vector3(0, 0, -200), flags)
	check(err == "" and str(flight.state().get("model", "")) == "6dof", "the Sufa flies the 6-DoF (%s)" % err)
	for c in [[60, false], [DETENT - 1, false], [DETENT, true], [DETENT + 2, true], [DETENT + 3, true]]:
		var r := engine_at(flight, c[0])
		var mil: bool = c[1]
		check(
			r[1] == 0 and (is_equal_approx(r[0], 0.74) if mil else r[0] < 0.74),
			"lever %d: %s, no afterburner (throttle %.3f, stage %d)" % [c[0], "MIL" if mil else "dry", r[0], r[1]]
		)
	for t in [DETENT + 5, 100]:
		var r := engine_at(flight, t)
		check(r[0] >= 0.78 and r[1] >= 1, "lever %d: afterburner (throttle %.3f, stage %d)" % [t, r[0], r[1]])
	# No detent: the linear lever as before (74 MIL dry, full travel the afterburner).
	s.throttle_detent = -1
	var lin := engine_at(flight, 74)
	check(lin[1] == 0, "no detent: lever 74 is MIL, dry (stage %d)" % lin[1])
	lin = engine_at(flight, 100)
	check(lin[1] == 2, "no detent: full travel, afterburner stage 2 (%d)" % lin[1])
	js.fake_devices = []
