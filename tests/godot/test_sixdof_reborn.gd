# Physics → "Flight model (modern jets)" (docs/deviations.md §2): off, the Sufa in mission 311 flies the original
# model; on, it flies Modern IAF's 6-DoF from the sim's own data and a 1998 jet keeps the original model; without that
# data the row falls back to Original.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_sixdof_reborn.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	# Missing data: the assets folder without the sim's data (a scratch folder), the row on.
	var assets: String = OS.get_environment("IAF_ASSETS_DIR")
	OS.set_environment("IAF_ASSETS_DIR", OS.get_user_data_dir().path_join("no-such-assets"))
	s.flight_model = "6dof"
	check(not s.sixdof_built() and s.sixdof_data() == "", "not built: the row falls back to Original")
	OS.set_environment("IAF_ASSETS_DIR", assets)
	if not s.sixdof_built():
		print("NEEDS DATA: Modern IAF's own flight data (./modern-iaf-setup)")
		await _quit(2)
		return
	s.flight_model = "original"
	s.f16_variant = "sufa"
	var tv = await start_mission(311)
	check(tv.flight.state().get("model") == "original", "row off: the Sufa on the original model")
	s.flight_model = "6dof"
	tv._start_flight()
	check(tv.flight.state().get("model") == "6dof", "row on: the Sufa on the 6-DoF")
	await fly(tv, 3.0)
	var st: Dictionary = tv.flight.state()
	check(st.model == "6dof" and not st.crashed, "row on: 3 s later still the 6-DoF, not crashed")
	# A 1998 jet with the row on, and the Barak (the Sufa switch off): the original model.
	var flags := {"sixdof_data": s.sixdof_data(), "f16_variant": "barak", "f15_variant": "baz"}
	for section in ["F-4", "F-16", "F-15"]:
		var f: Object = ClassDB.instantiate("IafFlight")
		var err: String = f.start(s.own_dir(), section, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, flags)
		check(err == "" and f.state().get("model") == "original", "row on: the 1998 %s keeps the original" % section)
	s.flight_model = "original"
