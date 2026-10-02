# Every Jet list jet flies (aircraft/player_aircraft.gd, docs/aircraft.md §5): F-15, F-4E, Lavi, Kfir and Mirage
# (the F-16 and the Kurnass 2000 have their own tests). For each: its type, model, cockpit and weapons; on the
# ground (311) the engine starts and it rolls; in the air (312) the gear cycles at 200 kt, the flaps and speed
# brake move, full afterburner lights every engine's flame, and ejection throws one parachuter per crew seat.
extends "res://../tests/godot/base.gd"

## Jet list id -> [type, cockpit folder, twin].
const JETS := {0: [110, "f15", true], 2: [120, "phantom", true], 4: [140, "lavi", false], 5: [130, "cfir", false],
		6: [190, "mirage", false]}


## Ours: the F-35I flown from the Lavi's button (Settings.f35i_slot = 4; F-16 cockpit until it has its own).
const F35I_CASE := [4, [1000, "f16", false]]


func run() -> void:
	var cases := []
	for id in JETS:
		cases.append([id, -1, JETS[id]])
	cases.append([F35I_CASE[0], F35I_CASE[0], F35I_CASE[1]])
	for c in cases:
		var id: int = c[0]
		var want: Array = c[2]
		Settings().f35i_slot = c[1]
		Settings().jet_id = id
		var tv = await start_mission(311)
		var name := "jet %d (type %d)" % [id, want[0]]
		check(tv.player.type == want[0] and tv.aircraft != null and tv.aircraft.type_code == want[0], "%s flies" % name)
		check(tv.cockpit.cockpit_dir.ends_with("/" + want[1]) and tv.cockpit.twin_engines == want[2]
				and tv.player_damage.twin == want[2], "%s: cockpit %s, twin %s" % [name, tv.cockpit.cockpit_dir, want[2]])
		check(tv.weapons != null and tv.weapons.jet_type == want[0], "%s: its weapons" % name)
		key(tv, KEY_1)
		key(tv, KEY_B)
		key(tv, KEY_6)
		var v0: float = tv.flight.state().speed_kt
		await create_timer(6.0).timeout
		var st: Dictionary = tv.flight.state()
		check(st.speed_kt > v0 + 5.0 and st.on_ground and not st.crashed, "%s rolls (%.0f -> %.0f kt)" % [name, v0, st.speed_kt])

		tv = await start_mission(312)
		var ac = tv.aircraft
		check(tv.player.type == want[0] and not tv.gear_down, "%s: 312 in the air" % name)
		var p0: Vector3 = tv.flight.state().position
		var fwd: Vector3 = tv.flight.state().forward
		tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, p0, tv.flight.state().heading,
				0.0, 0.0, fwd * 200.0 * 0.5144, true, true, false)
		key(tv, KEY_G)
		key(tv, KEY_F)
		key(tv, KEY_B)
		await create_timer(4.0).timeout
		check(tv.gear_down and ac.ramps.gear < 0.01, "%s: the gear comes down at 200 kt (ramp %.3f)" % [name, ac.ramps.gear])
		check(tv.flaps > 0.0 and ac.ramps.flaps > 0.1 and ac.ramps.speed_brake > 0.1, "%s: flaps and speed brake" % name)
		key(tv, KEY_8)
		await create_timer(2.0).timeout
		check(not ac.flames.is_empty() and ac.flame_lit(), "%s: full AB lights its flames (%d)" % [name, ac.flames.size()])
		# Crew seats: the model's pilot / pilotB parts (FUN_0053ee90).
		var crew := ["pilot", "pilotB"].filter(func(p): return ac.part_node(p) != null).size()
		for i in 3:
			key(tv, KEY_E)
		var n := 0
		var te := Time.get_ticks_msec()
		while is_instance_valid(tv) and n < crew and Time.get_ticks_msec() - te < 8000:
			n = tv._parachuters.size()
			await process_frame
		check(crew >= 1 and n == crew, "%s: ejection, %d parachuters for %d seats" % [name, n, crew])
	Settings().jet_id = -1
	Settings().f35i_slot = -1
