# Dev helper (not run by tools/test.sh): the Sufa's own shadow and its wingman's on Ramon's runway (Scramble's runway
# start, free_combat.gd), from the chase camera at several distances and heights and from the 3D cockpit looking at
# the left wing, then a low pass (LOW_M over the ground) from behind, with the GPU time of each pose
# (docs/rendering.md §3.1 "The first split"): SHOT_OUT/<pose>.png and a line "pose <name> gpu <ms>" each; SHADOW_AB=1
# also times the fitted split against the scene's 40 m in turns ("AB" lines).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> -- --log-file <t> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_jet_shadow_shot.gd
extends "res://../tests/godot/base.gd"

const FC := {"flight": 2, "area": "Hatzerim", "home": "Ramon", "seed": 7, "start": "runway"}
## name -> [orbit heading (deg, 180 behind), pitch (deg; on the ground the view stays above it), distance (m)]
const POSES := [
	["chase_15m", 150.0, -12.0, 15.0],
	["chase_30m", 150.0, -15.0, 30.0],
	["side_60m", 100.0, -20.0, 60.0],
	["above_120m", 160.0, -45.0, 120.0],
	["cockpit_wing", 0.0, 0.0, 0.0],
	["low_pass_40m", 160.0, 25.0, 45.0],
]
const LOW_M := 40.0


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	var s := settings()
	s.show_info = false
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	var id := sim_mission("ramon_free")
	var fc: Dictionary = FC.duplicate()
	load("res://flight/fly.gd").prepare_free(id, fc)
	s.free_combat = fc
	var tv := await start_mission(id)
	s.mission_files_override = []
	await fly(tv, 3.0)
	var sun := tv.get_node("Sun") as DirectionalLight3D
	print(
		"sun shadows ",
		sun.shadow_enabled,
		" reach ",
		sun.directional_shadow_max_distance,
		" splits ",
		[sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3],
		" atlas ",
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
	)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for p in POSES:
		if p[0].begins_with("low_pass"):
			var w: Vector3 = tv.player_world()
			var g = tv.mission_ground(w)
			var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y, float(g if g != null else 0.0) + LOW_M))
			tv.rig.position = pos
			tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(150, 0, 0), airborne_flags())
			tv.gear_down = false
			tv.throttle = 0.6
			s.invulnerable = true
		if p[0] == "cockpit_wing":
			tv.in_cockpit = true
			tv.views.snap = Vector2(deg_to_rad(110.0), deg_to_rad(5.0))
		else:
			tv.in_cockpit = false
			tv.views.orbit_heading = deg_to_rad(p[1]) - PI
			tv.views.orbit_pitch = -deg_to_rad(p[2])
			tv.views.dist = p[3]
			tv.views.dmin = minf(tv.views.dmin, p[3])
		await fly(tv, 0.2 if p[0].begins_with("low_pass") else 1.0)
		var w0: Vector3 = tv.player_world()
		print("pose %s agl %.0f m" % [p[0], w0.z - float(tv.mission_ground(w0))])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("%s.png" % p[0]))
		var gpu := 0.0
		for i in 60:
			await RenderingServer.frame_post_draw
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp) / 60.0
		if OS.get_environment("SHADOW_AB") != "" and p[0] != "cockpit_wing":
			# The fit against the scene's split in turns, the same frame drawn (the flight paused): GPU ms each.
			var fit := sun.directional_shadow_split_1
			var ab := [[], []]
			tv.set_process(false)
			for r in 6:
				for k in 2:
					sun.directional_shadow_split_1 = fit if k == 1 else 40.0 / sun.directional_shadow_max_distance
					await frames(5)
					var t := 0.0
					for i in 30:
						await RenderingServer.frame_post_draw
						t += RenderingServer.viewport_get_measured_render_time_gpu(vp) / 30.0
					ab[k].append(snappedf(t, 0.01))
			tv.set_process(true)
			print("AB %s scene %s fit %s" % [p[0], ab[0], ab[1]])
		print(
			(
				"pose %s gpu %.2f ms split %.0f m"
				% [p[0], gpu, sun.directional_shadow_split_1 * sun.directional_shadow_max_distance]
			)
		)
	check(true, "shots saved")
