# Keyboard stick (docs/controls.md, docs/flight-model.md §8): a pitch / roll key sets the stick at once
# to ±1 and its release to 0 (FUN_004e0b80 → GEV 1 → FUN_0059f3d0), the last key event wins, and the
# only smoothing is the flight model's lift ramp (G_Rate). Peak g of a Down-arrow (pull) tap in the
# F-16 at 350 kt, 10,000 ft, military power, both data sets.
extends "res://../tests/godot/base.gd"

const DT := 1.0 / 60.0


func set_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap_peak_g(tv: Node, real: bool, seconds: float) -> float:
	var install: String = Settings().assets_dir().path_join("install")
	tv.flight.start(install, "F-16", Vector3(0, 3048, 0), 0.0, 0.0, 0.0, Vector3(0, 0, -180.06), true, true, real)
	var fly := func(t: float) -> float:
		var peak := -INF
		for i in roundi(t / DT):
			tv._read_controls(DT)
			tv.flight.set_controls(tv.stick.x, tv.stick.y, tv.rudder, 0.74, 0.0, false, false)
			tv.flight.step(DT)
			peak = maxf(peak, tv.flight.state().g)
		return peak
	fly.call(5.0)
	set_key(KEY_DOWN, true)
	var peak: float = fly.call(seconds)
	set_key(KEY_DOWN, false)
	return maxf(peak, fly.call(3.0))


func run() -> void:
	Settings().player_flight = 0
	var tv = await start_mission(324)
	tv.frozen = true  # the test steps the flight model itself

	# Press → full deflection at once; release → centre; last event wins.
	set_key(KEY_DOWN, true)
	tv._read_controls(DT)
	check(tv.stick.y == 1.0, "Down arrow: full pull at once (%.2f)" % tv.stick.y)
	set_key(KEY_UP, true)
	tv._read_controls(DT)
	check(tv.stick.y == -1.0, "Up pressed while Down held: full push (the last event wins)")
	set_key(KEY_DOWN, false)
	tv._read_controls(DT)
	check(tv.stick.y == 0.0, "Down released while Up held: centred (the release sends 0)")
	set_key(KEY_UP, false)
	set_key(KEY_RIGHT, true)
	tv._read_controls(DT)
	check(tv.stick == Vector2(1, 0), "Right arrow: full roll at once")
	set_key(KEY_RIGHT, false)
	tv._read_controls(DT)
	check(tv.stick == Vector2.ZERO, "release centres")

	# Tap length → peak g (the lift ramp, ≈ 4.4 g/s at 350 kt): original / real data.
	for real in [false, true]:
		var want := {0.1: 1.44, 0.3: 2.31, 1.0: 5.36} if not real else {0.1: 1.46, 0.3: 2.38, 1.0: 5.61}
		for t in [0.1, 0.3, 1.0]:
			var g := tap_peak_g(tv, real, t)
			check(absf(g - want[t]) < 0.12, "%s data: %.1f s tap → peak %.2f g (≈ %.2f)" % ["real" if real else "original", t, g, want[t]])
