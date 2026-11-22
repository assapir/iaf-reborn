# Modern IAF's take-off in pairs (docs/ai.md §8.7, modern-iaf/docs/ai-plan.md F3), headless on mission
# ramon_four_ship through the dev hook ai_flights.gd `flight_pairs`: the tower's start-up clearance starts Kidon 1-2 to
# 1-4; the player's jet is put in the air over the base, so Kidon 1-2 takes off on its own; Kidon 1-3 lines up and
# waits on the runway for Kidon 1-4, which lines up beside it; the two roll together and lift off within seconds of
# each other, more than 10.5 m apart (the F-16's span is 9.45 m) and 10–25 m abreast at Kidon 1-3's lift-off.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_pairs_takeoff.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 6.0

var tv: Node


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


func run() -> void:
	var s := settings()
	var id := sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	tv.addon.rules = {}  # unscored: the lesson's checks would end the flight when the lead is put in the air
	check(tv.ai.flight_pairs(true), "the flight takes off in pairs")
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	check(wing.size() == 3, "Kidon 1-2..1-4 flown by the AI (%d)" % wing.size())
	if wing.size() != 3:
		return
	check(tv.addon.pick("startup") == "ACFT_CLEAR_TO_START", "start-up: the tower clears the flight")
	Engine.time_scale = TIME_SCALE
	await _until(func(): return wing.all(func(e): return bool(e.pilot.flight.state().engine_on)), 120.0)
	# The player's jet in the air 6 km north of the base, 1,500 m up, heading east: Kidon 1-2 taxies once it has moved.
	var w: Vector3 = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y + 6000.0, w.z + 1500.0))
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 90.0), Vector3(190.0, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.6
	var st := func(k: int) -> Dictionary: return wing[k].pilot.flight.state()
	var stage := func(k: int) -> String: return String(wing[k].pilot.flight.ap_stage())
	var rolled := [INF, INF, INF]
	var up := [INF, INF, INF]
	var waited := [false]
	var mates := [INF]
	var abreast := [Vector3.INF]
	var watch := func() -> bool:
		var t: float = tv._sim_time
		for k in 3:
			var on_runway: bool = stage.call(k).begins_with("take-off stage 1")
			if on_runway and float(st.call(k).speed) > 20.0 and rolled[k] == INF:
				rolled[k] = t
			if rolled[k] != INF and not bool(st.call(k).on_ground) and up[k] == INF:
				up[k] = t
				if k == 1:  # Kidon 1-3's lift-off: where Kidon 1-4 is
					abreast[0] = wing[2].world - wing[1].world
		waited[0] = waited[0] or bool(tv.ai.flight_ai.state(3).get("hold", false))
		if rolled[1] != INF and (up[1] == INF or up[2] == INF or t < maxf(up[1], up[2]) + 30.0):
			mates[0] = minf(mates[0], (wing[1].world as Vector3).distance_to(wing[2].world))
		return up[1] != INF and up[2] != INF and t > maxf(up[1], up[2]) + 30.0
	var ok: bool = await _until(watch, 1200.0)
	Engine.time_scale = 1.0
	check(ok and up[0] != INF, "Kidon 1-2, 1-3 and 1-4 airborne (%s s)" % [up])
	check(waited[0], "Kidon 1-3 waited on the runway for Kidon 1-4")
	check(absf(rolled[2] - rolled[1]) < 3.0, "Kidon 1-4 rolled with Kidon 1-3 (%.1f, %.1f s)" % [rolled[1], rolled[2]])
	check(absf(up[2] - up[1]) < 6.0, "Kidon 1-4 lifted off with Kidon 1-3 (%.1f, %.1f s)" % [up[1], up[2]])
	check(mates[0] > 10.5, "Kidon 1-3 and 1-4 more than 10.5 m apart from the roll on (%.1f m)" % mates[0])
	if abreast[0] != Vector3.INF:
		var ibx: Dictionary = s.load_ibx(s.own_dir().path_join("iaf.ibx"))
		var rn := deg_to_rad(float(ibx["Ramon"].RunwayNumber))
		var d: Vector3 = abreast[0]
		var right := d.x * cos(rn) - d.y * sin(rn)
		var ahead := d.x * sin(rn) + d.y * cos(rn)
		check(
			absf(right) > 10.0 and absf(right) < 25.0 and absf(ahead) < 60.0,
			"Kidon 1-4 beside Kidon 1-3 at the lift-off (%.1f m right, %.1f m ahead)" % [right, ahead]
		)
	else:
		check(false, "Kidon 1-3's lift-off seen")
