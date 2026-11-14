# The release seen by the sim's 6-DoF (finish list W19, modern-iaf/docs/flight-model.md §9.18): the Sufa's take-off
# mission set up as the front end's Fly does, an MK-84 on each wing (stations 3 and 7, the Arming page), the jet put in
# the air 1,500 m above the ground at 200 m/s, hands off. Single release (SGL): one bomb leaves one wing, and
# - the jet's mass drops by the bomb's 925 kg (the 6-DoF's state, through player_weapons.gd _push_stores);
# - the drag index left on the two wings differs by the bomb's (the left / right indices the 6-DoF reads);
# - the lateral moment is the other bomb's, and hands off the jet rolls toward it (more than 3° in 5 s); with both
#   bombs on it is near 0 (the pylons' arms differ by centimetres) and the jet holds its wings.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_release.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


## Hands off for `secs` of sim time: the roll change, degrees.
func _rolled(tv: Node, secs: float) -> float:
	var r0: float = tv.flight.state().roll
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < secs:
		await process_frame
	return float(tv.flight.state().roll) - r0


func run() -> void:
	await require_data()
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", IafBriefing.put(rec, "", 3, "mk-84", true))
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == "ramon_takeoff":
			id = int(k)
	check(load("res://flight/fly.gd").prepare(id), "ramon_takeoff prepared as the front end's Fly")
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	tv.addon.result = {"pass": true}  # the training run checks no more (sim_flight.gd _finish)
	var w = tv.weapons
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 1500.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 200.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.8
	tv.brakes = false
	await frames(10)
	check(tv.flight.state().model == "6dof", "the Sufa flies the 6-DoF")
	w._push_stores()  # the restart above dropped the stores the mission's start gave the flight model
	await frames(2)
	var both := await _rolled(tv, 3.0)
	check(
		absf(w.stores.roll_moment) < 30.0 and absf(both) < 1.0,
		"two MK-84: moment %.0f kg·m, hands off %+.2f° in 3 s" % [w.stores.roll_moment, both]
	)
	var m0: float = tv.flight.state().mass_kg
	var di0 := [w.stores.fm_di_left, w.stores.fm_di_right]
	_press(tv, KEY_BRACKETLEFT)
	await frames(3)
	_press(tv, KEY_A, true, true)
	w.release_pairs = false  # SGL: one store per press
	await frames(3)
	var t: int = w.stores.current_type()
	var before: int = w.stores.total(t, w.stores.current_name())
	_press(tv, KEY_SPACE)
	var t0: float = tv._sim_time
	# Level, the pipper is off the HUD: the delayed release waits for time-to-go 0.9 s (about 35 s here).
	while w.stores.total(t, w.stores.current_name()) == before and tv._sim_time - t0 < 60.0:
		m0 = tv.flight.state().mass_kg  # the last frame before the release
		await process_frame
	_press(tv, KEY_SPACE, false)
	var m1: float = tv.flight.state().mass_kg
	await frames(3)
	check(
		before == 2 and w.stores.total(t, w.stores.current_name()) == 1,
		"SGL: one MK-84 of %d leaves (%d left)" % [before, w.stores.total(t, w.stores.current_name())]
	)
	var dm: float = m0 - m1
	check(absf(dm - 925.0) < 2.0, "the 6-DoF's mass drops %.1f kg at the release (MK-84: 925 kg)" % dm)
	var di := [w.stores.fm_di_left, w.stores.fm_di_right]
	check(
		is_equal_approx(di0[0], di0[1]) and absf(absf(di[0] - di[1]) - 11.8e-4) < 1e-6,
		"drag index left / right %s before, %s after (MK-84: 11.8 × 10⁻⁴)" % [di0, di]
	)
	var moment: float = w.stores.roll_moment
	var one := await _rolled(tv, 5.0)
	check(
		absf(moment) > 900.0 and one * signf(moment) > 3.0,
		"one MK-84: moment %.0f kg·m, hands off %+.1f° in 5 s toward it" % [moment, one]
	)
