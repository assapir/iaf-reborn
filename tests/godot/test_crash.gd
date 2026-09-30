# Landing / crash check (docs/flight-model.md §15.6.1): a gentle touchdown with the gear down is a
# landing; a steep dive into the ground fails the check (sink > 80 m/s, nose-down > 10° with Easy
# landing) and destroys the jet. Like the original's player death, the player's destroy event runs,
# the mission fails and the flight ends after 5 s with the debrief (docs/mission-runtime.md §5).
extends "res://../tests/godot/base.gd"


func restart(tv, pos: Vector3, heading: float, velocity: Vector3) -> void:
	var install: String = Settings().assets_dir().path_join("install")
	tv.flight.start(install, "F-16", pos, heading, 0.0, 0.0, velocity, true, true, false)
	var h := tv.aircraft.find_child("height", true, false) as Node3D
	tv.flight.set_gear_clearance(-h.position.y if h != null else 0.0)
	tv.flight.set_easy_landing(true)


func run() -> void:
	var tv = await start_mission(311)
	var ground: float = tv.terrain.height_at(tv.rig.position)
	var hdg := deg_to_rad(150.0)
	var dir := Vector3(sin(hdg), 0, -cos(hdg))
	# Gentle: 80 m/s from 15 m, idle, clean, gear lowered (3.1 s): the jet sinks onto the runway.
	tv.gear_down = true
	tv.throttle = 0.0
	tv.flaps = 0.0
	tv.brakes = false
	restart(tv, tv.rig.position + Vector3(0, ground + 15.0 - tv.rig.position.y, 0), 150.0, dir * 80.0 + Vector3(0, -3, 0))
	var t0 := Time.get_ticks_msec()
	while not tv.flight.state().on_ground and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	var td: Dictionary = tv.flight.state()
	check(td.on_ground, "gentle approach touches down (%.0f kt)" % td.speed_kt)
	await frames(60)
	check(not tv.flight.state().crashed and not tv.crashed, "gentle landing: no crash")
	# Steep: 45° dive at 150 m/s from 150 m (sink 106 m/s).
	restart(tv, tv.rig.position + Vector3(0, 150.0, 0), 150.0, (dir * cos(PI / 4) + Vector3(0, -sin(PI / 4), 0)) * 150.0)
	t0 = Time.get_ticks_msec()
	while not tv.crashed and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	var st: Dictionary = tv.flight.state()
	check(tv.crashed and st.crashed and st.crash_reason == "landing", "steep dive into the ground destroys the jet (%s)" % st.crash_reason)
	check(tv.runtime != null and tv.runtime.failed, "the mission fails (player role 0)")
	var p0: Vector3 = st.position
	await frames(30)
	check(tv.flight.state().position == p0, "the wreck stays put")
	# The flight ends after 5 s and goes to the debrief (event 0x82).
	t0 = Time.get_ticks_msec()
	while current_scene == tv and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	check(current_scene != tv and current_scene.scene_file_path.ends_with("front_end.tscn"), "flight ended (back to the front end)")
	var d: Dictionary = Settings().debrief
	check(String(d.get("headline", "")).begins_with("Mission - failed"), "debrief headline: %s" % d.get("headline", ""))
