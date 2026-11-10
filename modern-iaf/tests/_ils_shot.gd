# Dev helper (not run by tools/test.sh): the Sufa on Ramon's ILS final (6 km out, a little off the path, the gear
# down) in the 3D cockpit, a real render frozen 3 s after the start, zoomed in to the true size and looking up 7°:
# SHOT_OUT/ils_<SHOT_TAG>.png, the ILS deviations and bar positions printed. The "before" (docs/real-hud.md): the same
# run with sim_settings.gd's hud_subpixel() returning false. The --at start comes from a headless run with PRINT_AT=1:
#   IAF_DEFAULT_SETTINGS=1 PRINT_AT=1 godot --headless --path modern-iaf -s ../modern-iaf/tests/_ils_shot.gd --log-file <t>
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_TAG=after \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_ils_shot.gd -- --at <printed>
extends "res://../tests/godot/base.gd"

const OUT_M := 6000.0
## Off the path: the glide slope 5.2° (a little high), the bearing 0.35° left of the runway heading.
const GLIDE_DEG := 5.2
const OFF_DEG := -0.35


func run() -> void:
	if OS.get_environment("PRINT_AT") == "1":
		var b: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))["Ramon"]
		var hdg := float(b.RunwayNumber)
		var back := deg_to_rad(hdg + 180.0 - OFF_DEG)
		var x := float(b.LineupLocX) + sin(back) * OUT_M
		var y := float(b.LineupLocY) + cos(back) * OUT_M
		var z := float(b.LineupLocZ) + OUT_M * tan(deg_to_rad(GLIDE_DEG))
		print("AT %.1f %.1f %.1f %.1f -3" % [x, y, z, hdg])
		return
	settings().show_info = false
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	tv.gear_down = true  # the handle (the free start's speed is over the gear's limit for the key)
	tv.throttle = 0.3
	tv._throttle_event()
	await create_timer(3.0).timeout
	Engine.time_scale = 0.0
	tv.cockpit.zoom = tv.cockpit.ZOOM_MAX  # the true size: the HUD's pixels at their largest
	tv.views.snap = Vector2(0.0, deg_to_rad(7.0))  # up at the bars
	await frames(30)
	var st: Dictionary = tv.cockpit.state
	var hud = tv.cockpit.hud
	print(
		(
			"ILS %s whole %s exact %s, %.2f px per HUD px"
			% [st.ils, hud.ils_lines(st.ils, hud._field()), 12.0 * st.ils, hud._s]
		)
	)
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join("ils_%s.png" % OS.get_environment("SHOT_TAG")))
	Engine.time_scale = 1.0
	check(true, "shot")
