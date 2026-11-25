# Dev helper (not run by tools/test.sh): the F-35I's skin from outside (docs/f35i.md §5), for before / after pairs
# of its surface: Scramble's air start from Nevatim (one jet) on a fixed date, held level by the autopilot, the chase
# camera at each pose, every graphics setting at its best. SHOT_OUT names the folder; SHOT_MIN the local start time
# (minutes after midnight; default 660, 11:00; 985 = 16:25, dusk on the date); SHOT_TAG ends each file name
# (<pose>_<tag>.png); SHOT_POSES a comma list of the poses to shoot (default all). Prints "pose <name> gpu <ms>",
# the mean GPU time of 60 frames at each pose. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_TAG=after \
#     -- --log-file <temp> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_surface_shot.gd
extends "res://../tests/godot/base.gd"

## 26 November: Nevatim's sun low in the south-west by 16:25.
const FC := {
	"flight": 1, "home": "Nevatim", "area": "Hatzerim", "seed": 7, "start": "air", "start_day": 330, "year": 2026
}
## name -> [orbit heading (deg, 180 behind), pitch (deg, positive above the jet), distance (m)]
const POSES := [
	["close_rear_quarter", 145.0, 18.0, 15.0],
	["close_side", 92.0, 4.0, 13.0],
	["close_front_quarter", 35.0, 14.0, 14.0],
	["close_top", 175.0, 65.0, 16.0],
	["close_below", 120.0, -28.0, 15.0],
	["mid_rear_quarter", 150.0, 15.0, 35.0],
	["mid_side", 85.0, 6.0, 40.0],
	# The reference photos' angles (docs/f35i.md §5.1): 901 from above on its left, 930 on its right, the pair from below.
	["photo_2016", 260.0, 28.0, 17.0],
	["photo_930", 75.0, 2.0, 18.0],
	["photo_below", 100.0, -60.0, 18.0],
]
const BEST := {
	"object_detail": 1.0,
	"visual_effects": 1.0,
	"shadows": true,
	"antialiasing": "taa",
	"upscaling": "off",
	"models": "detailed",
}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	var s := settings()
	s.show_info = false
	s.language = "en"
	for k in BEST:
		s.set(k, BEST[k])
	var dir := OS.get_environment("SHOT_OUT")
	var tag := OS.get_environment("SHOT_TAG")
	DirAccess.make_dir_recursive_absolute(dir)
	var id := sim_mission("nevatim_free")
	var fc: Dictionary = FC.duplicate()
	fc.start_min = int(_env("SHOT_MIN", "660"))
	check(load("res://flight/fly.gd").prepare_free(id, fc), "Scramble set up")
	s.free_combat = fc
	var tv := await start_mission(id)
	s.mission_files_override = []
	tv.addon.rules = {}  # unscored
	tv.addon.ui.visible = false
	s.invulnerable = true
	tv.gear_down = false
	tv.throttle = 0.55
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	await fly(tv, 2.0)
	await ground_streamed(tv, 30000, 10)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	tv.in_cockpit = false
	var only := _env("SHOT_POSES", "").split(",", false)  # names to shoot (default all)
	for p in POSES:
		if not only.is_empty() and p[0] not in only:
			continue
		tv.views.orbit_heading = deg_to_rad(p[1]) - PI
		tv.views.orbit_pitch = -deg_to_rad(p[2])
		tv.views.dist = p[3]
		tv.views.dmin = minf(tv.views.dmin, p[3])
		await fly(tv, 1.0)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join("%s_%s.png" % [p[0], tag]))
		var gpu := 0.0
		for i in 60:
			await RenderingServer.frame_post_draw
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp) / 60.0
		print("pose %s gpu %.2f ms" % [p[0], gpu])
	check(true, "shots saved")
