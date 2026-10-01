extends "res://../tests/godot/base.gd"
func set_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = down
	Input.parse_input_event(e); Input.flush_buffered_events()
func fly(tv, s: float) -> void:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s: await process_frame
func show(tv, what: String) -> void:
	var st: Dictionary = tv.flight.state()
	var v: Vector3 = st.get("velocity", Vector3.ZERO)
	var g := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length())) if v.length() > 1 else 0.0
	print("%s t=%.1f ap=%d stage=%s pitch %.1f gamma %.1f roll %.1f alt %.0f stick %s" % [what, tv._sim_time, tv.autopilot.mode, tv.flight.ap_stage(), st.pitch, g, st.roll, st.alt_ft, tv.stick])
func run() -> void:
	var tv = await start_mission(312)
	await frames(5)
	set_key(KEY_UP, true)   # stick forward (nose down): breaks the autopilot
	await fly(tv, 2.0)
	set_key(KEY_UP, false)
	await fly(tv, 1.0)
	show(tv, "dive")
	key(tv, KEY_A)
	for i in 10:
		await fly(tv, 2.0)
		show(tv, "lvl")
