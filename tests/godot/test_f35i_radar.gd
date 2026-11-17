# The F-35I's radar power (avionics-plan.md slice 7 part A; docs/radar.md §9.1): the jet has no radar switch, so its
# definition's radar.auto gives the power rules in the 1998 game too. Flown in mission 231 as the cockpit pictures
# fly it, the radar is not OFF: STBY on the ground, then the search by itself once airborne (it read "RADAR OFF" on the
# panoramic display before, 17 Nov). The original F-16 in the same mission keeps the 1998 radar: OFF until Q.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_f35i_radar.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	for f35 in [true, false]:
		settings().f35i_slot = 1 if f35 else -1
		settings().jet_id = 1
		var tv: Node = await start_mission(231)
		await frames(10)
		var w = tv.weapons
		var tag := "F-35I" if f35 else "F-16"
		if f35:
			check(w.radar.mode == 1, "%s on the ground: STBY (mode %d)" % [tag, w.radar.mode])
			# Put in the air as the cockpit pictures do.
			var st0: Dictionary = tv.flight.state()
			var pos: Vector3 = st0.position + Vector3(0, 1500.0, 0)
			tv.rig.position = pos
			tv.flight.start(
				settings().own_dir(),
				tv.player.fm_section,
				pos,
				Vector3(0, 0, st0.heading),
				st0.forward * 200.0,
				airborne_flags()
			)
			tv.gear_down = false
			await frames(10)
			check(
				w.radar.mode in [4, 5, 6], "%s airborne: the radar searches by itself (mode %d)" % [tag, w.radar.mode]
			)
			check(tv.cockpit.radar.get("mode") == w.radar.mode, "%s: the display's snapshot has the mode" % tag)
		else:
			check(w.radar.mode == 0, "%s: the 1998 radar starts OFF (mode %d)" % [tag, w.radar.mode])
	settings().f35i_slot = -1
	settings().jet_id = -1
