# Probe (real render): the cockpit world's anti-aliasing (cockpit_origin.gd), MSAA 4× (today) against FXAA, in one
# run over the same still frame. Mission 2012, the flight model stopped, the cockpit world's processing paused so its
# camera holds still; per mode the GPU time of the flight's viewport and the cockpit's over 120 frames, and a picture
# AA_OUT/<mode>.png (compare the HUD and the panel's text with ImageMagick: modern-iaf/docs/cockpit.md §6.2).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 AA_OUT=<dir> -- --log-file <log> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_cockpit_aa_probe.gd
extends "res://../tests/godot/base.gd"

const MODES := {
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED],
	"fxaa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA],
}


func run() -> void:
	settings().blackbox = false  # no training check: it ends the flight once the jet leaves the base
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(60)
	tv.fm_stopped = true
	await frames(60)
	var co: Node = tv.cockpit_origin
	check(co != null, "the sim draws its cockpit about the origin")
	if co == null:
		return
	co.set_process(false)
	var vps: Array[RID] = [tv.get_viewport().get_viewport_rid(), co.viewport.get_viewport_rid()]
	for v in vps:
		RenderingServer.viewport_set_measure_render_time(v, true)
	var out := OS.get_environment("AA_OUT")
	for round in 2:  # twice, interleaved: the laptop's warm-up shows as a difference between the rounds
		for mode in MODES:
			co.viewport.msaa_3d = MODES[mode][0]
			co.viewport.screen_space_aa = MODES[mode][1]
			await frames(30)
			var gpu := [0.0, 0.0]
			for i in 120:
				await RenderingServer.frame_post_draw
				for k in 2:
					gpu[k] += RenderingServer.viewport_get_measured_render_time_gpu(vps[k]) / 120.0
			print(
				(
					"AA %s round %d: GPU the flight's viewport %.2f ms, the cockpit's %.2f ms"
					% [mode, round, gpu[0], gpu[1]]
				)
			)
			if round == 0 and out != "":
				tv.get_viewport().get_texture().get_image().save_png(out.path_join(mode + ".png"))
